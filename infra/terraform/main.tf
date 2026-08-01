# AI_SP500 — cloud lakehouse footprint (architecture v0.4)
#
#   terraform init && terraform plan && terraform apply
#
# Everything here bills per request. There is deliberately NOTHING hourly-billed
# in this file — see docs/adr/ADR-003-serverless-over-cluster.md.
#
# Not created here (later phases, see ARCHITECTURE.md §12):
#   - Lambda functions (score / train / dq-assert) — packaged with the pipeline code
#   - Athena DDL — schemas are code in sql/athena/, applied via `make athena-apply`

terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # backend "s3" { ... }   # configure remote state for the portfolio-complete setup
}

provider "aws" {
  region = var.region
  default_tags {
    tags = { project = "ai-sp500", managed_by = "terraform" }
  }
}

# =============================================================================
# S3 — one bucket, prefix-per-layer
# =============================================================================

resource "aws_s3_bucket" "lake" {
  bucket = var.lake_bucket
}

resource "aws_s3_bucket_public_access_block" "lake" {
  bucket                  = aws_s3_bucket.lake.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Versioning protects raw/ against overwrite; noncurrent versions are expired
# below so cost stays bounded.
resource "aws_s3_bucket_versioning" "lake" {
  bucket = aws_s3_bucket.lake.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lake" {
  bucket = aws_s3_bucket.lake.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "lake" {
  bucket = aws_s3_bucket.lake.id

  rule {
    id     = "raw-to-glacier-ir"
    status = "Enabled"
    filter { prefix = "raw/" }
    transition {
      days          = 90
      storage_class = "GLACIER_IR" # replay-only after a quarter
    }
  }

  rule {
    id     = "expire-athena-results"
    status = "Enabled"
    filter { prefix = "athena-results/" }
    expiration { days = 30 }
  }

  rule {
    id     = "housekeeping"
    status = "Enabled"
    filter {} # whole bucket
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
    noncurrent_version_expiration { noncurrent_days = 30 }
  }
}

# =============================================================================
# Glue Data Catalog — the metastore. NO crawlers: schemas are code (sql/athena/).
# =============================================================================

resource "aws_glue_catalog_database" "layers" {
  for_each = toset(["bronze", "silver", "gold", "ops"])
  name     = "ai_sp500_${each.key}"
}

# =============================================================================
# Athena — workgroup with an enforced scan ceiling (the FinOps guardrail)
# =============================================================================

resource "aws_athena_workgroup" "pipeline" {
  name = "ai-sp500"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true
    bytes_scanned_cutoff_per_query     = 1073741824 # 1 GiB: a runaway query is killed, not billed

    result_configuration {
      output_location = "s3://${aws_s3_bucket.lake.bucket}/athena-results/"
      encryption_configuration { encryption_option = "SSE_S3" }
    }

    engine_version { selected_engine_version = "Athena engine version 3" }
  }
}

# =============================================================================
# Edge uploader — the ONLY principal the on-prem side holds.
# PutObject on two prefixes; raw/ is delete-DENIED even to its own writer.
# =============================================================================

resource "aws_iam_user" "edge_uploader" {
  name = "ai-sp500-edge-uploader"
}

resource "aws_iam_user_policy" "edge_uploader" {
  name = "edge-upload-least-privilege"
  user = aws_iam_user.edge_uploader.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "PutToLandingPrefixesOnly"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = [
          "${aws_s3_bucket.lake.arn}/raw/*",
          "${aws_s3_bucket.lake.arn}/bronze/*",
        ]
      },
      {
        Sid      = "ListForWatermarkResume"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [aws_s3_bucket.lake.arn]
        Condition = {
          StringLike = { "s3:prefix" = ["raw/*", "bronze/*"] }
        }
      },
      {
        Sid      = "RawIsImmutable"
        Effect   = "Deny"
        Action   = ["s3:DeleteObject", "s3:DeleteObjectVersion", "s3:PutObjectAcl"]
        Resource = ["${aws_s3_bucket.lake.arn}/*"]
      },
    ]
  })
}

# =============================================================================
# Alerting — SNS terminating at the n8n webhook already used by the edge units
# =============================================================================

resource "aws_sns_topic" "alerts" {
  name = "ai-sp500-alerts"
}

resource "aws_sns_topic_subscription" "n8n" {
  count     = var.n8n_webhook_url == "" ? 0 : 1
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "https"
  endpoint  = var.n8n_webhook_url # n8n must confirm the subscription once
}

resource "aws_budgets_budget" "monthly_cap" {
  name         = "ai-sp500-monthly"
  budget_type  = "COST"
  limit_amount = var.monthly_budget_eur
  limit_unit   = "USD" # budgets bill in USD; treat as ≈ EUR at this magnitude
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_sns_topic_arns  = [aws_sns_topic.alerts.arn]
  }
}

# =============================================================================
# Orchestration — EventBridge Scheduler → Step Functions (native Athena calls)
# =============================================================================

resource "aws_cloudwatch_log_group" "sfn" {
  name              = "/aws/sfn/ai-sp500-daily"
  retention_in_days = 30
}

resource "aws_iam_role" "sfn" {
  name = "ai-sp500-sfn"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "sfn" {
  name = "athena-glue-s3-sns"
  role = aws_iam_role.sfn.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "athena:StartQueryExecution", "athena:GetQueryExecution",
          "athena:GetQueryResults", "athena:StopQueryExecution",
        ]
        Resource = [
          "arn:aws:athena:${var.region}:*:workgroup/${aws_athena_workgroup.pipeline.name}"
        ]
      },
      {
        # Athena's execution role-passthrough: catalog + data access
        Effect = "Allow"
        Action = [
          "glue:GetDatabase", "glue:GetTable", "glue:GetTables", "glue:GetPartitions",
          "glue:UpdateTable", "glue:BatchCreatePartition",
        ]
        Resource = ["*"]
      },
      {
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:ListBucket", "s3:GetBucketLocation", "s3:AbortMultipartUpload"]
        Resource = [aws_s3_bucket.lake.arn, "${aws_s3_bucket.lake.arn}/*"]
      },
      { Effect = "Allow", Action = ["sns:Publish"], Resource = [aws_sns_topic.alerts.arn] },
      {
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = ["arn:aws:lambda:${var.region}:*:function:ai-sp500-*"]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery", "logs:GetLogDelivery", "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery", "logs:ListLogDeliveries", "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies", "logs:DescribeLogGroups",
        ]
        Resource = ["*"]
      },
    ]
  })
}

resource "aws_sfn_state_machine" "daily" {
  name     = "ai-sp500-daily"
  role_arn = aws_iam_role.sfn.arn

  definition = templatefile("${path.module}/../stepfunctions/daily_pipeline.asl.json", {
    workgroup       = aws_athena_workgroup.pipeline.name
    alerts_topic    = aws_sns_topic.alerts.arn
    results_bucket  = aws_s3_bucket.lake.bucket
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn.arn}:*"
    include_execution_data = true
    level                  = "ERROR"
  }
}

resource "aws_iam_role" "scheduler" {
  name = "ai-sp500-scheduler"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "scheduler" {
  name = "start-daily-sfn"
  role = aws_iam_role.scheduler.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["states:StartExecution"]
      Resource = [aws_sfn_state_machine.daily.arn]
    }]
  })
}

# 07:00 UTC — after the 06:15 edge ingest and 06:35 sync have landed in S3.
resource "aws_scheduler_schedule" "daily" {
  name                         = "ai-sp500-daily-0700utc"
  schedule_expression          = "cron(0 7 * * ? *)"
  schedule_expression_timezone = "UTC"
  flexible_time_window { mode = "OFF" }

  target {
    arn      = aws_sfn_state_machine.daily.arn
    role_arn = aws_iam_role.scheduler.arn
    # run_date defaults to "today" inside the machine when empty; pass an
    # explicit date here (or via StartExecution) to backfill idempotently.
    input = jsonencode({ run_date = "" })
  }
}

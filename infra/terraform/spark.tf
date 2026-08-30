# EMR Serverless — the one Spark workload (bulk backfill). See ADR-004.
#
# COST: an EMR Serverless application with NO pre-initialised capacity costs
# nothing while idle. `initial_capacity` is deliberately omitted — adding it
# would put a warm pool on the clock and break v0.4's "nothing hourly-billed"
# property. Billing is per vCPU-hour and GB-hour of actual job runtime, with a
# one-minute minimum per worker.

resource "aws_emrserverless_application" "spark" {
  name          = "ai-sp500-backfill"
  release_label = var.emr_release_label
  type          = "spark"

  # Ceiling so a bad job cannot scale into a surprise. The backfill needs a
  # fraction of this.
  maximum_capacity {
    cpu    = "8 vCPU"
    memory = "32 GB"
  }

  # Stop paying the moment work finishes; cold start is ~60s, irrelevant for a
  # job that runs a handful of times a year.
  auto_stop_configuration {
    enabled              = true
    idle_timeout_minutes = 5
  }
}

resource "aws_iam_role" "emr_job" {
  name = "ai-sp500-emr-job"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "emr-serverless.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "emr_job" {
  name = "lake-read-write-glue"
  role = aws_iam_role.emr_job.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "LakeObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject", "s3:PutObject", "s3:DeleteObject",
          "s3:ListBucket", "s3:GetBucketLocation", "s3:AbortMultipartUpload",
        ]
        Resource = [aws_s3_bucket.lake.arn, "${aws_s3_bucket.lake.arn}/*"]
      },
      {
        # Iceberg commits go through the Glue catalog, so Spark and Athena
        # share one metastore and one table definition.
        Sid    = "IcebergGlueCommits"
        Effect = "Allow"
        Action = [
          "glue:GetDatabase", "glue:GetDatabases",
          "glue:GetTable", "glue:GetTables", "glue:UpdateTable", "glue:CreateTable",
          "glue:GetPartition", "glue:GetPartitions", "glue:BatchCreatePartition",
        ]
        Resource = ["*"]
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
        Resource = ["${aws_cloudwatch_log_group.emr.arn}:*"]
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "emr" {
  name              = "/aws/emr-serverless/ai-sp500"
  retention_in_days = 30
}

output "emr_application_id" {
  value       = aws_emrserverless_application.spark.id
  description = "Pass as --application-id to `aws emr-serverless start-job-run`"
}

output "emr_job_role_arn" {
  value       = aws_iam_role.emr_job.arn
  description = "Pass as --execution-role-arn"
}

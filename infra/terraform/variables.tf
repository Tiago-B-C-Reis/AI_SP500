variable "region" {
  description = "AWS region for the lakehouse"
  type        = string
  default     = "eu-west-1"
}

variable "lake_bucket" {
  description = "S3 bucket name for the data lake (globally unique)"
  type        = string
}

variable "n8n_webhook_url" {
  description = "HTTPS n8n webhook for SNS alert delivery (empty disables the subscription; n8n must confirm it once on first delivery)"
  type        = string
  default     = ""
}

variable "monthly_budget_eur" {
  description = "Monthly cost alarm threshold"
  type        = string
  default     = "5"
}

output "edge_uploader_name" {
  value       = aws_iam_user.edge_uploader.name
  description = "Create one access key for this user and place it ONLY in the MP9 /opt/ai_sp500/.env"
}

output "state_machine_arn" {
  value = aws_sfn_state_machine.daily.arn
}

output "athena_workgroup" {
  value = aws_athena_workgroup.pipeline.name
}

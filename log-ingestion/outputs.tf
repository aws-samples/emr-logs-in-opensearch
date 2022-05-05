output "emr_logs_s3_bucket_name" {
  value = aws_s3_bucket.emr_logs.bucket
}

output "emr_log_files_sqs_queue_arn" {
  value = aws_sqs_queue.emr_log_files.arn
}

output "log_ingestion_lambda_arn" {
  value = aws_lambda_function.log_ingestion.arn
}

output "log_ingestion_lambda_role_arn" {
  value = aws_iam_role.log_ingestion.arn
}

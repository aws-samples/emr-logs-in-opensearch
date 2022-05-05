resource "aws_sqs_queue" "emr_log_files" {
  name = "${var.name_prefix}-emr-log-files"

  message_retention_seconds = 60 * 60 * 24 * 7 # 7 days
  visibility_timeout_seconds = 60

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.emr_log_files_failed.arn
    maxReceiveCount = 2
  })

  sqs_managed_sse_enabled = true
}

resource "aws_sqs_queue_policy" "emr_log_files" {
  queue_url = aws_sqs_queue.emr_log_files.id
  policy = data.aws_iam_policy_document.emr_log_files_sqs_queue.json
}

data "aws_iam_policy_document" "emr_log_files_sqs_queue" {
  statement {
    effect = "Allow"
    principals {
      type = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
    actions = [
      "sqs:SendMessage"
    ]
    resources = [
      aws_sqs_queue.emr_log_files.arn
    ]
    condition {
      test = "ArnEquals"
      variable = "aws:SourceArn"
      values = [
        aws_s3_bucket.emr_logs.arn
      ]
    }
    condition {
      test = "StringEquals"
      variable = "aws:SourceAccount"
      values = [
        local.aws_account_id
      ]
    }
  }
}

# Dead Letter Queue
resource "aws_sqs_queue" "emr_log_files_failed" {
  name = "${var.name_prefix}-emr-log-files-failed"

  message_retention_seconds = 60 * 60 * 24 * 7 # 7 days
  visibility_timeout_seconds = 60

  sqs_managed_sse_enabled = true
}

# Consume emr_log_files queue messages in emr_log_extractor lambda
resource "aws_lambda_event_source_mapping" "send_emr_log_file_queue_messages_to_log_ingestion" {
  event_source_arn = aws_sqs_queue.emr_log_files.arn
  function_name = aws_lambda_function.log_ingestion.arn
  batch_size = 1
}

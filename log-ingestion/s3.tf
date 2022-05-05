resource "aws_s3_bucket" "emr_logs" {
  bucket = "${var.name_prefix}-emr-logs-${local.aws_account_id}-${local.aws_region}"
}

resource "aws_s3_bucket_policy" "emr_logs" {
  bucket = aws_s3_bucket.emr_logs.id
  policy = data.aws_iam_policy_document.emr_logs.json
}

data "aws_iam_policy_document" "emr_logs" {
  statement {
    principals {
      type = "*"
      identifiers = ["*"]
    }
    effect = "Deny"
    actions = [
      "s3:*"
    ]
    resources = [
      aws_s3_bucket.emr_logs.arn,
      "${aws_s3_bucket.emr_logs.arn}/*",
    ]
    condition {
      test = "Bool"
      variable = "aws:SecureTransport"
      values = ["false"]
    }
  }
}

resource "aws_s3_bucket_public_access_block" "emr_logs" {
  bucket = aws_s3_bucket.emr_logs.id

  block_public_acls = true
  ignore_public_acls = true
  block_public_policy = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "emr_logs" {
  bucket = aws_s3_bucket.emr_logs.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_notification" "emr_logs" {
  bucket = aws_s3_bucket.emr_logs.id

  queue {
    id = "emr-log-stdout-file-created"
    queue_arn = aws_sqs_queue.emr_log_files.arn
    events = ["s3:ObjectCreated:*"]
    filter_prefix = var.log_bucket_key_prefix
    filter_suffix = "stdout.gz"
  }

  queue {
    id = "emr-log-stderr-file-created"
    queue_arn = aws_sqs_queue.emr_log_files.arn
    events = ["s3:ObjectCreated:*"]
    filter_prefix = var.log_bucket_key_prefix
    filter_suffix = "stderr.gz"
  }
}


# VPC Endpoint for S3
resource "aws_vpc_endpoint" "s3" {
  count = length(data.aws_elasticsearch_domain.logs.vpc_options) > 0 ? 1 : 0

  vpc_id = data.aws_elasticsearch_domain.logs.vpc_options[0].vpc_id
  service_name = "com.amazonaws.${local.aws_region}.s3"
}

data "aws_vpc" "for_s3_endpoint" {
  count = length(data.aws_elasticsearch_domain.logs.vpc_options) > 0 ? 1 : 0

  id = data.aws_elasticsearch_domain.logs.vpc_options[0].vpc_id
}

resource "aws_vpc_endpoint_route_table_association" "for_s3_endpoint" {
  count = length(data.aws_vpc.for_s3_endpoint) > 0 ? 1 : 0

  vpc_endpoint_id = aws_vpc_endpoint.s3[0].id
  route_table_id = data.aws_vpc.for_s3_endpoint[0].main_route_table_id
}

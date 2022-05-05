locals {
  lambda_source_dir = abspath("${path.module}/ingestion-lambda")
  lambda_package_file = "${local.lambda_source_dir}.zip"
}

resource "null_resource" "build_log_ingestion_lambda_package" {
  triggers = {
    timestamp = timestamp()
    lambda_package_file = local.lambda_package_file
  }

  provisioner "local-exec" {
    on_failure = fail
    command = <<-COMMAND
      build_dir="${local.lambda_source_dir}_package-build"
      mkdir -p "$build_dir"
      rm -rf "$build_dir/*"

      python3 -m pip install -q -r "${local.lambda_source_dir}/requirements.txt" --target "$build_dir"
      cp "${local.lambda_source_dir}"/*.py "$build_dir"

      pushd "$build_dir"
      zip "${local.lambda_package_file}" -rq *
      popd

      rm -rf "$build_dir"
    COMMAND
  }
}

resource "aws_lambda_function" "log_ingestion" {
  function_name = "${var.name_prefix}-log-ingestion"

  filename = local.lambda_package_file
  source_code_hash = filebase64sha256(null_resource.build_log_ingestion_lambda_package.triggers.lambda_package_file)

  handler = "main.lambda_handler"
  runtime = "python3.9"
  timeout = 60

  role = aws_iam_role.log_ingestion.arn

  vpc_config {
    subnet_ids = flatten(data.aws_elasticsearch_domain.logs.vpc_options.*.subnet_ids)
    security_group_ids = flatten(data.aws_elasticsearch_domain.logs.vpc_options.*.security_group_ids)
  }

  environment {
    variables = {
      OPENSEARCH_ENDPOINT = data.aws_elasticsearch_domain.logs.endpoint
    }
  }

  depends_on = [
    null_resource.build_log_ingestion_lambda_package
  ]
}

resource "aws_iam_role" "log_ingestion" {
  name = "${var.name_prefix}-log-ingestion-${local.aws_region}"
  assume_role_policy = data.aws_iam_policy_document.log_ingestor_assume_role.json
}

data "aws_iam_policy_document" "log_ingestor_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role_policy_attachment" "log_ingestor_role_policy_attachment_lambda_vpc" {
  role = aws_iam_role.log_ingestion.id
  policy_arn = "arn:${local.aws_partition}:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "log_ingestion" {
  name = "${var.name_prefix}-log-ingestion-${local.aws_region}"
  role = aws_iam_role.log_ingestion.id
  policy = data.aws_iam_policy_document.log_ingestion.json
}

data "aws_iam_policy_document" "log_ingestion" {
  statement {
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
    ]
    resources = [
      aws_sqs_queue.emr_log_files.arn
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.emr_logs.arn
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject"
    ]
    resources = [
      "${aws_s3_bucket.emr_logs.arn}/*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "es:ESHttpPost"
    ]
    resources = [
      "${data.aws_elasticsearch_domain.logs.arn}/_bulk"
    ]
  }
}

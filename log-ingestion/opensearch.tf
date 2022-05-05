data "aws_elasticsearch_domain" "logs" {
  domain_name = var.opensearch_domain_name
}

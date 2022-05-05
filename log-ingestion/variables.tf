variable "name_prefix" {
  description = "Prefix for resource names."
  type = string
}

variable "log_bucket_key_prefix" {
  description = "Object key (path) prefix for EMR log files in the log bucket."
  type = string
}

variable "opensearch_domain_name" {
  description = "Name of the OpenSearch domain for storing the logs into."
  type = string
}

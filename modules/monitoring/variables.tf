variable "project" { type = string }
variable "region" { type = string }
variable "account_id" { type = string }

variable "alert_email" {
  description = "Address subscribed to the alerts SNS topic (reuses the infra contact email)"
  type        = string
}

variable "instance_id" {
  description = "Backend EC2 instance the disk alarm and drift check target"
  type        = string
}

variable "parameter_path_prefix" {
  description = "SSM path prefix (e.g. /enviable/prod); BACKEND_IMAGE lives under it"
  type        = string
}

variable "backend_container_name" {
  description = "Running backend container name on the box"
  type        = string
  default     = "enviable-backend-1"
}

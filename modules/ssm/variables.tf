variable "project" {
  type = string
}

variable "default_initial_password" {
  type      = string
  sensitive = true
}

variable "database_url" {
  type      = string
  sensitive = true
}

variable "redis_url" {
  type = string
}

variable "s3_bucket" {
  type = string
}

variable "region" {
  type = string
}

variable "invoice_config" {
  type = map(string)
}

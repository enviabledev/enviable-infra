variable "project" {
  type    = string
  default = "enviable"
}

variable "region" {
  type    = string
  default = "eu-north-1"
}

variable "backend_domain" {
  type    = string
  default = "api.enviabletricycle.com"
}

variable "caddy_email" {
  description = "Email for Let's Encrypt registration via Caddy"
  type        = string
}

variable "github_org" {
  description = "GitHub org/user that owns the repos"
  type        = string
}

variable "github_repo_backend" {
  description = "Repo name for enviable-system"
  type        = string
  default     = "enviable-system"
}

variable "github_repo_infra" {
  description = "Repo name for enviable-infra"
  type        = string
  default     = "enviable-infra"
}

variable "default_initial_password" {
  description = "DEFAULT_INITIAL_PASSWORD for backend user creation"
  type        = string
  sensitive   = true
}

variable "db_name" {
  type    = string
  default = "enviable"
}

variable "db_username" {
  type    = string
  default = "enviable_admin"
}

variable "invoice_config" {
  description = "Non-secret invoice profile vars passed to the backend"
  type        = map(string)
  default = {
    INVOICE_COMPANY_NAME     = "Enviable Tricycle Auto Parts Ltd"
    INVOICE_DEFAULT_NET_DAYS = "14"
    INVOICE_SALES_CURRENCY   = "NGN"
  }
}

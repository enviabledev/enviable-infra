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
  description = "Non-secret backend config written to SSM as plain String params: company/invoice profile, Globus bank routing, and the customer warranty term. These print on customer-facing invoices, so they are not treated as secrets (see modules/ssm)."
  type        = map(string)
  default = {
    # Company identity — issuer block on every invoice / proforma.
    INVOICE_COMPANY_NAME    = "Enviable Tricycle Auto Parts Limited"
    INVOICE_COMPANY_ADDRESS = "52 Saka Tinubu Street, VI Lagos"
    INVOICE_COMPANY_EMAIL   = "info@enviabletricycle.com"
    INVOICE_COMPANY_RC      = "6987445"
    INVOICE_COMPANY_TIN     = "31405903-0001"
    # INVOICE_COMPANY_TEL intentionally unset: no company phone supplied for
    # launch. The document omits the Tel line when blank; set once Theresa
    # provides a real line.

    # Globus Bank routing — distinct registered account per wheeler class.
    # INVOICE_BANK_*_SORT_CODE intentionally unset: Nigerian NIP transfers route
    # on bank name + account number alone, and the bank supplied no sort code.
    INVOICE_BANK_3W_NAME           = "Globus Bank"
    INVOICE_BANK_3W_ACCOUNT_NAME   = "Enviable Tricycle Auto Parts Limited Account 2"
    INVOICE_BANK_3W_ACCOUNT_NUMBER = "1000503348"
    INVOICE_BANK_2W_NAME           = "Globus Bank"
    INVOICE_BANK_2W_ACCOUNT_NAME   = "Enviable Tricycles Auto Parts Ltd - 2 Wheeler"
    INVOICE_BANK_2W_ACCOUNT_NUMBER = "1000579033"

    # Invoice terms.
    INVOICE_DEFAULT_NET_DAYS = "14"
    INVOICE_SALES_CURRENCY   = "NGN"

    # Customer warranty term (months) printed on returns / warranty docs.
    CUSTOMER_WARRANTY_MONTHS = "12"
  }
}

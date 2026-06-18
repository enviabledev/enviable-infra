variable "project" { type = string }
variable "db_name" { type = string }
variable "db_username" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "rds_security_group_id" { type = string }

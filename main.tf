data "aws_caller_identity" "current" {}

module "network" {
  source  = "./modules/network"
  project = var.project
}

module "storage" {
  source     = "./modules/storage"
  project    = var.project
  account_id = data.aws_caller_identity.current.account_id
}

module "ecr" {
  source  = "./modules/ecr"
  project = var.project
}

module "database" {
  source                = "./modules/database"
  project               = var.project
  db_name               = var.db_name
  db_username           = var.db_username
  private_subnet_ids    = module.network.private_subnet_ids
  rds_security_group_id = module.network.rds_security_group_id
}

module "ssm" {
  source                   = "./modules/ssm"
  project                  = var.project
  region                   = var.region
  default_initial_password = var.default_initial_password
  database_url             = module.database.database_url
  redis_url                = "redis://redis:6379"
  s3_bucket                = module.storage.bucket_name
  invoice_config           = var.invoice_config
}

module "iam" {
  source                = "./modules/iam"
  project               = var.project
  region                = var.region
  account_id            = data.aws_caller_identity.current.account_id
  bucket_arn            = module.storage.bucket_arn
  ecr_repository_arn    = module.ecr.repository_arn
  parameter_path_prefix = module.ssm.parameter_path_prefix
}

module "compute" {
  source                = "./modules/compute"
  project               = var.project
  public_subnet_id      = module.network.public_subnet_id
  ec2_security_group_id = module.network.ec2_security_group_id
  instance_profile_name = module.iam.instance_profile_name
}

module "cicd" {
  source                = "./modules/cicd"
  project               = var.project
  region                = var.region
  account_id            = data.aws_caller_identity.current.account_id
  github_org            = var.github_org
  github_repo_backend   = var.github_repo_backend
  github_repo_infra     = var.github_repo_infra
  ecr_repository_arn    = module.ecr.repository_arn
  bucket_arn            = module.storage.bucket_arn
  parameter_path_prefix = module.ssm.parameter_path_prefix
  instance_id           = module.compute.instance_id
}

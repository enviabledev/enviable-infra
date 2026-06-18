output "elastic_ip" {
  value = module.compute.public_ip
}

output "instance_id" {
  value = module.compute.instance_id
}

output "s3_bucket" {
  value = module.storage.bucket_name
}

output "ecr_repository_url" {
  value = module.ecr.repository_url
}

output "rds_endpoint" {
  value     = module.database.endpoint
  sensitive = true
}

output "ssm_prefix" {
  value = module.ssm.parameter_path_prefix
}

output "backend_deploy_role_arn" {
  value = module.cicd.backend_deploy_role_arn
}

output "infra_role_arn" {
  value = module.cicd.infra_role_arn
}

output "dns_records_to_add" {
  value = <<-EOT
    Add these at your current DNS provider (zone NOT migrated):
      api    A      ${module.compute.public_ip}
      portal CNAME  <target Vercel gives you for the project>
  EOT
}

output "parameter_path_prefix" {
  value = local.prefix
}

output "session_secret" {
  value     = random_password.session_secret.result
  sensitive = true
}

output "endpoint" { value = aws_db_instance.this.endpoint }
output "address" { value = aws_db_instance.this.address }
output "port" { value = aws_db_instance.this.port }

output "database_url" {
  value     = "postgresql://${var.db_username}:${random_password.db.result}@${aws_db_instance.this.address}:${aws_db_instance.this.port}/${var.db_name}?schema=public"
  sensitive = true
}

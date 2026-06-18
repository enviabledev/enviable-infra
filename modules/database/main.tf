resource "random_password" "db" {
  length  = 32
  special = false # avoid URL-encoding issues in DATABASE_URL
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.project}-db-subnet"
  subnet_ids = var.private_subnet_ids
  tags       = { Name = "${var.project}-db-subnet" }
}

resource "aws_db_instance" "this" {
  identifier     = "${var.project}-postgres"
  engine         = "postgres"
  engine_version = "16"
  instance_class = "db.t3.micro"

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.rds_security_group_id]
  publicly_accessible    = false
  multi_az               = false

  backup_retention_period   = 7
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.project}-postgres-final"

  apply_immediately = true
}

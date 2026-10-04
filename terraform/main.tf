# Uses the account's default VPC on purpose: no NAT gateway, no interface
# endpoints, nothing that bills by the hour except the database itself.

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

locals {
  restoring = var.snapshot_identifier != null

  # The workflow passes an empty string when the AZ input is left blank.
  az = (var.availability_zone == null || var.availability_zone == "") ? null : var.availability_zone
}

resource "aws_db_subnet_group" "pilot" {
  name       = "${var.identifier}-subnets"
  subnet_ids = data.aws_subnets.default.ids
}

resource "aws_security_group" "pilot" {
  name        = "${var.identifier}-sg"
  description = "Postgres access for ${var.identifier}"
  vpc_id      = data.aws_vpc.default.id
}

resource "aws_vpc_security_group_ingress_rule" "postgres" {
  security_group_id = aws_security_group.pilot.id
  description       = "Postgres from allowed_cidr"
  cidr_ipv4         = var.allowed_cidr
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
}

resource "aws_db_instance" "pilot" {
  identifier = var.identifier

  engine            = "postgres"
  engine_version    = var.engine_version
  instance_class    = var.instance_class
  availability_zone = local.az

  allocated_storage = var.allocated_storage
  storage_type      = var.storage_type
  storage_encrypted = true # default aws/rds key, so no customer KMS key to manage

  # Fresh instance: RDS creates and stores the master password in Secrets Manager.
  # Restore: credentials come from the snapshot.
  snapshot_identifier         = var.snapshot_identifier
  db_name                     = local.restoring ? null : var.db_name
  username                    = local.restoring ? null : var.master_username
  manage_master_user_password = local.restoring ? null : true

  db_subnet_group_name   = aws_db_subnet_group.pilot.name
  vpc_security_group_ids = [aws_security_group.pilot.id]
  publicly_accessible    = var.publicly_accessible

  # Database Insights - Standard, 7-day retention (free tier of Performance Insights).
  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  backup_retention_period    = var.backup_retention_period
  auto_minor_version_upgrade = true
  copy_tags_to_snapshot      = true
  apply_immediately          = true
  deletion_protection        = false

  # Teardown behavior.
  skip_final_snapshot       = !var.keep_data_on_destroy
  final_snapshot_identifier = var.keep_data_on_destroy ? "${var.identifier}-final" : null
  delete_automated_backups  = true
}

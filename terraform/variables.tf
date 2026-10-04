variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "identifier" {
  description = "DB instance identifier."
  type        = string
  default     = "pilot-test-pg"
}

variable "engine_version" {
  description = "PostgreSQL engine version."
  type        = string
  default     = "17.5"
}

variable "instance_class" {
  description = "DB instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Storage in GiB (gp2)."
  type        = number
  default     = 20
}

variable "availability_zone" {
  description = "AZ for the instance."
  type        = string
  default     = "us-east-1b"
}

variable "db_name" {
  description = "Initial database name (ignored when restoring from a snapshot)."
  type        = string
  default     = "test"
}

variable "master_username" {
  description = "Master username (ignored when restoring from a snapshot)."
  type        = string
  default     = "rravala"
}

variable "allowed_cidr" {
  description = "Your public IP as a /32 (for example 203.0.113.7/32). Only this range can reach port 5432."
  type        = string

  validation {
    condition     = can(cidrhost(var.allowed_cidr, 0))
    error_message = "allowed_cidr must be a valid CIDR block, for example 203.0.113.7/32."
  }
}

variable "publicly_accessible" {
  description = "Give the instance a public IP so SCT/DMS/psql can reach it from outside AWS. Costs about $3.60/month for the IPv4 address."
  type        = bool
  default     = true
}

variable "backup_retention_period" {
  description = "Automated backup retention in days (0 disables backups)."
  type        = number
  default     = 1
}

variable "keep_data_on_destroy" {
  description = "Take a final snapshot named <identifier>-final when destroying. Delete the previous one first, or the next destroy will fail."
  type        = bool
  default     = false
}

variable "snapshot_identifier" {
  description = "Restore the instance from this snapshot instead of creating an empty database. Leave null for a fresh instance."
  type        = string
  default     = null
}

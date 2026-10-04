output "endpoint" {
  description = "Hostname and port for connecting."
  value       = aws_db_instance.pilot.endpoint
}

output "address" {
  description = "Hostname only."
  value       = aws_db_instance.pilot.address
}

output "port" {
  value = aws_db_instance.pilot.port
}

output "master_secret_arn" {
  description = "Secrets Manager secret holding the master password (empty when restored from a snapshot)."
  value       = try(aws_db_instance.pilot.master_user_secret[0].secret_arn, null)
}

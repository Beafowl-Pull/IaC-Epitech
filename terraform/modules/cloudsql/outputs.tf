output "instance_connection_name" {
  value = google_sql_database_instance.main.connection_name
}

output "private_ip" {
  value     = google_sql_database_instance.main.private_ip_address
  sensitive = true
}

output "db_password" {
  value     = random_password.db_password.result
  sensitive = true
}

output "secret_manager_secret_id" {
  description = "Secret Manager secret ID where the DB password is stored"
  value       = google_secret_manager_secret.db_password.secret_id
}

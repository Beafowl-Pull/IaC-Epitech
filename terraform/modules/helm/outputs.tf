output "task_manager_release_status" {
  value = helm_release.task_manager.status
}

output "traefik_release_status" {
  value = helm_release.traefik.status
}

output "cert_manager_release_status" {
  value = helm_release.cert_manager.status
}

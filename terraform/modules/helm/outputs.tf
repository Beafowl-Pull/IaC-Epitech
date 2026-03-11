output "task_manager_release_status" {
  value = helm_release.task_manager.status
}

output "ingress_nginx_release_status" {
  value = helm_release.ingress_nginx.status
}

output "cert_manager_release_status" {
  value = helm_release.cert_manager.status
}

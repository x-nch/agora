output "nginx_ingress_namespace" {
  description = "Namespace for NGINX ingress"
  value       = "ingress-nginx"
}

output "cert_manager_namespace" {
  description = "Namespace for cert-manager"
  value       = "cert-manager"
}

output "external_dns_namespace" {
  description = "Namespace for ExternalDNS"
  value       = "external-dns"
}

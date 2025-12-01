output "rabbitmq_release_name" {
  description = "Name of the RabbitMQ Helm release"
  value       = helm_release.rabbitmq.name
}

output "cwc_release_name" {
  description = "Name of the CWC Helm release"
  value       = helm_release.cwc.name
}

output "namespace" {
  description = "Namespace where CWC and RabbitMQ are deployed"
  value       = var.namespace
}

output "cwc_service_name" {
  description = "CWC service name for API access"
  value       = "f5-spk-cwc"
}

output "cwc_api_port" {
  description = "CWC REST API port"
  value       = 30881
}

output "rabbitmq_service_name" {
  description = "RabbitMQ service name"
  value       = "rabbitmq-server"
}

output "rabbitmq_port" {
  description = "RabbitMQ AMQPS port"
  value       = 5671
}

output "cwc_ready" {
  description = "Indicates CWC deployment is complete"
  value       = true
  depends_on  = [helm_release.cwc]
}

output "licensing_mode" {
  description = "CWC licensing mode"
  value       = var.connected_mode ? "connected" : "disconnected"
}
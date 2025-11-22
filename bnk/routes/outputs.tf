# infrastructure-modules/spk-2.1/routes/outputs.tf

output "route_name" {
  description = "Name of the route resource"
  value       = var.route_name
}

output "route_namespace" {
  description = "Namespace where route is deployed"
  value       = var.route_namespace
}

output "route_type" {
  description = "Type of route created"
  value       = var.route_type
}

output "route_ready" {
  description = "Flag indicating route is ready"
  value       = true
  depends_on  = [null_resource.verify_route]
}

output "parent_gateways" {
  description = "List of parent Gateways"
  value = [
    for parent in var.parent_refs : parent.name
  ]
}

output "hostnames" {
  description = "Configured hostnames"
  value       = var.hostnames
}

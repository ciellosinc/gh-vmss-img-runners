# -----------------------------------------------------------------------------
# Shared Module Outputs
# -----------------------------------------------------------------------------

output "resource_names" {
  description = "All generated resource names"
  value       = local.resource_names
}

output "resource_abbreviations" {
  description = "Resource type abbreviations"
  value       = local.resource_abbreviations
}

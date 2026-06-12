# -----------------------------------------------------------------------------
# Shared Module Variables
# -----------------------------------------------------------------------------

variable "app" {
  type        = string
  description = "Application name identifier"
}

variable "environment" {
  type        = string
  description = "Environment name (dev, test, prod)"
}

variable "region" {
  type        = string
  description = "Region abbreviation for resource naming"
}

variable "unique_suffix" {
  type        = string
  description = "Unique suffix for globally unique resource names"
  default     = ""
}

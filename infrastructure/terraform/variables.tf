variable "environment" {
  type    = string
  default = "production"
  validation {
    condition     = contains(["development", "production"], var.environment)
    error_message = "Must be development or production."
  }
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "jwt_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "jwt_key_users" {
  type      = string
  sensitive = true
}

variable "jwt_key_catalog" {
  type      = string
  sensitive = true
}

variable "jwt_key_payments" {
  type      = string
  sensitive = true
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "rmq_password" {
  type      = string
  sensitive = true
}

variable "jwt_issuer" {
  type    = string
  default = "https://fiapcloudgames.com"
}

variable "jwt_audience" {
  type    = string
  default = "FiapCloudGames"
}

variable "dd_api_key" {
  type      = string
  sensitive = true
}

variable "dd_app_key" {
  type        = string
  sensitive   = true
  description = "Datadog Application Key — Settings → API Keys → New App Key"
}

variable "dd_site" {
  type    = string
  default = "datadoghq.com"
}

variable "dd_extension_version" {
  type    = string
  default = "62"
}

variable "datadog_external_id" {
  type        = string
  description = "External ID do Datadog AWS Integration (obtido na UI do Datadog)"
  default     = "fiapcloudgames-dd-integration"
}

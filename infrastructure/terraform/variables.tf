variable "environment" {
  type    = string
  default = "prd"
  validation {
    # dev / prd = provisionados no Learner Lab; homolog fica documentado (não provisionado) —
    # ver specs/phase2/00-overview.md e 10-environments.md.
    condition     = contains(["dev", "homolog", "prd"], var.environment)
    error_message = "Must be dev, homolog or prd."
  }
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "jwt_rsa_private_key" {
  type        = string
  sensitive   = true
  description = "Chave RSA privada (base64 PEM) usada pela UsersAPI para assinar tokens. Gerada por infrastructure/scripts/generate-jwt-keys.sh"
}

variable "jwt_rsa_public_key" {
  type        = string
  sensitive   = false
  description = "Chave RSA pública (base64 PEM) usada pelas 3 APIs e pelo API Gateway (via JWKS) para validar tokens."
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


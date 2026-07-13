variable "region" {
  type    = string
  default = "us-east-1"
}

variable "cluster_name" {
  type    = string
  default = "fcg-eks" # cluster ÚNICO; ambientes = namespaces (fcg-dev/fcg-prd)
}

variable "kubernetes_version" {
  type    = string
  default = "1.30"
}

# Learner Lab: NÃO criamos roles (iam:CreateRole negado). Tudo reusa o LabRole.
variable "lab_role_arn" {
  type    = string
  default = "arn:aws:iam::667079134782:role/LabRole"
}

variable "node_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "node_desired" {
  type    = number
  default = 2
}

variable "node_min" {
  type    = number
  default = 1
}

variable "node_max" {
  type    = number
  default = 3
}

# Namespaces por ambiente (Learner Lab: dev + prd)
variable "namespaces" {
  type    = list(string)
  default = ["fcg-dev", "fcg-prd"]
}

variable "ecr_repos" {
  type    = list(string)
  default = ["users-api", "catalog-api", "payments-api"]
}

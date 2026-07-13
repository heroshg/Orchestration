# Root Terraform da PLATAFORMA (spec 01) — Learner Lab.
# Isolado do Terraform ECS legado em ../infrastructure/terraform.
# State remoto no S3 criado no Estágio 0.

terraform {
  required_version = ">= 1.7"

  backend "s3" {
    bucket         = "fcg-tfstate-667079134782"
    key            = "platform/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "fcg-tflock"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

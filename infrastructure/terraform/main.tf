terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    datadog = {
      source  = "DataDog/datadog"
      version = "~> 3.39"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "datadog" {
  api_key = var.dd_api_key
  app_key = var.dd_app_key
  api_url = "https://api.${var.dd_site}/"
}

data "aws_caller_identity" "current" {}

locals {
  name_prefix = "fcg-${var.environment}"
  common_tags = {
    Project     = "FiapCloudGames"
    Environment = var.environment
  }
}

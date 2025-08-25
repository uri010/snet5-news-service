terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.92"
    }
  }

  required_version = ">= 1.2"
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "Terraform"
    }
  }
}

# 현재 AWS 계정 정보
data "aws_caller_identity" "current" {}

# 현재 region 정보
data "aws_region" "current" {}

# EKS 서비스 계정을 위한 OIDC thumbprint
# (EKS 클러스터 생성 후 별도 파일에서 정의할 예정)
# data "tls_certificate" "eks" {
#   depends_on = [aws_eks_cluster.main]
#   url        = aws_eks_cluster.main.identity[0].oidc[0].issuer
# }
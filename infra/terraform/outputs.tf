# Project Information
output "project_name" {
  description = "Project name"
  value       = "news-service"
}

output "environment" {
  description = "Environment"
  value       = "dev"
}

output "region" {
  description = "AWS region"
  value       = "ap-northeast-2"
}

# Network Information
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = "10.0.0.0/16"
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = aws_subnet.private[*].id
}

# EKS Information
output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = aws_eks_cluster.main.endpoint
}

output "eks_cluster_version" {
  description = "EKS cluster version"
  value       = "1.28"
}

output "node_group_instance_type" {
  description = "EKS node group instance type"
  value       = "t3.small"
}

# Storage Information
output "static_website_bucket" {
  description = "Static website S3 bucket name"
  value       = "news-service-dev-static-${data.aws_caller_identity.current.account_id}"
}

output "images_bucket" {
  description = "Images S3 bucket name"
  value       = "news-service-dev-images-${data.aws_caller_identity.current.account_id}"
}

# CloudFront Information
output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.main.id
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "custom_domain" {
  description = "Custom domain name"
  value       = "ioinews.shop"
}

# Database Information
output "dynamodb_table_name" {
  description = "DynamoDB table name"
  value       = "naver_news_articles"
}

# Security Information
output "waf_web_acl_id" {
  description = "WAF Web ACL ID"
  value       = aws_wafv2_web_acl.main.id
}

# Cost Estimation
output "estimated_monthly_cost" {
  description = "Estimated monthly cost breakdown"
  value = {
    eks_control_plane = "$72"
    ec2_nodes         = "$60"
    nat_instance      = "$8.5"
    ebs_volumes       = "$3.2"
    cloudfront        = "$5-10"
    route53           = "$0.5"
    total             = "~$150/month"
  }
}

# Deployment Status
output "deployment_status" {
  description = "Current deployment status"
  value = {
    vpc_and_networking = "Complete"
    eks_cluster        = "Complete"
    s3_and_cloudfront  = "Complete"
    iam_and_security   = "Complete"
    vpc_endpoints      = "Complete"
  }
}

# Next Steps
output "next_steps" {
  description = "Pending deployment tasks"
  value = [
    "Kubernetes application deployment",
    "ServiceAccount creation",
    "Load Balancer Controller installation",
    "Application Docker images",
    "CI/CD pipeline setup"
  ]
}
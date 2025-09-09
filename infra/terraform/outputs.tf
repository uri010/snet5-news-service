output "project_info" {
  description = "프로젝트 기본 정보"
  value = {
    project_name = var.project_name
    environment  = var.environment
    region       = var.region
    account_id   = data.aws_caller_identity.current.account_id
  }
}

output "vpc_info" {
  description = "VPC 정보"
  value = {
    vpc_id   = aws_vpc.main.id
    vpc_arn  = aws_vpc.main.arn
    vpc_cidr = aws_vpc.main.cidr_block
    vpc_name = "${var.project_name}-${var.environment}-vpc"
    igw_id   = aws_internet_gateway.main.id
    igw_arn  = aws_internet_gateway.main.arn
  }
}

output "subnet_info" {
  description = "서브넷 정보"
  value = {
    public_subnets = [
      for i, subnet in aws_subnet.public : {
        id                = subnet.id
        arn               = subnet.arn
        cidr_block        = subnet.cidr_block
        availability_zone = subnet.availability_zone
        name              = "${var.project_name}-${var.environment}-public-subnet-${i + 1}"
      }
    ]
    private_subnets = [
      for i, subnet in aws_subnet.private : {
        id                = subnet.id
        arn               = subnet.arn
        cidr_block        = subnet.cidr_block
        availability_zone = subnet.availability_zone
        name              = "${var.project_name}-${var.environment}-private-subnet-${i + 1}"
      }
    ]
  }
}

output "nat_instances_info" {
  description = "NAT 인스턴스 정보"
  value = [
    for i, instance in aws_instance.nat : {
      instance_id       = instance.id
      instance_arn      = instance.arn
      public_ip         = instance.public_ip
      private_ip        = instance.private_ip
      availability_zone = instance.availability_zone
      subnet_id         = instance.subnet_id
      security_group_id = aws_security_group.nat_instance.id
      name              = "${var.project_name}-${var.environment}-nat-instance-${i + 1}"
    }
  ]
}

output "route_tables_info" {
  description = "라우팅 테이블 정보"
  value = {
    public_route_table = {
      id   = aws_route_table.public.id
      arn  = aws_route_table.public.arn
      name = "${var.project_name}-${var.environment}-public-rt"
    }
    private_route_tables = [
      for i, rt in aws_route_table.private : {
        id   = rt.id
        arn  = rt.arn
        name = "${var.project_name}-${var.environment}-private-rt-${i + 1}"
        az   = var.availability_zones[i]
      }
    ]
  }
}

output "vpc_endpoint_info" {
  description = "VPC 엔드포인트 정보"
  value = {
    dynamodb_endpoint = {
      id           = aws_vpc_endpoint.dynamodb.id
      arn          = aws_vpc_endpoint.dynamodb.arn
      service_name = aws_vpc_endpoint.dynamodb.service_name
      vpc_id       = aws_vpc_endpoint.dynamodb.vpc_id
    }
  }
}

output "eks_cluster_info" {
  description = "EKS 클러스터 정보"
  value = {
    cluster_name              = aws_eks_cluster.main.name
    cluster_arn               = aws_eks_cluster.main.arn
    cluster_endpoint          = aws_eks_cluster.main.endpoint
    cluster_version           = aws_eks_cluster.main.version
    cluster_security_group_id = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
    oidc_issuer_url           = aws_eks_cluster.main.identity[0].oidc[0].issuer
  }
}

output "eks_node_group_info" {
  description = "EKS 노드 그룹 정보"
  value = {
    node_group_id        = aws_eks_node_group.main.id
    node_group_arn       = aws_eks_node_group.main.arn
    node_group_name      = aws_eks_node_group.main.node_group_name
    node_role_arn        = aws_iam_role.eks_node_group.arn
    instance_types       = aws_eks_node_group.main.instance_types
    capacity_type        = aws_eks_node_group.main.capacity_type
    scaling_config       = aws_eks_node_group.main.scaling_config
    launch_template_id   = aws_launch_template.eks_nodes.id
    launch_template_name = aws_launch_template.eks_nodes.name
  }
}

output "eks_security_groups_info" {
  description = "EKS 보안 그룹 정보"
  value = {
    cluster_security_group = {
      id   = aws_security_group.eks_cluster.id
      arn  = aws_security_group.eks_cluster.arn
      name = aws_security_group.eks_cluster.name
    }
    nodes_security_group = {
      id   = aws_security_group.eks_nodes.id
      arn  = aws_security_group.eks_nodes.arn
      name = aws_security_group.eks_nodes.name
    }
  }
}

output "eks_addons_info" {
  description = "EKS 애드온 정보"
  value = {
    coredns = {
      addon_name    = aws_eks_addon.coredns.addon_name
      addon_version = aws_eks_addon.coredns.addon_version
      arn           = aws_eks_addon.coredns.arn
    }
    kube_proxy = {
      addon_name    = aws_eks_addon.kube_proxy.addon_name
      addon_version = aws_eks_addon.kube_proxy.addon_version
      arn           = aws_eks_addon.kube_proxy.arn
    }
    vpc_cni = {
      addon_name    = aws_eks_addon.vpc_cni.addon_name
      addon_version = aws_eks_addon.vpc_cni.addon_version
      arn           = aws_eks_addon.vpc_cni.arn
    }
    ebs_csi_driver = {
      addon_name    = aws_eks_addon.ebs_csi_driver.addon_name
      addon_version = aws_eks_addon.ebs_csi_driver.addon_version
      arn           = aws_eks_addon.ebs_csi_driver.arn
    }
  }
}

output "external_dns_info" {
  description = "External DNS 설정 정보"
  value = {
    chart_version       = helm_release.external_dns.version
    namespace           = helm_release.external_dns.namespace
    service_account_arn = aws_iam_role.external_dns.arn
    domain_filter       = var.domain_name
    txt_owner_id        = aws_eks_cluster.main.name
    status              = helm_release.external_dns.status
  }
}

output "aws_load_balancer_controller_info" {
  description = "AWS Load Balancer Controller 정보"
  value = {
    chart_version       = helm_release.aws_load_balancer_controller.version
    namespace           = helm_release.aws_load_balancer_controller.namespace
    service_account_arn = aws_iam_role.aws_load_balancer_controller.arn
    cluster_name        = aws_eks_cluster.main.name
    replica_count       = 2
    status              = helm_release.aws_load_balancer_controller.status
  }
}
/*
output "kube_prometheus_stack_info" {
  description = "kube-prometheus-stack (Prometheus + Grafana) 정보"
  value = {
    chart_version      = helm_release.kube_prometheus_stack.version
    namespace          = helm_release.kube_prometheus_stack.namespace
    grafana_url        = "http://grafana.${var.domain_name}"
    grafana_admin_user = "admin"
    prometheus_url     = "http://prometheus.${var.domain_name}"
    status             = helm_release.kube_prometheus_stack.status
  }
}*/

output "ingress_info" {
  description = "Ingress 및 ALB 정보"
  value = {
    api_domain           = "api.${var.domain_name}"
    alb_certificate_arn  = aws_acm_certificate.alb.arn
    external_dns_enabled = true
    ssl_redirect_enabled = true
    health_check_path    = "/health"
  }
}
/*
output "kubernetes_storage_class_prometheus_info" {
  description = "Prometheus용 Kubernetes StorageClass 정보"
  value = {
    sc_name                = kubernetes_storage_class.prometheus.metadata[0].name
    sc_provisioner         = kubernetes_storage_class.prometheus.storage_provisioner
    sc_parameters          = kubernetes_storage_class.prometheus.parameters
    sc_reclaim_policy      = kubernetes_storage_class.prometheus.reclaim_policy
    sc_volume_binding_mode = kubernetes_storage_class.prometheus.volume_binding_mode
  }
}*/

output "s3_buckets_info" {
  description = "S3 버킷 정보"
  value = {
    static_website_bucket = {
      id                   = aws_s3_bucket.static_website.id
      arn                  = aws_s3_bucket.static_website.arn
      bucket_name          = aws_s3_bucket.static_website.bucket
      bucket_domain_name   = aws_s3_bucket.static_website.bucket_domain_name
      regional_domain_name = aws_s3_bucket.static_website.bucket_regional_domain_name
      website_endpoint     = aws_s3_bucket_website_configuration.static_website.website_endpoint
      website_domain       = aws_s3_bucket_website_configuration.static_website.website_domain
    }
    images_bucket = {
      id                   = aws_s3_bucket.images.id
      arn                  = aws_s3_bucket.images.arn
      bucket_name          = aws_s3_bucket.images.bucket
      bucket_domain_name   = aws_s3_bucket.images.bucket_domain_name
      regional_domain_name = aws_s3_bucket.images.bucket_regional_domain_name
    }
  }
}

output "cloudfront_info" {
  description = "CloudFront 배포 정보"
  value = {
    distribution_id  = aws_cloudfront_distribution.main.id
    distribution_arn = aws_cloudfront_distribution.main.arn
    domain_name      = aws_cloudfront_distribution.main.domain_name
    hosted_zone_id   = aws_cloudfront_distribution.main.hosted_zone_id
    custom_domain    = var.domain_name
    status           = aws_cloudfront_distribution.main.status
    etag             = aws_cloudfront_distribution.main.etag
  }
}

output "cloudfront_oac_info" {
  description = "CloudFront Origin Access Control 정보"
  value = {
    website_oac = {
      id   = aws_cloudfront_origin_access_control.main.id
      name = aws_cloudfront_origin_access_control.main.name
    }
    images_oac = {
      id   = aws_cloudfront_origin_access_control.images.id
      name = aws_cloudfront_origin_access_control.images.name
    }
  }
}

output "certificate_info" {
  description = "SSL 인증서 정보"
  value = {
    cloudfront_certificate = {
      certificate_arn         = aws_acm_certificate.main.arn
      domain_name             = aws_acm_certificate.main.domain_name
      validation_method       = aws_acm_certificate.main.validation_method
      status                  = aws_acm_certificate.main.status
      validation_record_fqdns = aws_acm_certificate_validation.main.validation_record_fqdns
      region                  = "us-east-1"
    }
    alb_certificate = {
      certificate_arn         = aws_acm_certificate.alb.arn
      domain_name             = aws_acm_certificate.alb.domain_name
      validation_method       = aws_acm_certificate.alb.validation_method
      status                  = aws_acm_certificate.alb.status
      validation_record_fqdns = aws_acm_certificate_validation.alb.validation_record_fqdns
      region                  = "ap-northeast-2"
    }
  }
}

output "route53_info" {
  description = "Route53 정보"
  value = {
    hosted_zone_id  = aws_route53_zone.main.zone_id
    hosted_zone_arn = aws_route53_zone.main.arn
    name_servers    = aws_route53_zone.main.name_servers
    domain_name     = var.domain_name
    a_record_name   = aws_route53_record.main.name
    a_record_fqdn   = aws_route53_record.main.fqdn
  }
}

output "waf_info" {
  description = "WAF Web ACL 정보"
  value = {
    web_acl_id   = aws_wafv2_web_acl.main.id
    web_acl_arn  = aws_wafv2_web_acl.main.arn
    web_acl_name = aws_wafv2_web_acl.main.name
    capacity     = aws_wafv2_web_acl.main.capacity
  }
}

output "iam_roles_info" {
  description = "IAM 역할 정보"
  value = {
    eks_cluster_role = {
      name = aws_iam_role.eks_cluster.name
      arn  = aws_iam_role.eks_cluster.arn
      id   = aws_iam_role.eks_cluster.id
    }
    eks_node_group_role = {
      name = aws_iam_role.eks_node_group.name
      arn  = aws_iam_role.eks_node_group.arn
      id   = aws_iam_role.eks_node_group.id
    }
    aws_load_balancer_controller_role = {
      name = aws_iam_role.aws_load_balancer_controller.name
      arn  = aws_iam_role.aws_load_balancer_controller.arn
      id   = aws_iam_role.aws_load_balancer_controller.id
    }
    external_dns_role = {
      name = aws_iam_role.external_dns.name
      arn  = aws_iam_role.external_dns.arn
      id   = aws_iam_role.external_dns.id
    }
    ebs_csi_driver_role = {
      name = aws_iam_role.ebs_csi_driver.name
      arn  = aws_iam_role.ebs_csi_driver.arn
      id   = aws_iam_role.ebs_csi_driver.id
    }
    news_data_collector_role = {
      name = aws_iam_role.news_data_collector.name
      arn  = aws_iam_role.news_data_collector.arn
      id   = aws_iam_role.news_data_collector.id
    }
    news_api_service_role = {
      name = aws_iam_role.news_api_service.name
      arn  = aws_iam_role.news_api_service.arn
      id   = aws_iam_role.news_api_service.id
    }
  }
}

output "oidc_provider_info" {
  description = "OIDC 공급자 정보"
  value = {
    arn        = aws_iam_openid_connect_provider.eks.arn
    url        = aws_iam_openid_connect_provider.eks.url
    client_ids = aws_iam_openid_connect_provider.eks.client_id_list
  }
}

output "dynamodb_info" {
  description = "DynamoDB 테이블 정보"
  value = {
    table_name = data.aws_dynamodb_table.naver_news_articles.name
    table_arn  = data.aws_dynamodb_table.naver_news_articles.arn
    table_id   = data.aws_dynamodb_table.naver_news_articles.id
  }
}

output "connection_info" {
  description = "서비스 연결 정보"
  value = {
    website_url            = "https://${var.domain_name}"
    api_url                = "https://api.${var.domain_name}"
    api_docs_url           = "https://api.${var.domain_name}/docs"
    api_redoc_url          = "https://api.${var.domain_name}/redoc"
    cloudfront_url         = "https://${aws_cloudfront_distribution.main.domain_name}"
    eks_cluster_endpoint   = aws_eks_cluster.main.endpoint
    kubectl_config_command = "aws eks update-kubeconfig --region ${var.region} --name ${aws_eks_cluster.main.name}"
    ingress_ready          = "ALB Controller installed - ready for Ingress resources"
  }
}

output "cost_estimation" {
  description = "월 예상 비용"
  value = {
    eks_control_plane = "$72 (클러스터당 고정비용)"
    ec2_nodes         = "$60 (t3.small 2대 기준)"
    nat_instances     = "$17 (t3.micro 2대)"
    ebs_volumes       = "$3.2 (20GB gp3 디스크)"
    cloudfront        = "$5-10 (트래픽 기준)"
    route53           = "$0.5 (호스팅 존)"
    s3_storage        = "변동 (데이터량 기준)"
    data_transfer     = "변동 (트래픽 기준)"
    total_estimated   = "약 $150-160/월"
    currency          = "USD"
  }
}
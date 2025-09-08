# EKS Cluster IAM Role
resource "aws_iam_role" "eks_cluster" {
  name = "${var.project_name}-${var.environment}-eks-cluster-role"

  # EKS 서비스만 이 역할을 사용할 수 있도록 신뢰 관계 설정
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-eks-cluster-role"
    Type = "IAMRole"
  }
}

# EKS 클러스터가 필요한 기본 AWS 권한들
# - VPC 리소스 관리 (ENI, 서브넷, 보안 그룹)
# - CloudWatch 로그 스트림 생성
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

# EKS Node Group IAM Role  
# 역할: 워커 노드(EC2 인스턴스)들이 EKS와 통신하고 컨테이너 실행
resource "aws_iam_role" "eks_node_group" {
  name = "${var.project_name}-${var.environment}-eks-node-group-role"

  # EC2 인스턴스만 이 역할을 사용할 수 있도록 신뢰 관계 설정
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-eks-node-group-role"
    Type = "IAMRole"
  }
}

# 워커 노드가 EKS 클러스터에 조인하기 위한 권한
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_group.name
}

# 기존 노드 그룹 IAM 역할에 추가
resource "aws_iam_role_policy_attachment" "eks_node_ebs_csi_policy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.eks_node_group.name
}

# Pod 간 네트워킹을 위한 VPC CNI 권한
# - Pod에 VPC IP 주소 할당
# - ENI 관리 권한
resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_group.name
}

# ECR에서 컨테이너 이미지 다운로드 권한
# Docker Hub 사용해도 나중에 ECR 사용할 수 있도록 유지
resource "aws_iam_role_policy_attachment" "eks_container_registry_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_group.name
}

# EKS OIDC 인증서 정보 가져오기
data "tls_certificate" "eks" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

# OIDC Identity Provider 생성
resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = {
    Name = "${var.project_name}-${var.environment}-eks-oidc"
    Type = "OIDCProvider"
  }
}

# AWS Load Balancer Controller IAM Role
# Kubernetes Ingress를 AWS ALB로 자동 변환 (ALB만 사용)
resource "aws_iam_role" "aws_load_balancer_controller" {
  name = "${var.project_name}-${var.environment}-aws-load-balancer-controller"

  # OIDC를 통한 역할 신뢰 관계 (특정 ServiceAccount만 사용 가능)
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" : "system:serviceaccount:kube-system:aws-load-balancer-controller"
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-alb-controller-role"
    Type = "IAMRole"
  }
}

resource "aws_iam_role_policy_attachment" "aws_load_balancer_controller_elb" {
  policy_arn = "arn:aws:iam::aws:policy/ElasticLoadBalancingFullAccess"
  role       = aws_iam_role.aws_load_balancer_controller.name
}

resource "aws_iam_role_policy_attachment" "aws_load_balancer_controller_ec2" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
  role       = aws_iam_role.aws_load_balancer_controller.name
}

# External DNS IAM Role 
resource "aws_iam_role" "external_dns" {
  name = "${var.project_name}-${var.environment}-external-dns"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" : "system:serviceaccount:kube-system:external-dns"
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

# External DNS Route53 권한
resource "aws_iam_policy" "external_dns" {
  name = "${var.project_name}-${var.environment}-external-dns"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "external_dns" {
  policy_arn = aws_iam_policy.external_dns.arn
  role       = aws_iam_role.external_dns.name
}

# EBS CSI Driver용 IAM Role
resource "aws_iam_role" "ebs_csi_driver" {
  name = "${var.project_name}-${var.environment}-ebs-csi-driver"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" : "system:serviceaccount:kube-system:ebs-csi-controller-sa"
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ebs_csi_driver_attach" {
  role       = aws_iam_role.ebs_csi_driver.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# 데이터 수집용 IAM Role
resource "aws_iam_role" "news_data_collector" {
  name = "${var.project_name}-${var.environment}-news-data-collector"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" : "system:serviceaccount:default:news-data-collector-sa"
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-news-data-collector-role"
    Type = "IAMRole"
  }
}

# 데이터 조회용 IAM Role
resource "aws_iam_role" "news_api_service" {
  name = "${var.project_name}-${var.environment}-news-api-service"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" : "system:serviceaccount:default:news-api-service-sa"
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-news-api-service-role"
    Type = "IAMRole"
  }
}

# 데이터 수집용 DynamoDB 정책 (읽기/쓰기)
resource "aws_iam_policy" "news_data_collector_dynamodb" {
  name        = "${var.project_name}-${var.environment}-data-collector-dynamodb"
  description = "DynamoDB access for news data collector"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:DescribeTable",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          data.aws_dynamodb_table.naver_news_articles.arn,
          "${data.aws_dynamodb_table.naver_news_articles.arn}/index/*"
        ]
      }
    ]
  })
}

# 데이터 조회용 DynamoDB 정책 (읽기만)
resource "aws_iam_policy" "news_api_service_dynamodb" {
  name        = "${var.project_name}-${var.environment}-api-service-dynamodb"
  description = "DynamoDB read access for news API service"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:DescribeTable",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ]
        Resource = [
          data.aws_dynamodb_table.naver_news_articles.arn,
          "${data.aws_dynamodb_table.naver_news_articles.arn}/index/*"
        ]
      }
    ]
  })
}

# 데이터 수집용 S3 정책
resource "aws_iam_policy" "news_data_collector_s3" {
  name        = "${var.project_name}-${var.environment}-data-collector-s3"
  description = "S3 access for news image storage"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "arn:aws:s3:::${var.s3_bucket_name}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.s3_bucket_name}"
        ]
      }
    ]
  })
}

# 정책 연결 - 데이터 수집 서비스
resource "aws_iam_role_policy_attachment" "news_data_collector_dynamodb" {
  policy_arn = aws_iam_policy.news_data_collector_dynamodb.arn
  role       = aws_iam_role.news_data_collector.name
}

resource "aws_iam_role_policy_attachment" "news_data_collector_s3" {
  policy_arn = aws_iam_policy.news_data_collector_s3.arn
  role       = aws_iam_role.news_data_collector.name
}

# 정책 연결 - API 서비스
resource "aws_iam_role_policy_attachment" "news_api_service_dynamodb" {
  policy_arn = aws_iam_policy.news_api_service_dynamodb.arn
  role       = aws_iam_role.news_api_service.name
}
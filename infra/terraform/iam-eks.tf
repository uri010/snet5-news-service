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

# AWS Load Balancer Controller 권한 정책 (ALB만)
resource "aws_iam_policy" "aws_load_balancer_controller" {
  name        = "${var.project_name}-${var.environment}-ALBControllerPolicy"
  description = "Minimal IAM policy for AWS Load Balancer Controller (ALB only)"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # VPC 및 EC2 기본 읽기 권한 (ALB 배치를 위해 필요)
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeTags"
        ]
        Resource = "*"
      },

      # ALB 관련 읽기 권한
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:DescribeTags"
        ]
        Resource = "*"
      },

      # ALB 생성 권한
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:CreateLoadBalancer",
          "elasticloadbalancing:CreateTargetGroup",
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:CreateRule"
        ]
        Resource = "*"
      },

      # ALB 수정/삭제 권한 (EKS가 생성한 것만)
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:DeleteRule"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "elasticloadbalancing:CreateAction" = [
              "CreateLoadBalancer",
              "CreateTargetGroup"
            ]
          }
        }
      },

      # 타겟 등록/해제 (Pod를 ALB에 연결)
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:RegisterTargets",
          "elasticloadbalancing:DeregisterTargets"
        ]
        Resource = "*"
      },

      # 보안 그룹 관리 (ALB용 보안 그룹 생성/수정)
      {
        Effect = "Allow"
        Action = [
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:CreateSecurityGroup",
          "ec2:DeleteSecurityGroup"
        ]
        Resource = "*"
      },

      # 태그 관리 (생성한 리소스 식별용)
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateTags",
          "ec2:DeleteTags",
          "elasticloadbalancing:AddTags",
          "elasticloadbalancing:RemoveTags"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-alb-controller-policy"
    Type = "IAMPolicy"
  }
}

# 정책 연결
resource "aws_iam_role_policy_attachment" "aws_load_balancer_controller" {
  policy_arn = aws_iam_policy.aws_load_balancer_controller.arn
  role       = aws_iam_role.aws_load_balancer_controller.name
}

# DynamoDB 접근 IAM Role
resource "aws_iam_role" "dynamodb_access" {
  name = "${var.project_name}-${var.environment}-dynamodb-access"

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
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" : "system:serviceaccount:default:news-app-sa"
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-dynamodb-role"
    Type = "IAMRole"
  }
}

# DynamoDB 권한 정책
resource "aws_iam_policy" "dynamodb_access" {
  name        = "${var.project_name}-${var.environment}-dynamodb-policy"
  description = "Policy for accessing existing DynamoDB table"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
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

  tags = {
    Name = "${var.project_name}-${var.environment}-dynamodb-policy"
    Type = "IAMPolicy"
  }
}

# 정책 연결
resource "aws_iam_role_policy_attachment" "dynamodb_access" {
  policy_arn = aws_iam_policy.dynamodb_access.arn
  role       = aws_iam_role.dynamodb_access.name
}
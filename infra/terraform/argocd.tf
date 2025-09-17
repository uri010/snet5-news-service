# ArgoCD 네임스페이스 생성
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
    labels = {
      name = "argocd"
    }
  }
}

# ArgoCD Helm Release
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  version    = "8.5.0"

  values = [
    yamlencode({
      global = {
        domain = "argocd.${var.domain_name}"
        nodeSelector = {
          "eks.amazonaws.com/nodegroup" = "news-service-dev-node-group"
        }
      }

      # ArgoCD Server 설정
      server = {
        service = {
          type = "ClusterIP" # Ingress를 통해 접근
        }
        extraArgs = [
          "--insecure"
        ]

        # Ingress 설정 (ALB 사용 시)
        ingress = {
          enabled          = true
          ingressClassName = "alb"
          annotations = {
            "kubernetes.io/ingress.class"                = "alb"
            "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
            "alb.ingress.kubernetes.io/target-type"      = "ip"
            "alb.ingress.kubernetes.io/listen-ports"     = "[{\"HTTP\": 80}, {\"HTTPS\": 443}]"
            "alb.ingress.kubernetes.io/ssl-redirect"     = "443"
            "alb.ingress.kubernetes.io/certificate-arn"  = aws_acm_certificate.alb.arn
            "alb.ingress.kubernetes.io/backend-protocol" = "HTTP"
          }
          hosts = [
            {
              host = "argocd.${var.domain_name}"
              paths = [
                {
                  path     = "/"
                  pathType = "Prefix"
                }
              ]
            }
          ]
        }

        # Admin 비밀번호 설정 비활성화 (초기 비밀번호 사용)
        config = {
          "admin.enabled" = "true"
        }

        # RBAC 설정
        rbacConfig = {
          "policy.default" = "role:readonly"
          "policy.csv"     = <<-EOT
            p, role:admin, applications, *, */*, allow
            p, role:admin, clusters, *, *, allow
            p, role:admin, repositories, *, *, allow
            g, argocd-admin, role:admin
          EOT
        }
      }

      # ArgoCD Application Controller 설정
      controller = {
        replicas = 1
        resources = {
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
          requests = {
            cpu    = "250m"
            memory = "256Mi"
          }
        }
      }

      # ArgoCD Repo Server 설정
      repoServer = {
        replicas = 1
        resources = {
          limits = {
            cpu    = "500m"
            memory = "512Mi"
          }
          requests = {
            cpu    = "250m"
            memory = "256Mi"
          }
        }
      }

      # ArgoCD Redis 설정
      redis = {
        resources = {
          limits = {
            cpu    = "200m"
            memory = "128Mi"
          }
          requests = {
            cpu    = "100m"
            memory = "64Mi"
          }
        }
      }

      # ArgoCD Image Updater 활성화
      imageUpdater = {
        enabled = true
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.argocd
  ]
}

# ArgoCD Image Updater 별도 설치 (더 많은 제어가 필요한 경우)
resource "helm_release" "argocd_image_updater" {
  name       = "argocd-image-updater"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-image-updater"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  version    = "0.12.3"

  values = [
    yamlencode({
      nodeSelector = {
        "eks.amazonaws.com/nodegroup" = "news-service-dev-node-group"
      }

      config = {
        registries = [
          {
            name        = "ecr"
            api_url     = "https://236528210774.dkr.ecr.ap-northeast-2.amazonaws.com"
            prefix      = "236528210774.dkr.ecr.ap-northeast-2.amazonaws.com"
            ping        = true
            insecure    = false
            credentials = "ext:/scripts/auth1.sh"
          }
        ]
      }
      authScripts = {
        enabled = true
        scripts = {
          "auth1.sh" = <<-EOT
            #!/bin/sh
            aws ecr get-login-password --region ap-northeast-2
          EOT
        }
      }

      # ServiceAccount for ECR access
      serviceAccount = {
        create = true
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.argocd_image_updater.arn
        }
      }

      resources = {
        limits = {
          cpu    = "100m"
          memory = "128Mi"
        }
        requests = {
          cpu    = "50m"
          memory = "64Mi"
        }
      }
    })
  ]

  depends_on = [
    helm_release.argocd,
    aws_iam_role.argocd_image_updater
  ]
}

# ArgoCD Image Updater용 IAM Role
resource "aws_iam_role" "argocd_image_updater" {
  name = "argocd-image-updater-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.eks.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:argocd:argocd-image-updater"
            "${replace(aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "argocd-image-updater-role"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# ArgoCD Image Updater ECR 권한
resource "aws_iam_role_policy" "argocd_image_updater_ecr" {
  name = "ECRReadOnlyPolicy"
  role = aws_iam_role.argocd_image_updater.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:DescribeImages"
        ]
        Resource = [
          aws_ecr_repository.news_api.arn,
          aws_ecr_repository.news_collector.arn
        ]
      }
    ]
  })
}
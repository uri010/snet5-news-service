# News API ECR Repository
resource "aws_ecr_repository" "news_api" {
  name                 = "${var.project_name}/${var.environment}/news-api"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-news-api-ecr"
    Environment = var.environment
    Project     = var.project_name
    Service     = "news-api"
  }
}

# News Data Collector ECR Repository
resource "aws_ecr_repository" "news_collector" {
  name                 = "${var.project_name}/${var.environment}/news-collector"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-news-collector-ecr"
    Environment = var.environment
    Project     = var.project_name
    Service     = "news-collector"
  }
}

# ECR Lifecycle Policy for News API
resource "aws_ecr_lifecycle_policy" "news_api" {
  repository = aws_ecr_repository.news_api.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Delete untagged images older than 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# ECR Lifecycle Policy for News Collector
resource "aws_ecr_lifecycle_policy" "news_collector" {
  repository = aws_ecr_repository.news_collector.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Delete untagged images older than 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# GitHub OIDC Identity Provider 
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com",
  ]

  thumbprint_list = [
    "2b18947a6a9fc7764fd8b5fb18a863b0c6dac24f", # 기존 (다른 팀용)
    "7560d6f40fa55195f740ee2b1b7c0b4836cbe103"
  ]

  tags = {
    Name    = "github-actions-oidc"
    Purpose = "GitHubActions"
  }
}


# IAM Role for GitHub Actions
resource "aws_iam_role" "github_actions_ecr_role" {
  name = "github-actions-ecr-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          # Repository 조건 다시 추가
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_username}/${var.repo_name}:*"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "github-actions-ecr-role"
    Environment = "ci-cd"
    ManagedBy   = "terraform"
  }
}

# ECR Access Policy
resource "aws_iam_role_policy" "ecr_access" {
  name = "ECRAccessPolicy"
  role = aws_iam_role.github_actions_ecr_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRGetAuthorizationToken"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECRRepositoryActions"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:DescribeImages",
          "ecr:BatchDeleteImage"
        ]
        Resource = [
          aws_ecr_repository.news_collector.arn,
          aws_ecr_repository.news_api.arn
        ]
      }
    ]
  })
}
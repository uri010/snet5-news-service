# CloudWatch Observability EKS Add-on 구성
# cloudwatch-addon.tf

# CloudWatch Observability를 위한 IAM 역할
resource "aws_iam_role" "cloudwatch_observability" {
  name = "${var.project_name}-${var.environment}-cloudwatch-observability"

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
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" : "system:serviceaccount:amazon-cloudwatch:cloudwatch-agent"
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-cloudwatch-observability-role"
    Type = "IAMRole"
  }
}

# CloudWatch Observability를 위한 IAM 역할 (로그 권한 제거)
resource "aws_iam_policy" "cloudwatch_observability" {
  name = "${var.project_name}-${var.environment}-cloudwatch-observability-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath",
          "ec2:DescribeVolumes",
          "ec2:DescribeTags",
          "ec2:DescribeInstances",
          "ec2:DescribeRegions",
          "eks:DescribeCluster",
          "eks:DescribeNodegroup",
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "logs:CreateLogGroup",
          "logs:DescribeLogGroups",
          "logs:CreateLogStream",   
          "logs:PutLogEvents",      
          "logs:DescribeLogGroups", 
          "logs:DescribeLogStreams" 
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-cloudwatch-observability-policy"
  }
}

resource "aws_iam_role_policy_attachment" "cloudwatch_observability" {
  policy_arn = aws_iam_policy.cloudwatch_observability.arn
  role       = aws_iam_role.cloudwatch_observability.name
}

# Amazon CloudWatch Observability EKS Add-on
resource "aws_eks_addon" "cloudwatch_observability" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "amazon-cloudwatch-observability"
  addon_version               = "v4.3.0-eksbuild.1"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
  service_account_role_arn    = aws_iam_role.cloudwatch_observability.arn

  depends_on = [
    aws_eks_cluster.main,
    aws_eks_node_group.main,
    aws_iam_role_policy_attachment.cloudwatch_observability
  ]

  tags = {
    Name        = "${var.project_name}-${var.environment}-cloudwatch-observability-addon"
    Environment = var.environment
    Project     = var.project_name
  }
}

# CloudWatch 메트릭 알람
resource "aws_cloudwatch_metric_alarm" "cluster_cpu_high" {
  alarm_name          = "${var.project_name}-${var.environment}-cluster-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "cluster_cpu_utilization"
  namespace           = "ContainerInsights"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "EKS cluster CPU utilization is high"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = aws_eks_cluster.main.name
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-cluster-cpu-alarm"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_metric_alarm" "cluster_memory_high" {
  alarm_name          = "${var.project_name}-${var.environment}-cluster-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "cluster_memory_utilization"
  namespace           = "ContainerInsights"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "EKS cluster memory utilization is high"
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = aws_eks_cluster.main.name
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-cluster-memory-alarm"
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_metric_alarm" "cluster_node_count" {
  alarm_name          = "${var.project_name}-${var.environment}-cluster-nodes-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "cluster_number_of_running_nodes"
  namespace           = "ContainerInsights"
  period              = "300"
  statistic           = "Average"
  threshold           = "2"
  alarm_description   = "EKS cluster running nodes count is low"
  treat_missing_data  = "breaching"

  dimensions = {
    ClusterName = aws_eks_cluster.main.name
  }

  tags = {
    Name        = "${var.project_name}-${var.environment}-cluster-nodes-alarm"
    Environment = var.environment
    Project     = var.project_name
  }
}

# CloudWatch Dashboard
resource "aws_cloudwatch_dashboard" "container_insights" {
  dashboard_name = "${var.project_name}-${var.environment}-container-insights"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["ContainerInsights", "cluster_cpu_utilization", "ClusterName", aws_eks_cluster.main.name],
            [".", "cluster_memory_utilization", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "클러스터 리소스 사용률"
          period  = 300
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 6
        height = 6

        properties = {
          metrics = [
            ["ContainerInsights", "cluster_number_of_running_nodes", "ClusterName", aws_eks_cluster.main.name],
            [".", "cluster_number_of_running_pods", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "클러스터 노드/Pod 개수"
          period  = 300
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 6
        y      = 6
        width  = 6
        height = 6

        properties = {
          metrics = [
            ["ContainerInsights", "node_cpu_utilization", "ClusterName", aws_eks_cluster.main.name],
            [".", "node_memory_utilization", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "노드 평균 리소스 사용률"
          period  = 300
          yAxis = {
            left = {
              min = 0
              max = 100
            }
          }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6

        properties = {
          metrics = [
            ["ContainerInsights", "pod_cpu_utilization", "ClusterName", aws_eks_cluster.main.name],
            [".", "pod_memory_utilization", ".", "."]
          ]
          view    = "timeSeries"
          stacked = false
          region  = var.region
          title   = "Pod 리소스 사용률"
          period  = 300
          yAxis = {
            left = {
              min = 0
            }
          }
        }
      }
    ]
  })
}
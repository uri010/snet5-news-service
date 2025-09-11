# Karpenter Controller IAM Role
resource "aws_iam_role" "karpenter_controller" {
  name = "${var.project_name}-${var.environment}-karpenter-controller"

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
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub" : "system:serviceaccount:karpenter:karpenter"
            "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud" : "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-karpenter-controller-role"
    Type = "IAMRole"
  }
}

# Karpenter Controller Policy
resource "aws_iam_policy" "karpenter_controller" {
  name = "${var.project_name}-${var.environment}-karpenter-controller-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateFleet",
          "ec2:CreateLaunchTemplate",
          "ec2:CreateTags",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSpotPriceHistory",
          "ec2:DescribeSubnets",
          "ec2:DeleteLaunchTemplate",
          "ec2:RunInstances",
          "ec2:TerminateInstances",
          "ssm:GetParameter",
          "iam:PassRole",
          "iam:CreateInstanceProfile",
          "iam:TagInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:DeleteInstanceProfile",
          "iam:GetInstanceProfile"
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "eks:DescribeCluster"
        Resource = aws_eks_cluster.main.arn
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-karpenter-controller-policy"
  }
}

resource "aws_iam_role_policy_attachment" "karpenter_controller" {
  policy_arn = aws_iam_policy.karpenter_controller.arn
  role       = aws_iam_role.karpenter_controller.name
}

# Karpenter Node IAM Role
resource "aws_iam_role" "karpenter_node" {
  name = "${var.project_name}-${var.environment}-karpenter-node"

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
    Name = "${var.project_name}-${var.environment}-karpenter-node-role"
    Type = "IAMRole"
  }
}

# Karpenter Node Policies
resource "aws_iam_role_policy_attachment" "karpenter_node_worker" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.karpenter_node.name
}

resource "aws_iam_role_policy_attachment" "karpenter_node_cni" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.karpenter_node.name
}

resource "aws_iam_role_policy_attachment" "karpenter_node_registry" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.karpenter_node.name
}

resource "aws_iam_role_policy_attachment" "karpenter_node_ssm" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.karpenter_node.name
}

resource "aws_iam_role_policy_attachment" "karpenter_node_cloudwatch" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  role       = aws_iam_role.karpenter_node.name
}

resource "aws_iam_instance_profile" "karpenter_node" {
  name = "${var.project_name}-${var.environment}-karpenter-node"
  role = aws_iam_role.karpenter_node.name

  tags = {
    Name = "${var.project_name}-${var.environment}-karpenter-node-profile"
  }
}

# Karpenter Helm Installation
resource "helm_release" "karpenter" {
  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  namespace  = "karpenter"
  version    = "1.5.0"

  create_namespace = true

  values = [
    yamlencode({
      settings = {
        clusterName     = aws_eks_cluster.main.name
        clusterEndpoint = aws_eks_cluster.main.endpoint
        isolatedVPC     = false
        aws = {
          clusterName            = aws_eks_cluster.main.name
          defaultInstanceProfile = aws_iam_instance_profile.karpenter_node.name
          clusterCIDR            = var.vpc_cidr
          interruptionQueue      = ""
        }
      }


      serviceAccount = {
        create = true
        name   = "karpenter"
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.karpenter_controller.arn
        }
      }

      resources = {
        requests = {
          cpu    = "1"
          memory = "1Gi"
        }
        limits = {
          cpu    = "1"
          memory = "1Gi"
        }
      }

      replicas = 2

      podDisruptionBudget = {
        maxUnavailable = 1
      }

      nodeSelector = {
        "kubernetes.io/os" = "linux"
      }

      # 기존 노드 그룹에서 Karpenter가 실행되도록 톨러레이션 설정
      tolerations = [
        {
          key      = "CriticalAddonsOnly"
          operator = "Exists"
        }
      ]

      priorityClassName = "system-cluster-critical"
      logLevel          = "info"
    })
  ]

  depends_on = [
    aws_eks_cluster.main,
    aws_eks_node_group.main, # 기존 노드 그룹에서 Karpenter 실행
    aws_iam_role_policy_attachment.karpenter_controller,
  ]
}

# UserData Template File
resource "local_file" "karpenter_userdata" {
  filename = "${path.module}/karpenter-userdata.tpl"
  content  = <<-EOF
#!/bin/bash
/etc/eks/bootstrap.sh ${aws_eks_cluster.main.name}
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sysctl -p /etc/sysctl.conf
echo "Karpenter node initialization completed" >> /var/log/karpenter-init.log
EOF
}
# EKS Cluster Security Group
resource "aws_security_group" "eks_cluster" {
  name_prefix = "${var.project_name}-${var.environment}-eks-cluster-"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-eks-cluster-sg"
  }
}

# EKS Node Group Security Group
resource "aws_security_group" "eks_nodes" {
  name_prefix = "${var.project_name}-${var.environment}-eks-nodes-"
  vpc_id      = aws_vpc.main.id

  # 노드 간 통신
  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  ingress {
    description = "Node to node communication"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "Kubelet API"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "NodePort Services"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  # ALB에서 Pod로의 접근 허용 (8000-8010 포트 범위)
  ingress {
    description = "ALB to Pod communication"
    from_port   = 8000
    to_port     = 8010
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr] # VPC 내부에서의 접근 허용
  }

  # Bastion에서 SSH 허용
  ingress {
    description     = "SSH from Bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  # DNS UDP 포트 추가
  ingress {
    description = "DNS UDP"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = [var.vpc_cidr]
  }

  # DNS TCP 포트 추가 (혹시 모를 경우를 대비)
  ingress {
    description = "DNS TCP"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name                     = "${var.project_name}-${var.environment}-eks-nodes-sg"
    "karpenter.sh/discovery" = aws_eks_cluster.main.name
  }
}

# EKS Cluster
resource "aws_eks_cluster" "main" {
  name     = "${var.project_name}-${var.environment}-cluster"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.31"

  vpc_config {
    subnet_ids              = aws_subnet.private[*].id
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = ["0.0.0.0/0"]
    security_group_ids      = [aws_security_group.eks_cluster.id]
  }

  enabled_cluster_log_types = ["api", "audit"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]

  tags = {
    Name = "${var.project_name}-${var.environment}-eks-cluster"
  }
}

# EKS Worker Node 최적화 AMI 조회
data "aws_ami" "eks_worker" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amazon-eks-node-${aws_eks_cluster.main.version}*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# EKS 노드용 SSH 키 생성
resource "tls_private_key" "eks_node_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "eks_node_key" {
  key_name   = "${var.project_name}-${var.environment}-eks-node-key"
  public_key = tls_private_key.eks_node_key.public_key_openssh

  tags = {
    Name = "${var.project_name}-${var.environment}-eks-node-keypair"
    Type = "EKS-Node-SSH-Key"
  }
}

# 개인 키를 로컬 파일로 저장
resource "local_file" "eks_node_private_key" {
  content         = tls_private_key.eks_node_key.private_key_pem
  filename        = "${path.module}/${var.project_name}-${var.environment}-eks-node-key.pem"
  file_permission = "0600"
}


# Launch Template
resource "aws_launch_template" "eks_nodes" {
  name_prefix = "${var.project_name}-${var.environment}-eks-nodes-"
  image_id    = data.aws_ami.eks_worker.id
  key_name    = aws_key_pair.eks_node_key.key_name # SSH 키 추가

  vpc_security_group_ids = [aws_security_group.eks_nodes.id]

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 20
      volume_type = "gp3"
      encrypted   = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name                          = "${var.project_name}-${var.environment}-eks-node"
      "topology.kubernetes.io/zone" = "$${EC2_AVAIL_ZONE}" # 가용 영역 정보 자동 할당
    }
  }

  user_data = base64encode(<<-EOF
#!/bin/bash
# 가용 영역 정보를 가져와서 kubelet에 레이블로 전달
AVAIL_ZONE=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)

# EKS 클러스터 부트스트랩 (레이블 추가)
/etc/eks/bootstrap.sh ${aws_eks_cluster.main.name} --kubelet-extra-args "--node-labels=topology.kubernetes.io/zone=$AVAIL_ZONE,topology.kubernetes.io/region=$REGION"

# 인스턴스 태그도 추가 (선택사항)
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
aws ec2 create-tags --region ${var.region} --resources $INSTANCE_ID --tags Key=topology.kubernetes.io/zone,Value=$AVAIL_ZONE Key=topology.kubernetes.io/region,Value=$REGION
EOF
  )

  tags = {
    Name = "${var.project_name}-${var.environment}-eks-node-template"
  }
}

# EKS Node Group
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project_name}-${var.environment}-node-group"
  node_role_arn   = aws_iam_role.eks_node_group.arn
  subnet_ids      = aws_subnet.private[*].id

  capacity_type  = "ON_DEMAND"
  instance_types = var.eks_node_instance_types

  scaling_config {
    desired_size = var.eks_node_desired_size
    max_size     = var.eks_node_max_size
    min_size     = var.eks_node_min_size
  }

  update_config {
    max_unavailable = 1
  }

  launch_template {
    id      = aws_launch_template.eks_nodes.id
    version = aws_launch_template.eks_nodes.latest_version
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry_policy,
  ]

  tags = {
    Name = "${var.project_name}-${var.environment}-node-group"
  }
}

# EKS Add-ons
resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "coredns"

  depends_on = [aws_eks_node_group.main]

  tags = {
    Name = "${var.project_name}-${var.environment}-coredns"
  }
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "kube-proxy"

  depends_on = [aws_eks_node_group.main]

  tags = {
    Name = "${var.project_name}-${var.environment}-kube-proxy"
  }
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "vpc-cni"

  depends_on = [aws_eks_node_group.main]

  tags = {
    Name = "${var.project_name}-${var.environment}-vpc-cni"
  }
}

resource "helm_release" "external_dns" {
  name       = "external-dns"
  repository = "https://kubernetes-sigs.github.io/external-dns/"
  chart      = "external-dns"
  namespace  = "kube-system"
  version    = "1.18.0"

  values = [
    yamlencode({
      provider = "aws"
      aws = {
        region = var.region
      }
      domainFilters = [var.domain_name]
      txtOwnerId    = aws_eks_cluster.main.name
      registry      = "txt"
      txtPrefix     = "external-dns-"

      serviceAccount = {
        create = true
        name   = "external-dns"
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.external_dns.arn
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
    aws_eks_cluster.main,
    aws_eks_node_group.main
  ]
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.10.0" # 최신 버전으로 업데이트 필요시

  values = [
    yamlencode({
      clusterName = aws_eks_cluster.main.name
      region      = var.region

      serviceAccount = {
        create = true
        name   = "aws-load-balancer-controller"
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.aws_load_balancer_controller.arn
        }
      }

      # 리소스 제한
      resources = {
        limits = {
          cpu    = "200m"
          memory = "500Mi"
        }
        requests = {
          cpu    = "100m"
          memory = "200Mi"
        }
      }

      # 로그 레벨
      logLevel = "info"

      # 고가용성을 위한 복제본
      replicaCount = 2

      # Pod 분산 배치
      podDisruptionBudget = {
        maxUnavailable = 1
      }
    })
  ]

  depends_on = [
    aws_eks_cluster.main,
    aws_eks_node_group.main,
    aws_iam_role_policy_attachment.aws_load_balancer_controller_elb,
    aws_iam_role_policy_attachment.aws_load_balancer_controller_ec2
  ]
}

resource "aws_eks_addon" "metrics_server" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "metrics-server"

  depends_on = [
    aws_eks_cluster.main,
    aws_eks_node_group.main
  ]

  tags = {
    Name        = "${var.project_name}-metrics-server"
    Environment = var.environment
  }
}


resource "kubernetes_namespace" "news_api" {
  metadata {
    name = "news-api"
  }
}

resource "kubernetes_namespace" "news_collector" {
  metadata {
    name = "news-collector"
  }
}

# Bastion Host용 Security Group
resource "aws_security_group" "bastion" {
  name_prefix = "${var.project_name}-${var.environment}-bastion-"
  vpc_id      = aws_vpc.main.id

  # SSH 접속 허용 (필요시 특정 IP로 제한)
  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # 모든 아웃바운드 트래픽 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-bastion-sg"
  }
}

# Bastion Host용 SSH 키 생성
resource "tls_private_key" "bastion_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "bastion_key" {
  key_name   = "${var.project_name}-${var.environment}-bastion-key"
  public_key = tls_private_key.bastion_key.public_key_openssh

  tags = {
    Name = "${var.project_name}-${var.environment}-bastion-keypair"
    Type = "Bastion-SSH-Key"
  }
}

# 개인 키를 로컬 파일로 저장
resource "local_file" "bastion_private_key" {
  content         = tls_private_key.bastion_key.private_key_pem
  filename        = "${path.module}/${var.project_name}-${var.environment}-bastion-key.pem"
  file_permission = "0600"
}

# Bastion Host EC2 Instance
resource "aws_instance" "bastion" {
  ami                         = "ami-0357b3d964cbfbed6"
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.bastion_key.key_name

  user_data = <<-EOF
#!/bin/bash
yum update -y
yum install -y htop tree
EOF

  tags = {
    Name = "${var.project_name}-${var.environment}-bastion"
    Type = "Bastion"
  }
}
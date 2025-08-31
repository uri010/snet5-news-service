# VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-${var.environment}-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-${var.environment}-igw"
  }
}

# Public Subnets (Multi-AZ)
resource "aws_subnet" "public" {
  count = length(var.availability_zones)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                     = "${var.project_name}-${var.environment}-public-subnet-${count.index + 1}"
    Type                     = "Public"
    "kubernetes.io/role/elb" = "1" # EKS ALB용
  }
}

# Private Subnets (Multi-AZ)
resource "aws_subnet" "private" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name                              = "${var.project_name}-${var.environment}-private-subnet-${count.index + 1}"
    Type                              = "Private"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# NAT Instance용 Security Group
resource "aws_security_group" "nat_instance" {
  name_prefix = "${var.project_name}-${var.environment}-nat-"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Private subnet에서 오는 모든 트래픽 허용
  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = var.private_subnet_cidrs
  }

  # 외부로 나가는 모든 트래픽 허용
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-nat-sg"
  }
}

resource "tls_private_key" "nat_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "nat_key" {
  key_name   = "${var.project_name}-${var.environment}-nat-key"
  public_key = tls_private_key.nat_key.public_key_openssh

  tags = {
    Name = "${var.project_name}-${var.environment}-nat-keypair"
    Type = "NAT-SSH-Key"
  }
}

# 개인 키를 로컬 파일로 저장
resource "local_file" "nat_private_key" {
  content  = tls_private_key.nat_key.private_key_pem
  filename = "${path.module}/${var.project_name}-${var.environment}-nat-key.pem"

  # 파일 권한 설정 (SSH 키 요구사항)
  file_permission = "0600"
}

# NAT Instance
resource "aws_instance" "nat" {
  count = length(var.availability_zones)

  ami                         = "ami-095919fccdf5fb49b"
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public[count.index].id
  vpc_security_group_ids      = [aws_security_group.nat_instance.id]
  associate_public_ip_address = true
  source_dest_check           = false # NAT 기능을 위해 필수

  key_name = aws_key_pair.nat_key.key_name

  depends_on = [aws_internet_gateway.main]


  user_data = <<-EOF
#!/bin/bash
yum update -y
echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
sysctl -p /etc/sysctl.conf
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
iptables -A FORWARD -i eth0 -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i eth0 -o eth0 -j ACCEPT
service iptables save
EOF

  tags = {
    Name = "${var.project_name}-${var.environment}-nat-instance-${count.index + 1}"
  }
}

# Route Table for Public Subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-public-rt"
  }
}

# Route Table Association for Public Subnets
resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Route Tables for Private Subnets (각 AZ별로 별도)
resource "aws_route_table" "private" {
  count  = length(var.availability_zones)
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-${var.environment}-private-rt-${count.index + 1}"
    AZ   = var.availability_zones[count.index]
  }
}

# 각 AZ의 NAT Instance Network Interface 정보 가져오기
data "aws_network_interface" "nat" {
  count = length(aws_instance.nat)
  id    = aws_instance.nat[count.index].primary_network_interface_id
}

# NAT Instance로 향하는 라우트 (Network Interface ID 사용)
resource "aws_route" "private_nat" {
  count = length(var.availability_zones)

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = data.aws_network_interface.nat[count.index].id

  depends_on = [aws_instance.nat]
}

# Route Table Association for Private Subnets
resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}
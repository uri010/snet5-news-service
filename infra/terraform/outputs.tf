# 네트워크 구성 요약
output "network_summary" {
  description = "Network configuration summary"
  value = {
    vpc_id             = aws_vpc.main.id
    vpc_cidr           = aws_vpc.main.cidr_block
    public_subnets     = length(aws_subnet.public)
    private_subnets    = length(aws_subnet.private)
    nat_gateways       = 1
    availability_zones = length(var.availability_zones)
  }
}
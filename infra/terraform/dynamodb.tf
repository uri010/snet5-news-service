# 기존 DynamoDB 테이블 정보 가져오기
data "aws_dynamodb_table" "naver_news_articles" {
  name = "naver_news_articles"
}

# DynamoDB VPC Endpoint (Gateway Type - 무료)
resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id          = aws_vpc.main.id
  service_name    = "com.amazonaws.${var.region}.dynamodb"
  route_table_ids = aws_route_table.private[*].id

  vpc_endpoint_type = "Gateway"

  tags = {
    Name = "${var.project_name}-${var.environment}-dynamodb-endpoint"
    Type = "VPCEndpoint"
  }
}
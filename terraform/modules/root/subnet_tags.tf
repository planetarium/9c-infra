resource "aws_ec2_tag" "vpc_tag" {
  count       = var.create_vpc ? 0 : 1
  resource_id = var.vpc_id
  key         = "kubernetes.io/cluster/${var.name}"
  value       = "shared"

  depends_on = [
    aws_vpc.default
  ]
}

resource "aws_ec2_tag" "public_subnet_tag" {
  count       = var.create_vpc ? 0 : length(var.public_subnet_ids)
  resource_id = element(var.public_subnet_ids, count.index)
  key         = "kubernetes.io/role/elb"
  value       = "1"
}

resource "aws_ec2_tag" "public_subnet_cluster_tag" {
  count       = var.create_vpc ? 0 : length(var.public_subnet_ids)
  resource_id = element(var.public_subnet_ids, count.index)
  key         = "kubernetes.io/cluster/${var.name}"
  value       = "shared"

  depends_on = [
    aws_subnet.public
  ]
}
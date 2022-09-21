resource "aws_ec2_tag" "vpc_tag" {
  resource_id = var.vpc_id
  key         = "kubernetes.io/cluster/${var.name}"
  value       = "shared"
}

resource "aws_ec2_tag" "public_subnet_tag" {
  for_each    = toset(var.public_subnets)
  resource_id = each.value
  key         = "kubernetes.io/role/elb"
  value       = "1"
}

resource "aws_ec2_tag" "public_subnet_cluster_tag" {
  for_each    = toset(var.public_subnets)
  resource_id = each.value
  key         = "kubernetes.io/cluster/${var.name}"
  value       = "shared"
}


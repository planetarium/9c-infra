resource "aws_ec2_tag" "vpc_tag" {
  resource_id = var.create_vpc ? aws_vpc.default[0].id :  var.vpc_id
  key         = "kubernetes.io/cluster/${var.name}"
  value       = "shared"

  depends_on = [
    aws_vpc.default
  ]
}

resource "aws_ec2_tag" "public_subnet_tag" {
  for_each    = var.create_vpc ? toset(aws_subnet.public[*].id) : toset(var.public_subnets)
  resource_id = each.value
  key         = "kubernetes.io/role/elb"
  value       = "1"

  depends_on = [
    aws_subnet.public
  ]
}

resource "aws_ec2_tag" "public_subnet_cluster_tag" {
  for_each    = var.create_vpc ? toset(aws_subnet.public[*].id) : toset(var.public_subnets)
  resource_id = each.value
  key         = "kubernetes.io/cluster/${var.name}"
  value       = "shared"

  depends_on = [
    aws_subnet.public
  ]
}


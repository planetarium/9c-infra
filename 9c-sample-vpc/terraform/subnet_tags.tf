resource "aws_ec2_tag" "vpc_tag" {
  count       = var.create_vpc ? 1 : 0
  resource_id =  var.vpc_id
  key         = "kubernetes.io/cluster/${var.name}"
  value       = "shared"

  depends_on = [
    aws_vpc.default
  ]
}

resource "aws_ec2_tag" "public_subnet_tag" {
  count       = length(var.public_subnets)
  resource_id = element(var.public_subnets, count.index)
  key         = "kubernetes.io/role/elb"
  value       = "1"

  depends_on = [
    aws_subnet.public
  ]
}

resource "aws_ec2_tag" "public_subnet_cluster_tag" {
  count       = length(var.public_subnets)
  resource_id = element(var.public_subnets, count.index)
  key         = "kubernetes.io/cluster/${var.name}"
  value       = "shared"

  depends_on = [
    aws_subnet.public
  ]
}


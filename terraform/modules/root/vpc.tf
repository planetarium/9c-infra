resource "aws_vpc" "default" {
  count                            = var.create_vpc ? 1 : 0
  cidr_block                       = var.vpc_cidr_block
  enable_dns_hostnames             = true
  assign_generated_ipv6_cidr_block = true

  tags = {
    Name                                = "vpc-${var.vpc_name}"
    "kubernetes.io/cluster/${var.name}" = "shared"
  }
}

resource "aws_internet_gateway" "default" {
  count  = var.create_vpc ? 1 : 0
  vpc_id = aws_vpc.default[0].id

  tags = {
    Name = "igw-${var.vpc_name}"
  }
}

resource "aws_eip" "nat" {
  count = var.create_vpc ? 1 : 0
  domain   = "vpc"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_nat_gateway" "nat" {
  count = var.create_vpc ? 1 : 0

  allocation_id = aws_eip.nat[0].id

  subnet_id = aws_subnet.public["us-east-2c"].id

  tags = {
    Name = "NAT-GW${count.index}-${var.vpc_name}"
  }

}

# PUBLIC SUBNETS
# The public subnet is where the bastion, NATs and ELBs reside. In most cases,
# there should not be any servers in the public subnet.

resource "aws_subnet" "public" {
  # count  = var.create_vpc ? length(var.availability_zones) : 0
  for_each = {
    for zone, cidr in var.public_subnets : zone => cidr
    if var.create_vpc
  }
  vpc_id = aws_vpc.default[0].id

  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = true

  tags = {
    Name                                = "public-${each.key}-${var.vpc_name}"
    Network                             = "Public"
    "kubernetes.io/role/elb"            = "1"
    "kubernetes.io/cluster/${var.name}" = "shared"
  }
}

# PUBLIC SUBNETS - Default route
resource "aws_route_table" "public" {
  count  = var.create_vpc ? 1 : 0
  vpc_id = aws_vpc.default[0].id

  tags = {
    Name = "publicrt-${var.vpc_name}"
  }
}

resource "aws_route_table_association" "public" {
  count = var.create_vpc ? length(var.public_subnets) : 0
  subnet_id = element([
    for subnet in aws_subnet.public : subnet.id
  ], count.index)
  route_table_id = aws_route_table.public[0].id
}


# PRIVATE SUBNETS
# Route Tables in a private subnet will not have Route resources created
# statically for them as the NAT instances are responsible for dynamically
# managing them on a per-AZ level using the Network=Private tag.

resource "aws_subnet" "private" {
  for_each = {
    for zone, cidr in var.private_subnets : zone => cidr
    if var.create_vpc
  }
  vpc_id = aws_vpc.default[0].id

  cidr_block        = each.value
  availability_zone = each.key

  tags = {
    Name               = "private-${each.key}-${var.vpc_name}"
    immutable_metadata = "{ \"purpose\": \"internal_${var.vpc_name}\", \"target\": null }"
    Network            = "Private"
    "kubernetes.io/role/internal-elb" = "1"
    "kubernetes.io/cluster/${var.name}" = "shared"
  }
}

resource "aws_route_table" "private" {
  count  = var.create_vpc ? length(var.private_subnets) : 0
  vpc_id = aws_vpc.default[0].id

  tags = {
    Name    = "private${count.index}rt-${var.vpc_name}"
    Network = "Private"
  }
}

resource "aws_route_table_association" "private" {
  count          = var.create_vpc ? length(var.private_subnets) : 0
  subnet_id      = element([for subnet in aws_subnet.private : subnet.id], count.index)
  route_table_id = element(aws_route_table.private.*.id, count.index)
}

resource "aws_route" "public_internet_gateway" {
  count                  = var.create_vpc ? 1 : 0
  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.default[0].id
}

resource "aws_route" "private_nat" {
  count                  = var.create_vpc ? length(var.private_subnets) : 0
  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat[0].id
}

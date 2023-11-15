resource "aws_eks_node_group" "node_groups" {
  for_each        = var.node_groups
  cluster_name    = aws_eks_cluster.cluster.name
  node_group_name = each.key
  node_role_arn   = aws_iam_role.node_group.arn
  subnet_ids      = var.create_vpc ? [aws_subnet.public[each.value["availability_zone"]].id] : var.public_subnet_ids
  instance_types  = each.value["instance_types"]
  capacity_type   = try(each.value["capacity_type"], "ON_DEMAND")
  ami_type        = try(each.value["ami_type"], "AL2_x86_64")

  scaling_config {
    desired_size = each.value["desired_size"]
    max_size     = each.value["max_size"]
    min_size     = each.value["min_size"]
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.eks-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.eks-AmazonEC2ContainerRegistryReadOnly,
    aws_subnet.public
  ]
}

# EKS can't directly set the "Name" tag, so we use the autoscaling_group_tag resource.
resource "aws_autoscaling_group_tag" "node_name_tag" {

  for_each = toset([for node in aws_eks_node_group.node_groups : node.resources[0].autoscaling_groups[0].name])

  autoscaling_group_name = each.value

  tag {
    key                 = "Name"
    value               = each.value
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_group_tag" "node_service_tag" {

  for_each = toset([for node in aws_eks_node_group.node_groups : node.resources[0].autoscaling_groups[0].name])

  autoscaling_group_name = each.value

  tag {
    key                 = "Service"
    value               = aws_eks_cluster.cluster.name
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_group_tag" "node_environment_tag" {

  for_each = toset([for node in aws_eks_node_group.node_groups : node.resources[0].autoscaling_groups[0].name])

  autoscaling_group_name = each.value

  tag {
    key                 = "Environment"
    value               = "development"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_group_tag" "node_owner_tag" {

  for_each = toset([for node in aws_eks_node_group.node_groups : node.resources[0].autoscaling_groups[0].name])

  autoscaling_group_name = each.value

  tag {
    key                 = "Owner"
    value               = "jihyung"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_group_tag" "node_team_tag" {

  for_each = toset([for node in aws_eks_node_group.node_groups : node.resources[0].autoscaling_groups[0].name])

  autoscaling_group_name = each.value

  tag {
    key                 = "Team"
    value               = "game"
    propagate_at_launch = true
  }
}

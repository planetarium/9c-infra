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

  dynamic "taint" {
    for_each = try(each.value["taints"], [])
    content {
      effect = taint.value["effect"]
      key    = taint.value["key"]
      value  = taint.value["value"]
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.eks-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.eks-AmazonEC2ContainerRegistryReadOnly,
    aws_subnet.public
  ]
}


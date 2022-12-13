locals {
  irsa_id  = aws_iam_openid_connect_provider.oidc.arn
  irsa_url = replace(aws_iam_openid_connect_provider.oidc.url, "https://", "")
}

data "tls_certificate" "cert" {
  url = aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "oidc" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cert.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}


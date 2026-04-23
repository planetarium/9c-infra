# IRSA for the on-prem pt6 RKE2 single-server cluster. The OIDC document is
# served from the existing public S3 bucket `9c-cluster-config` so AWS STS
# can verify service-account tokens issued by pt6.
#
# See /Users/yang/projects/9c-infra/9c-pt6/ for the cluster Helm values and
# /Users/yang/.claude/plans/flickering-mapping-steele.md for the full plan.

locals {
  pt6_oidc_issuer_url = "https://9c-cluster-config.s3.us-east-2.amazonaws.com/pt6-oidc"
}

# Thumbprint for S3's TLS certificate chain. S3 uses a well-known AWS
# certificate so this rarely rotates; update via `terraform refresh` if AWS
# issues a new root.
data "tls_certificate" "pt6_oidc" {
  url = "${local.pt6_oidc_issuer_url}/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "pt6" {
  url             = local.pt6_oidc_issuer_url
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.pt6_oidc.certificates[0].sha1_fingerprint]
}

resource "aws_iam_role" "pt6_external_secrets" {
  name = "rke2-pt6-external-secrets"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.pt6.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            # ESO runs in the `external-secrets` namespace with the
            # default `external-secrets` ServiceAccount name. If the helm
            # release name changes, update this.
            "${trimprefix(local.pt6_oidc_issuer_url, "https://")}:sub" = "system:serviceaccount:external-secrets:external-secrets"
            "${trimprefix(local.pt6_oidc_issuer_url, "https://")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

# Least-privilege: only the two Secrets Manager entries the pt6 snapshot
# CronJob needs. Expand the Resource list if additional ExternalSecret CRs
# are added to the pt6 deployment.
resource "aws_iam_policy" "pt6_external_secrets" {
  name = "rke2-pt6-external-secrets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
        ]
        Resource = [
          "arn:aws:secretsmanager:us-east-2:319679068466:secret:9c-main-v2/aws-keys*",
          "arn:aws:secretsmanager:us-east-2:319679068466:secret:9c-main-v2/slack*",
        ]
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "pt6_external_secrets" {
  role       = aws_iam_role.pt6_external_secrets.name
  policy_arn = aws_iam_policy.pt6_external_secrets.arn
}

output "pt6_external_secrets_role_arn" {
  value       = aws_iam_role.pt6_external_secrets.arn
  description = "Set this on pt6 helm install external-secrets --set serviceAccount.annotations.\"eks.amazonaws.com/role-arn\"=<this>"
}

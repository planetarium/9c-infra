resource "aws_iam_role" "external_dns" {
  name               = "eks-${var.name}-external-dns"
  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${local.irsa_id}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${local.irsa_url}:sub": "system:serviceaccount:kube-system:external-dns"
        }
      }
    }
  ]
}
POLICY
}

# IAM Policy
resource "aws_iam_policy" "route53" {
  name   = "eks-${var.name}-route53"
  policy = <<-EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "route53:ChangeResourceRecordSets"
      ],
      "Resource": [
        "arn:aws:route53:::hostedzone/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "route53:ListHostedZones",
        "route53:ListResourceRecordSets"
      ],
      "Resource": [
        "*"
      ]
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "external_dns_route53" {
  policy_arn = aws_iam_policy.route53.arn
  role       = aws_iam_role.external_dns.name
}


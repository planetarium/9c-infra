resource "aws_iam_role" "loki_assumerole" {
  name               = "eks-${var.name}-loki"
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
          "${local.irsa_url}:sub": "system:serviceaccount:monitoring:loki"
        }
      }
    }
  ]
}
POLICY
}

# IAM Policy
resource "aws_iam_policy" "loki" {
  name   = "eks-${var.name}-loki-policy"
  policy = <<-EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "s3:ListBucketMultipartUploads",
                "s3:DeleteObjectVersion",
                "s3:ListBucketVersions",
                "s3:PutReplicationConfiguration",
                "s3:ListBucket",
                "s3:PutBucketCORS",
                "s3:GetBucketAcl",
                "s3:GetBucketPolicy",
                "s3:ListMultipartUploadParts",
                "s3:PutObject",
                "s3:GetObjectAcl",
                "s3:GetObject",
                "s3:PutObjectRetention",
                "s3:GetBucketCORS",
                "s3:DeleteObject"
            ],
            "Resource": [
                "arn:aws:s3:::${var.loki_bucket}/*",
                "arn:aws:s3:::${var.loki_bucket}"
            ]
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "loki" {
  policy_arn = aws_iam_policy.loki.arn
  role       = aws_iam_role.loki_assumerole.name
}

resource "aws_iam_role" "fluent_bit_assumerole" {
  name               = "eks-${var.name}-fluent-bit"
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
          "${local.irsa_url}:sub": "system:serviceaccount:monitoring:fluent-bit"
        }
      }
    }
  ]
}
POLICY
}

# IAM Policy
resource "aws_iam_policy" "fluent_bit" {
  name   = "eks-${var.name}-fluent-bit-policy"
  policy = <<-EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogStream",
                "logs:CreateLogGroup",
                "logs:PutLogEvents",
                "logs:PutRetentionPolicy"
            ],
            "Resource": "*"
        },
        {
         "Effect":"Allow",
         "Action":[
            "s3:ListBucket"
         ],
         "Resource":"arn:aws:s3:::fluent-bit.planetariumhq.com"
        },
        {
          "Effect":"Allow",
          "Action":[
              "s3:PutObject"
          ],
          "Resource":"arn:aws:s3:::fluent-bit.planetariumhq.com/*"
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "fluent_bit" {
  policy_arn = aws_iam_policy.fluent_bit.arn
  role       = aws_iam_role.fluent_bit_assumerole.name
}

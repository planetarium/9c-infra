resource "aws_iam_role" "gateway_api_controller_assumerole" {
  name               = "eks-${var.name}-gateway-api-controller"
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
          "${local.irsa_url}:sub": "system:serviceaccount:aws-application-networking-system:gateway-api-controller"
        }
      }
    }
  ]
}
POLICY
}

# IAM Policy
resource "aws_iam_policy" "gateway_api_controller" {
  name   = "eks-${var.name}-gateway-api-controller-policy"
  policy = <<-EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "vpc-lattice:*",
                "ec2:DescribeVpcs",
                "ec2:DescribeSubnets",
                "ec2:DescribeTags",
                "ec2:DescribeSecurityGroups",
                "logs:CreateLogDelivery",
                "logs:GetLogDelivery",
                "logs:DescribeLogGroups",
                "logs:PutResourcePolicy",
                "logs:DescribeResourcePolicies",
                "logs:UpdateLogDelivery",
                "logs:DeleteLogDelivery",
                "logs:ListLogDeliveries",
                "tag:GetResources",
                "firehose:TagDeliveryStream",
                "s3:GetBucketPolicy",
                "s3:PutBucketPolicy"
            ],
            "Resource": "*"
        },
        {
            "Effect" : "Allow",
            "Action" : "iam:CreateServiceLinkedRole",
            "Resource" : "arn:aws:iam::*:role/aws-service-role/vpc-lattice.amazonaws.com/AWSServiceRoleForVpcLattice",
            "Condition" : {
                "StringLike" : {
                    "iam:AWSServiceName" : "vpc-lattice.amazonaws.com"
                }
            }
        },
        {
            "Effect" : "Allow",
            "Action" : "iam:CreateServiceLinkedRole",
            "Resource" : "arn:aws:iam::*:role/aws-service-role/delivery.logs.amazonaws.com/AWSServiceRoleForLogDelivery",
            "Condition" : {
                "StringLike" : {
                    "iam:AWSServiceName" : "delivery.logs.amazonaws.com"
                }
            }
        }
    ]
}

EOF
}

resource "aws_iam_role_policy_attachment" "gateway_api_controller" {
  policy_arn = aws_iam_policy.gateway_api_controller.arn
  role       = aws_iam_role.gateway_api_controller_assumerole.name
}


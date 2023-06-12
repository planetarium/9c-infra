resource "aws_iam_role" "athena_grafana_assumerole" {
  name               = "eks-${var.name}-athena-grafana"
  assume_role_policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AssumeFromEKSNode",
            "Effect": "Allow",
            "Principal": {
                "AWS": "*",
            },
            "Action": "sts:AssumeRole"
            "Condition" : {
                "ForAnyValue:StringLike": {
                    "aws:PrincipalArn": [
                        "arn:aws:sts::319679068466:assumed-role/eks-9c-main-v2-node-role/*"
                    ]
                } 
            }
        }
    ]
} 
POLICY
}

# IAM Policy
resource "aws_iam_policy" "athena_grafana" {
  name   = "eks-${var.name}-athena-grafana-policy"
  policy = <<-EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AthenaQueryAccess",
      "Effect": "Allow",
      "Action": [
        "athena:ListDatabases",
        "athena:ListDataCatalogs",
        "athena:ListWorkGroups",
        "athena:GetDatabase",
        "athena:GetDataCatalog",
        "athena:GetQueryExecution",
        "athena:GetQueryResults",
        "athena:GetTableMetadata",
        "athena:GetWorkGroup",
        "athena:ListTableMetadata",
        "athena:StartQueryExecution",
        "athena:StopQueryExecution"
      ],
      "Resource": ["*"]
    },
    {
      "Sid": "GlueReadAccess",
      "Effect": "Allow",
      "Action": [
        "glue:GetDatabase",
        "glue:GetDatabases",
        "glue:GetTable",
        "glue:GetTables",
        "glue:GetPartition",
        "glue:GetPartitions",
        "glue:BatchGetPartition"
      ],
      "Resource": ["*"]
    },
    {
      "Sid": "AthenaS3Access",
      "Effect": "Allow",
      "Action": [
        "s3:GetBucketLocation",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:ListBucketMultipartUploads",
        "s3:ListMultipartUploadParts",
        "s3:AbortMultipartUpload",
        "s3:PutObject"
      ],
      "Resource": ["arn:aws:s3:::9c-athena-result"]
    },
    {
      "Sid": "AthenaExamplesS3Access",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:ListBucket"],
      "Resource": ["arn:aws:s3:::9c-athena-result"]
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "athena_grafana" {
  policy_arn = aws_iam_policy.athena_grafana.arn
  role       = aws_iam_role.athena_grafana_assumerole.name
}

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
                "AWS": "*"
            },
            "Action": "sts:AssumeRole",
            "Condition" : {
                "StringLike": {
                    "aws:PrincipalArn": "arn:aws:sts::319679068466:*"
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
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "athena:GetTableMetadata",
                "athena:StartQueryExecution",
                "athena:ListDataCatalogs",
                "glue:GetTables",
                "glue:GetPartitions",
                "athena:GetQueryResults",
                "glue:BatchGetPartition",
                "athena:GetDatabase",
                "athena:GetDataCatalog",
                "athena:ListWorkGroups",
                "glue:GetDatabases",
                "glue:GetTable",
                "glue:GetDatabase",
                "athena:GetWorkGroup",
                "glue:GetPartition",
                "athena:ListDatabases",
                "athena:StopQueryExecution",
                "athena:GetQueryExecution",
                "athena:ListTableMetadata"
            ],
            "Resource": "*"
        },
        {
            "Sid": "VisualEditor1",
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject",
                "s3:ListBucketMultipartUploads",
                "s3:AbortMultipartUpload",
                "s3:ListBucket",
                "s3:GetBucketLocation",
                "s3:ListMultipartUploadParts"
            ],
            "Resource": [
                "arn:aws:s3:::arn:aws:s3:::9c-athena-result/arn:aws:s3:::9c-athena-result/*",
                "arn:aws:s3:::9c-athena-result"
            ]
        },
        {
            "Sid": "VisualEditor2",
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::arn:aws:s3:::9c-athena-result/*",
                "arn:aws:s3:::9c-athena-result"
            ]
        }
    ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "athena_grafana" {
  policy_arn = aws_iam_policy.athena_grafana.arn
  role       = aws_iam_role.athena_grafana_assumerole.name
}

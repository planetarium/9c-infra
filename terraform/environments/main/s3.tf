resource "aws_s3_bucket" "snapshots_archive" {
  bucket = "9c-snapshots-archive"
}

resource "aws_s3_bucket_public_access_block" "snapshots_archive" {
  bucket = aws_s3_bucket.snapshots_archive.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "snapshots_archive" {
  bucket = aws_s3_bucket.snapshots_archive.id

  rule {
    id     = "expire-after-91d"
    status = "Enabled"

    filter {
      prefix = "main/"
    }

    expiration {
      days = 91
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

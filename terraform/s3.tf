resource "random_id" "bucket" {
  byte_length = 4
}

resource "aws_s3_bucket" "backups" {
  bucket        = "${var.project}-mongo-backups-${random_id.bucket.hex}"
  force_destroy = true
}

# EXERCISE REQUIREMENT: public read AND public listing.
# All four blocks must be false or the bucket policy below is ignored.
resource "aws_s3_bucket_public_access_block" "backups" {
  bucket                  = aws_s3_bucket.backups.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# S3 disables ACLs by default now, re-enable them so the public-read ACL applies
resource "aws_s3_bucket_ownership_controls" "backups" {
  bucket = aws_s3_bucket.backups.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "backups" {
  bucket = aws_s3_bucket.backups.id
  acl    = "public-read"

  depends_on = [
    aws_s3_bucket_ownership_controls.backups,
    aws_s3_bucket_public_access_block.backups,
  ]
}

# s3:GetObject is public read of the dumps, s3:ListBucket is public listing,
# which is what turns "you need the exact key" into "here is the index"
resource "aws_s3_bucket_policy" "backups" {
  bucket = aws_s3_bucket.backups.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicRead"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.backups.arn}/*"
      },
      {
        Sid       = "PublicList"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:ListBucket"
        Resource  = aws_s3_bucket.backups.arn
      },
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.backups]
}

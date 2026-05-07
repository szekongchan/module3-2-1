terraform {
  required_version = ">= 1.14.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.31.0"
    }
  }
}

provider "aws" {
  region = "ap-southeast-1"
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

variable "log_bucket_name" {
  description = "Name of existing S3 bucket used for access logs"
  type        = string
}

variable "replica_bucket_arn" {
  description = "ARN of existing cross-region S3 replica bucket"
  type        = string
}

terraform {
  backend "s3" {
    bucket = "sctp-ce12-tfstate-bucket" # Change this
    key    = "sk-module3-2-1"           # Change this
    region = "ap-southeast-1"
  }
}

resource "aws_s3_bucket" "s3_tf" {
  bucket_prefix = "sk" # Set your bucket name here
}

resource "aws_s3_bucket_public_access_block" "s3_tf" {
  bucket                  = aws_s3_bucket.s3_tf.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "s3_tf" {
  bucket = aws_s3_bucket.s3_tf.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "s3_tf" {
  bucket = aws_s3_bucket.s3_tf.id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {
      prefix = ""
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_kms_key" "s3_tf" {
  description             = "KMS key for S3 default encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "s3_tf" {
  bucket = aws_s3_bucket.s3_tf.id

  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.s3_tf.arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_logging" "s3_tf" {
  bucket        = aws_s3_bucket.s3_tf.id
  target_bucket = var.log_bucket_name
  target_prefix = "access-logs/"
}

resource "aws_iam_role" "s3_replication" {
  name = "s3-replication-role-sk"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "s3_replication" {
  name = "s3-replication-policy-sk"
  role = aws_iam_role.s3_replication.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetReplicationConfiguration",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.s3_tf.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging"
        ]
        Resource = [
          "${aws_s3_bucket.s3_tf.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ]
        Resource = [
          "${var.replica_bucket_arn}/*"
        ]
      }
    ]
  })
}

resource "aws_s3_bucket_replication_configuration" "s3_tf" {
  role   = aws_iam_role.s3_replication.arn
  bucket = aws_s3_bucket.s3_tf.id

  rule {
    id     = "replicate-all"
    status = "Enabled"

    filter {
      prefix = ""
    }

    destination {
      bucket        = var.replica_bucket_arn
      storage_class = "STANDARD"
    }
  }

  depends_on = [
    aws_s3_bucket_versioning.s3_tf
  ]
}

resource "aws_sns_topic" "s3_events" {
  name              = "s3-events-sk"
  kms_master_key_id = "alias/aws/sns"
}

resource "aws_sns_topic_policy" "s3_events" {
  arn = aws_sns_topic.s3_events.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3Publish"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.s3_events.arn
        Condition = {
          ArnLike = {
            "aws:SourceArn" = aws_s3_bucket.s3_tf.arn
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_notification" "s3_tf" {
  bucket = aws_s3_bucket.s3_tf.id

  topic {
    topic_arn = aws_sns_topic.s3_events.arn
    events    = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_sns_topic_policy.s3_events]
}



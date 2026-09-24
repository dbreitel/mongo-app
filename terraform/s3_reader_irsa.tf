# EXERCISE REQUIREMENT (Outpost, Private Connectivity):
# a pod that can list and get objects from the backup bucket without
# traversing the public internet. The gateway endpoint in vpc_endpoints.tf
# provides the private path, this provides the identity.
#
# Deliberately least privilege, unlike the EC2 instance profile: two actions,
# scoped to this one bucket, assumable only by one named service account.

data "aws_iam_policy_document" "s3_reader" {
  statement {
    sid       = "ListTheBackupBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.backups.arn]
  }

  statement {
    sid       = "ReadBackupObjects"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.backups.arn}/*"]
  }
}

resource "aws_iam_policy" "s3_reader" {
  name   = "${var.cluster_name}-s3-reader"
  policy = data.aws_iam_policy_document.s3_reader.json
}

data "aws_iam_policy_document" "s3_reader_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.this.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    # binds the role to exactly one service account in one namespace.
    # without this condition ANY pod in the cluster could assume it.
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["system:serviceaccount:default:s3-reader"]
    }
  }
}

resource "aws_iam_role" "s3_reader" {
  name               = "${var.cluster_name}-s3-reader"
  assume_role_policy = data.aws_iam_policy_document.s3_reader_trust.json
}

resource "aws_iam_role_policy_attachment" "s3_reader" {
  role       = aws_iam_role.s3_reader.name
  policy_arn = aws_iam_policy.s3_reader.arn
}

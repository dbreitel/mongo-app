# Read-only identity for the Prowler workflow. Reuses the GitHub OIDC
# provider created in github_oidc.tf, so no credentials are stored.

data "aws_iam_policy_document" "github_prowler_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_repository}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "github_prowler" {
  name               = "${var.project}-github-prowler"
  assume_role_policy = data.aws_iam_policy_document.github_prowler_trust.json
}

# The pair AWS documents for Prowler. Both are read-only: no mutating
# action is granted, so the scanner cannot change what it audits.
resource "aws_iam_role_policy_attachment" "prowler" {
  # ViewOnlyAccess lives under job-function/, unlike SecurityAudit.
  # The bare arn:aws:iam::aws:policy/ViewOnlyAccess does not exist.
  for_each = toset([
    "arn:aws:iam::aws:policy/SecurityAudit",
    "arn:aws:iam::aws:policy/job-function/ViewOnlyAccess",
  ])
  role       = aws_iam_role.github_prowler.name
  policy_arn = each.value
}

# A handful of Prowler checks call APIs neither managed policy covers.
# Still read-only.
resource "aws_iam_role_policy" "prowler_extra" {
  name = "prowler-additions"
  role = aws_iam_role.github_prowler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "account:Get*",
        "appstream:Describe*",
        "codeartifact:List*",
        "codebuild:BatchGet*",
        "ds:Get*",
        "ds:Describe*",
        "ds:List*",
        "ec2:GetEbsEncryptionByDefault",
        "ecr:Describe*",
        "elasticfilesystem:DescribeBackupPolicy",
        "glue:GetConnections",
        "glue:GetSecurityConfiguration*",
        "glue:SearchTables",
        "lambda:GetFunction*",
        "logs:FilterLogEvents",
        "macie2:GetMacieSession",
        "s3:GetAccountPublicAccessBlock",
        "shield:DescribeProtection",
        "shield:GetSubscriptionState",
        "securityhub:BatchImportFindings",
        "securityhub:GetFindings",
        "ssm:GetDocument",
        "ssm-incidents:List*",
        "support:Describe*",
        "tag:GetTagKeys",
        "wellarchitected:List*"
      ]
      Resource = "*"
    }]
  })
}

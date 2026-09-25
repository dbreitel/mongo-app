# Identity the IaC pipeline assumes. Reuses the GitHub OIDC provider from
# github_oidc.tf, so no AWS keys are stored in GitHub.
#
# CHICKEN AND EGG: this role is created BY terraform, so the very first
# apply has to run from a laptop with your own credentials. After that the
# pipeline can manage everything including itself.

data "aws_iam_policy_document" "github_terraform_trust" {
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

# Broad by necessity: this role creates IAM roles, EKS clusters, VPCs and
# S3 buckets. Worth naming as a finding in its own right. The control that
# makes it defensible is the trust policy above, which pins it to one repo
# and one branch, plus the environment approval gate on the workflow.
resource "aws_iam_role" "github_terraform" {
  name               = "${var.project}-github-terraform"
  assume_role_policy = data.aws_iam_policy_document.github_terraform_trust.json
}

resource "aws_iam_role_policy_attachment" "github_terraform" {
  role       = aws_iam_role.github_terraform.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

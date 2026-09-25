# Partial backend config. The bucket and lock table are created by the
# bootstrap step in .github/workflows/iac-deploy.yaml, or by hand, before
# the first init. Values come from -backend-config so the same code works
# from a laptop and from CI.
#
# local:  terraform init -backend-config=backend.hcl
# CI:     terraform init -backend-config="bucket=..." -backend-config="key=..." ...
terraform {
  backend "s3" {}
}

# IRSA for the aws-load-balancer-controller. Terraform creates the IAM
# side, helm installs the controller itself (see README).
# REQUIREMENT: the app is exposed through a Kubernetes ingress backed by
# a CSP load balancer, which is what this controller provisions.

resource "aws_iam_policy" "alb_controller" {
  name = "${var.cluster_name}-alb-controller"
  # Vendored from aws-load-balancer-controller v3.5.0 rather than fetched at
  # apply time, so the permissions granted are reviewable in git. This MUST
  # track the chart version actually installed: v3 added 9 actions that v2.8.2
  # lacked, and the controller fails to reconcile an Ingress without them.
  policy = file("${path.module}/policies/alb-controller-iam-policy.json")
}

resource "aws_iam_role" "alb_controller" {
  name = "${var.cluster_name}-alb-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRoleWithWebIdentity"
      Principal = {
        Federated = aws_iam_openid_connect_provider.this.arn
      }
      Condition = {
        StringEquals = {
          "${local.oidc_host}:aud" = "sts.amazonaws.com"
          "${local.oidc_host}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}

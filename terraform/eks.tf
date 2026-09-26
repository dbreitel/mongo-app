# ---------- control plane IAM ----------

resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ---------- cluster ----------

# Created explicitly so retention is controlled. If EKS creates this group
# itself the logs are kept forever, which costs money quietly.
resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = 30
}

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  # EXERCISE REQUIREMENT: control plane audit logging.
  # "audit" is the one the requirement names, the rest give the full
  # control plane picture: who called what, and whether it was allowed.
  enabled_cluster_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler",
  ]

  vpc_config {
    # REQUIREMENT: cluster in private subnets. The control plane ENIs and
    # every node live here, nothing gets a public IP.
    subnet_ids = aws_subnet.private[*].id

    # private access so in-VPC traffic resolves the API to private IPs,
    # public access narrowed to one address for kubectl from your laptop
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = distinct(concat([var.home_ip], var.extra_allowed_cidrs))
  }

  # lets the IAM principal running terraform use kubectl immediately,
  # without hand editing the aws-auth ConfigMap
  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster,
    aws_cloudwatch_log_group.eks,
  ]
}

# ---------- node IAM ----------

resource "aws_iam_role" "node" {
  name = "${var.cluster_name}-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ])
  role       = aws_iam_role.node.name
  policy_arn = each.value
}

# ---------- node group ----------

resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "notes"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = aws_subnet.private[*].id
  instance_types  = [var.node_instance_type]

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = 1
    max_size     = 3
  }

  # REQUIREMENT: the web application runs on a specific node.
  # No label is set here on purpose. A node group label lands on EVERY
  # node in the group, which would let the pod schedule onto either one
  # and prove nothing. Instead label a single node after apply:
  #   kubectl label node <node-name> app-node=notes-app
  # That matches the nodeSelector in k8s/app.yaml and pins the pod to
  # one named node, which is also a live kubectl demonstration.

  depends_on = [aws_iam_role_policy_attachment.node]
}

# ---------- OIDC provider for IRSA ----------

data "tls_certificate" "oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "this" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]
}

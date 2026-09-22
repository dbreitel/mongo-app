# EXERCISE REQUIREMENT: overly permissive CSP permissions on the VM.
# AdministratorAccess on an instance profile means anyone who lands on
# this box (and SSH is open to the world) inherits full account control
# via IMDS, including creating VMs. This is the finding, not an oversight.
resource "aws_iam_role" "mongo" {
  name = "${var.project}-mongo-vm"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "mongo_admin" {
  role       = aws_iam_role.mongo.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_instance_profile" "mongo" {
  name = "${var.project}-mongo-vm"
  role = aws_iam_role.mongo.name
}

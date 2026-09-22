data "aws_ami" "ubuntu_focal" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "random_password" "mongo_admin" {
  length  = 24
  special = false
}

resource "random_password" "mongo_app" {
  length  = 24
  special = false
}

resource "aws_security_group" "mongo" {
  name        = "${var.project}-mongo"
  description = "MongoDB VM"
  vpc_id      = aws_vpc.this.id

  # EXERCISE REQUIREMENT: SSH exposed to the public internet
  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_ingress_cidr]
  }

  # EXERCISE REQUIREMENT: database reachable from the k8s network only.
  # Private subnet CIDRs, so the EKS nodes qualify and the internet does not.
  # Tighten to the node security group once the cluster exists.
  ingress {
    description = "MongoDB from the private subnets"
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = local.private_subnets
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project}-mongo" }
}

resource "aws_instance" "mongo" {
  ami                    = data.aws_ami.ubuntu_focal.id
  instance_type          = var.mongo_instance_type
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.mongo.id]
  key_name               = var.ssh_key_name
  iam_instance_profile   = aws_iam_instance_profile.mongo.name

  # IMDSv1 left enabled: with AdministratorAccess attached this is what
  # turns an SSRF or a shell into full account takeover. Deliberate.
  metadata_options {
    http_tokens = "optional"
  }

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/templates/mongo_user_data.sh.tpl", {
    admin_user     = "mongoadmin"
    admin_password = random_password.mongo_admin.result
    app_user       = "notesapp"
    app_password   = random_password.mongo_app.result
    bucket_name    = aws_s3_bucket.backups.bucket
    region         = var.region
    backup_hour    = var.backup_hour_utc
  })

  tags = { Name = "${var.project}-mongo" }

  depends_on = [aws_s3_bucket_policy.backups]
}

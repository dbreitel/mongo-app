variable "aws_profile" {
  type    = string
  default = "test7"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "notes-app"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

# The key pair already exists in AWS (created outside terraform, the
# private half is ~/.ssh/test7.pem). Referenced by name, not created,
# so terraform never sees the key material.
variable "ssh_key_name" {
  type    = string
  default = "test7"
}

# used only to build the ssh command in outputs
variable "ssh_private_key_path" {
  type    = string
  default = "~/.ssh/test7.pem"
}

# EXERCISE REQUIREMENT: SSH exposed to the public internet.
# Narrow this to your own /32 if you want the VM to survive the weekend.
variable "ssh_ingress_cidr" {
  type    = string
  default = "0.0.0.0/0"
}

variable "mongo_instance_type" {
  type    = string
  default = "t3.small"
}

variable "backup_hour_utc" {
  type    = number
  default = 3
}

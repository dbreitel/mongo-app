output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "mongo_public_ip" {
  value = aws_instance.mongo.public_ip
}

output "mongo_private_ip" {
  description = "put this in MONGO_HOST in k8s/app.yaml"
  value       = aws_instance.mongo.private_ip
}

output "ssh_command" {
  value = "ssh -i ${var.ssh_private_key_path} ubuntu@${aws_instance.mongo.public_ip}"
}

output "backup_bucket" {
  value = aws_s3_bucket.backups.bucket
}

output "backup_bucket_public_url" {
  description = "public listing, no credentials needed"
  value       = "https://${aws_s3_bucket.backups.bucket}.s3.${var.region}.amazonaws.com/"
}

# The password lives only in SSM, so terraform cannot build the URI without
# pulling the secret into state. This prints the command that builds it.
# The password MUST be percent-encoded: a literal @ : / ? # or % in it would
# otherwise be parsed as URI syntax, and the driver would read the text after
# the password's @ as the hostname.
output "mongodb_uri_command" {
  description = "run this to produce the URI for k8s/secret.yaml"
  value       = <<-EOT
    PW=$(aws ssm get-parameter --name ${var.mongo_password_parameter} --with-decryption --profile ${var.aws_profile} --region ${var.region} --query Parameter.Value --output text)
    ENC=$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$PW")
    echo "mongodb://notesapp:$ENC@${aws_instance.mongo.private_ip}:27017/notesapp?authSource=notesapp"
  EOT
}

output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.this.endpoint
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --name ${aws_eks_cluster.this.name} --region ${var.region} --profile ${var.aws_profile}"
}

output "alb_controller_role_arn" {
  description = "annotate the kube-system/aws-load-balancer-controller service account with this"
  value       = aws_iam_role.alb_controller.arn
}

output "app_node_label" {
  description = "matches the nodeSelector in k8s/app.yaml"
  value       = "app-node=notes-app"
}

output "s3_vpc_endpoint_id" {
  description = "gateway endpoint that keeps pod-to-S3 traffic off the internet"
  value       = aws_vpc_endpoint.s3.id
}

output "s3_reader_role_arn" {
  description = "annotate the default/s3-reader service account with this"
  value       = aws_iam_role.s3_reader.arn
}

output "github_deploy_role_arn" {
  description = "set as the AWS_DEPLOY_ROLE repository variable in GitHub"
  value       = aws_iam_role.github_deploy.arn
}

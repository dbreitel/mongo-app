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

output "mongodb_uri" {
  description = "terraform output -raw mongodb_uri, then paste into k8s/secret.yaml"
  sensitive   = true
  value       = "mongodb://notesapp:${random_password.mongo_app.result}@${aws_instance.mongo.private_ip}:27017/notesapp?authSource=notesapp"
}

output "mongo_admin_password" {
  sensitive = true
  value     = random_password.mongo_admin.result
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

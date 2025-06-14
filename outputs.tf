# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane"
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ids attached to the cluster control plane"
  value       = module.eks.cluster_security_group_id
}

output "region" {
  description = "AWS region"
  value       = var.aws_region
}

output "eks_cluster_name" {
  description = "Kubernetes Cluster Name"
  value       = module.eks.cluster_name
}

output "mongo_cluster_ip" {
  description = "Mongo Cluster IP"
  value       = aws_instance.my_instance.public_ip
}

output "s3_bucket_name" {
  description = "Name of S3 Bucket"
  value       = aws_s3_bucket.my_s3_bucket.bucket
}
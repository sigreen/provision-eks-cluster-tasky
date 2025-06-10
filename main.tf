# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

provider "aws" {
  region = var.region
}

# Filter out local zones, which are not currently supported 
# with managed node groups
data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  cluster_name = "education-eks-${random_string.suffix.result}"
}

resource "random_string" "suffix" {
  length  = 8
  special = false
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.8.1"

  name = "education-vpc"

  cidr = "10.0.0.0/16"
  azs  = slice(data.aws_availability_zones.available.names, 0, 3)

  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.8.5"

  cluster_name    = local.cluster_name
  cluster_version = "1.29"

  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true

  cluster_addons = {
    aws-ebs-csi-driver = {
      service_account_role_arn = module.irsa-ebs-csi.iam_role_arn
    }
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_group_defaults = {
    ami_type = "AL2_x86_64"

  }

  eks_managed_node_groups = {
    one = {
      name = "node-group-1"

      instance_types = ["t3.small"]

      min_size     = 1
      max_size     = 3
      desired_size = 2
    }

    two = {
      name = "node-group-2"

      instance_types = ["t3.small"]

      min_size     = 1
      max_size     = 2
      desired_size = 1
    }
  }
}


# https://aws.amazon.com/blogs/containers/amazon-ebs-csi-driver-is-now-generally-available-in-amazon-eks-add-ons/ 
data "aws_iam_policy" "ebs_csi_policy" {
  arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

module "irsa-ebs-csi" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-assumable-role-with-oidc"
  version = "5.39.0"

  create_role                   = true
  role_name                     = "AmazonEKSTFEBSCSIRole-${module.eks.cluster_name}"
  provider_url                  = module.eks.oidc_provider
  role_policy_arns              = [data.aws_iam_policy.ebs_csi_policy.arn]
  oidc_fully_qualified_subjects = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
}

# Mongo stuff
# Security Group for EC2 Instance
resource "aws_security_group" "ec2_sg" {
  name        = "ec2_sg"
  description = "Security group for EC2 instance"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port = 27017
    to_port   = 27017
    protocol  = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
   }
}
### db security group
resource aws_security_group "docdb-security-group"{
    name        = "docdb-sg"
    description = "Security group for documentdb"
    vpc_id      = module.vpc.vpc_id
    ingress {
        from_port = 27017
        to_port = 27017
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
}
resource "aws_key_pair" "ssh_keypair" {
  key_name   = "my-keypair"  # Replace with your desired key pair name
  public_key = file("${path.root}/keys/id_ed25519.pub")  # Replace with the path to your public key file
}
# EC2 Instance
resource "aws_instance" "my_instance" {
  ami             = "ami-0fc5d935ebf8bc3bc" # Ubuntu 20.04 LTS
  instance_type   = "t2.micro"
  key_name        = aws_key_pair.ssh_keypair.key_name
  subnet_id       = flatten([module.vpc.public_subnets])[0]
  security_groups  = [aws_security_group.ec2_sg.id]
  associate_public_ip_address = true
  user_data = <<-EOF
              #!/bin/bash
              apt-get update
              apt-get install gnupg curl
              curl -fsSL https://pgp.mongodb.com/server-7.0.asc | \
              gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg \
              --dearmor
              echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list
              apt-get update
              apt-get install -y mongodb-org
              sudo sed -i 's/bindIp: 127.0.0.1/bindIp: 0.0.0.0/g' /etc/mongod.conf
              systemctl start mongod
              systemctl enable mongodb
              EOF
 tags = {
    Name = "my-ssh-tunnel-server"

 }
}

# DocumentDB Cluster
resource "aws_docdb_cluster_instance" "mydocdb_instance" {
  identifier           = "docdb-cluster-instance"
  cluster_identifier   = aws_docdb_cluster.docdb_cluster.id
  instance_class       = "db.t3.medium"  # Replace with your desired instance type
#   publicly_accessible  = false
}
resource "aws_docdb_subnet_group" "subnet_group" {
  name       = "db-subnet-group"
  subnet_ids = module.vpc.private_subnets
}
resource "aws_docdb_cluster" "docdb_cluster" {
  cluster_identifier   = "docdb-cluster"
  availability_zones   = ["us-east-1a","us-east-1b","us-east-1c"]  # Replace with your desired AZs
  engine_version       = "4.0.0"
  master_username      = "adminuser"
  master_password      = "password123"  # Replace with your own strong password
  backup_retention_period = 5  # Replace with your desired retention period
  preferred_backup_window = "07:00-09:00"  # Replace with your desired backup window
  skip_final_snapshot   = true
  db_subnet_group_name = aws_docdb_subnet_group.subnet_group.name
  vpc_security_group_ids = [aws_security_group.docdb-security-group.id]
  # Additional cluster settings can be configured here
}
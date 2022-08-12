# Multi-stage Dockerfile
------------------------

FROM ubuntu
WORKDIR /tmp
RUN apt update  
RUN apt install nginx -y
EXPOSE 80
RUN ["/usr/sbin/nginx", "-g", "daemon off;"]

FROM alpine:latest  
RUN apk --no-cache add ca-certificates
WORKDIR /root/
COPY --from=builder /go/src/github.com/alexellis/href-counter/app ./
CMD ["./app"]  


# Elastic Container Regitry (ECR)
---------------------------------

aws ecr get-login-password --region region | docker login --username AWS --password-stdin aws_account_id.dkr.ecr.region.amazonaws.com
docker push aws_account_id.dkr.ecr.region.amazonaws.com/sample-test:latest
docker pull aws_account_id.dkr.ecr.region.amazonaws.com/sample-test:latest

# Using Infrastructure as Code tool (Terraform) to EKS (Kubernetes Cluster) in AWS.
-----------------------------------------------------------------------------------

# Variables

variable "instance_type_eks" {
  description = "EKS Instance Types"
  default = "t3.medium"
}
variable "capacity_type_eks" {
  description = "EKS capacity type"
  default = "SPOT"
}
variable "desired_size" {
  description = "Desired number of Nodes"
  default = 1
}
variable "max_size" {
  description = "Maximum number of nodes that can be in a cluster"
  default = 5
}
variable "min_size" { 
  description = "Minimum number of nodes that should be in a cluster"
  default = 1
}
variable "max_unavailable" {
  description = " Maximum number of nodes that can be unavailable in a cluster"
  default = 1
}


# Role for EKS Cluster
resource "aws_iam_role" "team-role" {
  name = "eks-cluster-team"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

# EKS Cluster

resource "aws_iam_role_policy_attachment" "team-AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.team-role.name
}

resource "aws_iam_role_policy_attachment" "team-AmazonEKSVPCResourceController" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.team-role.name
}

resource "aws_iam_role_policy_attachment" "team-AmazonECR_FullaccessPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryFullAccess"
  role       = aws_iam_role.team-role.name
}

resource "aws_eks_cluster" "team" {
  name     = "team-cluster"
  role_arn = aws_iam_role.team-role.arn

  vpc_config {
    subnet_ids = [aws_subnet.public-subnet-1.id,aws_subnet.public-subnet-2.id]
    endpoint_private_access = true
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Cluster handling.
  # Otherwise, EKS will not be able to properly delete EKS managed EC2 infrastructure such as Security Groups.
  depends_on = [
    aws_iam_role_policy_attachment.team-AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.team-AmazonEKSVPCResourceController,
    aws_iam_role_policy_attachment.team-AmazonECR_FullaccessPolicy,
  ]
}


# Node Group

resource "aws_eks_node_group" "node-team" {
  cluster_name    = aws_eks_cluster.team.name
  node_group_name = "Team-group"
  node_role_arn   = aws_iam_role.team.arn
  subnet_ids      = [aws_subnet.public-subnet-1.id]
  instance_types  = [var.instance_type_eks]
  capacity_type   = var.capacity_type_eks
  scaling_config {
    desired_size = var.desired_size
    max_size     = var.max_size
    min_size     = var.min_size
  }

  update_config {
    max_unavailable = var.max_unavailable
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  # Otherwise, EKS will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
  depends_on = [
    aws_iam_role_policy_attachment.team-AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.team-AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.team-AmazonEC2ContainerRegistryReadOnly,
  ]
}

# Role for the Node Group

resource "aws_iam_role" "team" {
  name = "eks-node-group-team"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "team-AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.team.name
}

resource "aws_iam_role_policy_attachment" "team-AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.team.name
}

resource "aws_iam_role_policy_attachment" "team-AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.team.name
}
# Common tags for all resources
locals {
  common_tags = {
    owner = "meirt"
    TTL   = "3W"
  }
}

# VPC Module
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.2"

  name = var.cluster_name
  cidr = "10.0.0.0/16"

  azs             = ["eu-west-1a", "eu-west-1b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  # Tags for AWS Load Balancer Controller subnet auto-discovery
  public_subnet_tags = {
    "kubernetes.io/role/elb"                      = "1"
    "kubernetes.io/cluster/${var.cluster_name}"   = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"             = "1"
    "kubernetes.io/cluster/${var.cluster_name}"   = "shared"
  }

  tags = merge(local.common_tags, {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  })
}

# IAM Role for EKS Cluster
resource "aws_iam_role" "eks_cluster_role" {
  name = "eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# IAM Role for EKS Nodes
resource "aws_iam_role" "eks_node_role" {
  name = "eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "node_policies" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  ])

  role       = aws_iam_role.eks_node_role.name
  policy_arn = each.value
}

# EKS Cluster Module
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.8.4"

  cluster_name    = var.cluster_name
  cluster_version = "1.31"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Use custom IAM role
  create_iam_role = false
  iam_role_arn    = aws_iam_role.eks_cluster_role.arn

  # Enable public access to cluster endpoint
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  # Grant cluster creator admin permissions
  enable_cluster_creator_admin_permissions = true

  enable_irsa = true

  tags = local.common_tags

  eks_managed_node_groups = {
    small_nodes = {
      desired_size   = 3
      max_size       = 3
      min_size       = 3
      instance_types = ["t2.small"]

      # Custom labels for node selection
      labels = {
        "node.type" = "node.small"
        node-size = "t2.small"
        pool      = "node_small"
      }

      # Use custom node IAM role
      create_iam_role = false
      iam_role_arn    = aws_iam_role.eks_node_role.arn
    }

    medium_nodes = {
      desired_size   = 2
      max_size       = 2
      min_size       = 2
      instance_types = ["t2.medium"]

      # Custom labels for node selection
      labels = {
        "node.type" = "node.medium"
        node-size = "t2.medium"
        pool      = "node_medium"
      }

      # Use custom node IAM role
      create_iam_role = false
      iam_role_arn    = aws_iam_role.eks_node_role.arn
    }
  }
}

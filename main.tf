locals {
  access_policies = {
    admin = {
      statement = [{
        Effect   = "Allow"
        Resource = aws_eks_cluster.this.arn
        Action   = "eks:*"
      }]
    }
    describe = {
      statement = [{
        Effect   = "Allow"
        Resource = aws_eks_cluster.this.arn
        Action   = "eks:DescribeCluster"
      }]
    }
  }
}

data "aws_region" "current" {}

module "role" {
  source  = "ptonini/iam-role/aws"
  version = "~> 3.0.0"
  name    = "eks-${var.name}"
  assume_role_policy_statements = [{
    Effect    = "Allow"
    Principal = { Service = "eks.amazonaws.com" }
    Action    = "sts:AssumeRole"
  }]
  policy_arns = [
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy",
    "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
  ]
  policy_statements = [
    {
      Effect   = "Allow"
      Resource = ["arn:aws:iam::*:role/aws-service-role/*"]
      Action   = ["iam:CreateServiceLinkedRole"]
    },
    {
      Effect   = "Allow"
      Resource = "*"
      Action = [
        "ec2:DescribeAccountAttributes",
        "ec2:DescribeInternetGateways"
      ]
    }
  ]
}

resource "aws_eks_cluster" "this" {
  name     = var.name
  role_arn = module.role.this.arn
  version  = var.kubernetes_version
  vpc_config {
    subnet_ids              = var.vpc_config.subnet_ids
    endpoint_private_access = var.vpc_config.endpoint_private_access
    endpoint_public_access  = var.vpc_config.endpoint_public_access
    public_access_cidrs     = var.vpc_config.public_access_cidrs
    security_group_ids      = var.vpc_config.security_group_ids
  }
  lifecycle {
    ignore_changes = [
      vpc_config[0].security_group_ids
    ]
  }
  depends_on = [
    module.role
  ]
}

module "node_group" {
  source                 = "ptonini/eks-node-group/aws"
  version                = "~> 1.0.0"
  for_each               = var.node_groups
  cluster_name           = aws_eks_cluster.this.name
  name                   = each.key
  instance_type          = each.value.instance_type
  subnet_ids             = each.value.subnet_ids
  ssh_key                = each.value.ssh_key
  desired_size           = each.value.desired_size
  max_size               = each.value.max_size
  min_size               = each.value.min_size
  user_data              = each.value.user_data
  node_pool_class        = each.value.node_pool_class
  taints                 = each.value.taints
  vpc_security_group_ids = concat(each.value.vpc_security_group_ids == null ? [] : each.value.vpc_security_group_ids, [aws_eks_cluster.this.vpc_config[0].cluster_security_group_id])
  tags                   = each.value.tags
}

resource "aws_eks_addon" "this" {
  for_each     = var.addons
  cluster_name = aws_eks_cluster.this.name
  addon_name   = each.key
}

resource "aws_iam_openid_connect_provider" "this" {
  client_id_list  = var.openid_connect_provider.client_id_list
  thumbprint_list = var.openid_connect_provider.thumbprint_list
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

module "sa_role" {
  source   = "ptonini/iam-role/aws"
  version  = "~> 3.0.0"
  for_each = var.sa_roles
  name     = "eks-${var.name}-sa-${each.key}"
  assume_role_policy_statements = [{
    Effect    = "Allow"
    Principal = { Federated = aws_iam_openid_connect_provider.this.arn }
    Action    = "sts:AssumeRoleWithWebIdentity"
    Condition = {
      StringEquals = {
        "${replace(aws_iam_openid_connect_provider.this.url, "https://", "")}:sub" : "system:serviceaccount:${each.value.namespace}:${each.key}"
      }
    }
  }]
  policy_arns = each.value.policy_arns
}

module "access_policies" {
  source   = "ptonini/iam-policy/aws"
  version  = "~> 1.0.0"
  for_each = local.access_policies
  name     = "eks-${var.name}-${each.key}-access"
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = each.value.statement
  })
}

data "aws_eks_cluster_auth" "this" {
  name = aws_eks_cluster.this.name
}
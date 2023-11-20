output "this" {
  value = aws_eks_cluster.this
}

output "token" {
  value = data.aws_eks_cluster_auth.this.token
}

output "sa_role_arns" {
  value = { for k, v in module.sa_role : k => v.this.arn }
}

output "sa_role_helm_release_values" {
  value = { for k, v in module.sa_role : k => {
    serviceaccount = {
      enabled     = true
      annotations = { "eks.amazonaws.com/role-arn" = v.this.arn }
    }
  } }
}

output "access_policy_arns" {
  value = { for k, v in module.access_policies : k => v.this.arn }
}
output "cluster_id" {
  value       = module.hcp.cluster_id
  description = "Unique identifier of the cluster."
}

output "account_role_prefix" {
  value       = module.hcp.account_role_prefix
  description = "The prefix used for all generated AWS resources."
}

output "account_roles_arn" {
  value       = module.hcp.account_roles_arn
  description = "A map of Amazon Resource Names (ARNs) associated with the AWS IAM roles created. The key in the map represents the name of an AWS IAM role, while the corresponding value represents the associated Amazon Resource Name (ARN) of that role."
}

output "path" {
  value       = module.hcp.path
  description = "The arn path for the account/operator roles as well as their policies."
}

output "oidc_config_id" {
  value       = module.hcp.oidc_config_id
  description = "The unique identifier associated with users authenticated through OpenID Connect (OIDC) generated by this OIDC config."
}

output "oidc_endpoint_url" {
  value       = module.hcp.oidc_endpoint_url
  description = "Registered OIDC configuration issuer URL, generated by this OIDC config."
}

output "oidc_arn" {
  value  = data.aws_iam_openid_connect_provider.cluster_oidc.arn
}

output "operator_role_prefix" {
  value       = module.hcp.operator_role_prefix
  description = "Prefix used for generated AWS operator policies."
}

output "operator_roles_arn" {
  value       = module.hcp.operator_roles_arn
  description = "List of Amazon Resource Names (ARNs) for all operator roles created."
}

output "cluster_demo_user_password" {
  value     = resource.random_password.rosa_password
  sensitive = true
}

output "cluster_admin_password" {
  value     = module.hcp.cluster_admin_password
  sensitive = true
}

output "cluster_api_url" {
  value     = module.hcp.cluster_api_url
}

output "cluster_console_url" {
  value     = module.hcp.cluster_console_url
}

output "vpc_id" {
  value    = module.vpc.vpc_id
}

output "efs_resource_id" {
  value  = module.efs.id
}

output rds_database_arn {
  value   = resource.aws_db_instance.rds_postgres.arn
}

output rds_database_user {
  value   = resource.aws_db_instance.rds_postgres.username  
}

output rds_database_password {
  value     = resource.aws_db_instance.rds_postgres.password
  sensitive = true
}

output rds_database_address {
  value    = resource.aws_db_instance.rds_postgres.address
}

output rds_database_schema {
  value = resource.aws_db_instance.rds_postgres.db_name
}

output s3_bucket_pictures {
  value = resource.aws_s3_bucket.s3_bucket_pictures.bucket
}

output "s3_bucket_pictures_policy" {
  description = "IAM policy allowing access to the specific S3 bucket"
  value = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = "${resource.aws_s3_bucket.s3_bucket_pictures.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = [
          "s3:ListBucket"
        ]
        Resource = resource.aws_s3_bucket.s3_bucket_pictures.arn
      }
    ]
  })
}


output demo_role_arn {
  value = resource.aws_iam_role.demo_role.arn
}

output demo_namespace {
  value = var.demo_namespace
}

output demo_service_account {
  value = local.demo_service_account
}
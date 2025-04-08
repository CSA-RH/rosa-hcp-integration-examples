locals {
  account_role_prefix  = "${var.cluster_name}-account"
  operator_role_prefix = "${var.cluster_name}-operator"

  demo_service_account = "${var.cluster_name}-demo-app-sa"

  rds_iam_user         = "rds_iam_user"
}

############################
# Cluster
############################
data "aws_caller_identity" "current" {}

module "hcp" {
  source = "terraform-redhat/rosa-hcp/rhcs"

  cluster_name             = var.cluster_name
  openshift_version        = var.openshift_version
  machine_cidr             = module.vpc.cidr_block
  aws_subnet_ids           = concat(module.vpc.public_subnets, module.vpc.private_subnets)
  aws_availability_zones   = module.vpc.availability_zones
  replicas                 = length(module.vpc.availability_zones)
  create_admin_user        = true
  ec2_metadata_http_tokens = "required"

  // STS configuration
  create_account_roles     = true
  account_role_prefix      = local.account_role_prefix
  create_oidc              = true
  create_operator_roles    = true
  operator_role_prefix     = local.operator_role_prefix
  aws_billing_account_id   = coalesce(var.aws_billing_account_id, data.aws_caller_identity.current.account_id)
}


############################
# HTPASSWD IDP
############################
module "htpasswd_idp" {
  source = "terraform-redhat/rosa-hcp/rhcs//modules/idp"

  cluster_id         = module.hcp.cluster_id
  name               = "htpasswd-idp"
  idp_type           = "htpasswd"
  htpasswd_idp_users = [{ username = "demo-user", password = random_password.rosa_password.result }]
}

resource "random_password" "rosa_password" {
  length      = 14
  special     = true
  min_lower   = 1
  min_numeric = 1
  min_special = 1
  min_upper   = 1
}

############################
# VPC
############################
module "vpc" {
  source = "./modules/vpc"

  vpc_cidr                 = var.cluster_vpc_cidr

  name_prefix              = var.cluster_name
  availability_zones_count = 3
}

############################
# EFS
############################
module "efs" {
  source = "terraform-aws-modules/efs/aws"
  name   = "rosa-hcp-efs"  
  
  enable_backup_policy = false
  create_backup_policy = false
  create_security_group = false

  mount_targets              = { for k, v in zipmap(module.vpc.availability_zones, module.vpc.private_efs_subnets) : k => { subnet_id = v } }

  security_group_vpc_id      = module.vpc.vpc_id
}

# Get the default security group for the VPC
data "aws_security_group" "default" {
  vpc_id = module.vpc.vpc_id

  filter {
    name   = "group-name"
    values = ["default"]
  }
}

# Add an inbound rule to the default security group
resource "aws_security_group_rule" "allow_ingress" {
  type        = "ingress"
  from_port   = 2049
  to_port     = 2049
  protocol    = "tcp"
  cidr_blocks = [var.cluster_vpc_cidr]
  security_group_id = data.aws_security_group.default.id
}

############################
# RDS
############################
resource "aws_security_group" "db_sg" {
  name        = "postgres-db-sg"
  description = "Allow access to RDS PostgreSQL"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.cluster_vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_subnet_group" "postgres" {
  name       = "pg-subnet-group"
  subnet_ids = module.vpc.private_efs_subnets

  tags = {
    Name = "Postgres DB subnet group"
  }
}

resource "aws_db_instance" "rds_postgres" {
  identifier                          = "cluster-db-demo"
  engine                              = "postgres"
  engine_version                      = "17"
  instance_class                      = "db.t4g.micro"
  allocated_storage                   = 5
  storage_type                        = "gp2"
  username                            = "postgres"
  password                            = random_password.rds_password.result
  db_name                             = "dbschematest"
  multi_az                            = true
  publicly_accessible                 = false
  skip_final_snapshot                 = true
  deletion_protection                 = false
  vpc_security_group_ids              = [aws_security_group.db_sg.id]
  db_subnet_group_name                = aws_db_subnet_group.postgres.name
  iam_database_authentication_enabled = true

  tags = {
    Environment = "ROSA HCP Demo"
  }
}

resource "random_password" "rds_password" {
  length  = 14
  special = true
  min_lower = 1
  min_numeric = 1
  min_special = 1
  min_upper = 1
}

############################
# DynamoDB
############################

resource "aws_dynamodb_table" "dynamodb_items_table" {
  name           = "Items"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "Timestamp"

  attribute {
    name = "Timestamp"
    type = "S"
  }

  ttl {
    attribute_name = "TimeToExist"
    enabled        = false
  }

  tags = {
    Environment = "ROSA HCP Demo"
  }
}

############################
# S3 bucket
############################

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false

/*  lifecycle {
    prevent_destroy = true
  }*/
}

resource "aws_s3_bucket" "s3_bucket_pictures" {
  bucket = "picture-repository-${random_string.suffix.id}"

  tags = {
    Environment = "ROSA HCP Demo"
  }
}

############################
# IAM permissions
############################
data "aws_iam_openid_connect_provider" "cluster_oidc" {
  url = "https://${module.hcp.oidc_endpoint_url}"

  # Optional: prevent issues for ordering
  depends_on = [module.hcp]
}

data "aws_iam_policy_document" "trust_oidc" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.cluster_oidc.arn] 
    }

    condition {
      test     = "StringEquals"
      variable = "${module.hcp.oidc_endpoint_url}:sub"
      values   = ["system:serviceaccount:${var.demo_namespace}:${local.demo_service_account}"]
    }
  }
}

# For S3
data "aws_iam_policy" "s3_full_access" {
  name = "AmazonS3FullAccess"
}

# Policy for RDS
data "aws_region" "current" {}

resource "aws_iam_policy" "rds_connect_policy" {
  name        = "${var.cluster_name}-rds-demo-policy"
  description = "Allows connection to RDS"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "rds-db:connect"
        Resource = "arn:aws:rds-db:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_db_instance.rds_postgres.resource_id}/${local.rds_iam_user}"
      }
    ]
  })
}


# Policy for DynamoDB
data "aws_iam_policy_document" "dynamodb_crud" {
  statement {
    effect = "Allow"

    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
      "dynamodb:Scan",
      "dynamodb:Query",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem"
    ]

    resources = [
      aws_dynamodb_table.dynamodb_items_table.arn
    ]
  }
}

resource "aws_iam_policy" "dynamodb_crud_policy" {
  name        = "${var.cluster_name}-dynamodb-demo-policy"
  description = "Allows basic CRUD and query access to the Items table"
  policy      = data.aws_iam_policy_document.dynamodb_crud.json
}

# Role creation
resource "aws_iam_role" "demo_role" {
  name               = "${var.cluster_name}-demo-app-role"
  assume_role_policy = data.aws_iam_policy_document.trust_oidc.json
}

resource "aws_iam_role_policy_attachment" "attach_s3_policy_to_demo_role" {
  role       = aws_iam_role.demo_role.name
  policy_arn = data.aws_iam_policy.s3_full_access.arn
}

resource "aws_iam_role_policy_attachment" "attach_rds_policy_to_demo_role" {
  role       = aws_iam_role.demo_role.name
  policy_arn = aws_iam_policy.rds_connect_policy.arn
}

resource "aws_iam_role_policy_attachment" "attach_dynamodb_policy_to_demo_role" {
  role       = aws_iam_role.demo_role.name
  policy_arn = aws_iam_policy.dynamodb_crud_policy.arn
}

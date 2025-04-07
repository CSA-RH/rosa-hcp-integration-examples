output "private_subnets" {
  value       = sort(aws_subnet.private_subnet[*].id)
  description = "List of private subnets created in the AWS VPC"
}

output "public_subnets" {
  value       = sort(aws_subnet.public_subnet[*].id)
  description = "List of public subnets created in the AWS VPC"
}

output "private_efs_subnets" {
  value       = sort(aws_subnet.efs_subnet[*].id)
  description =  "List of private EFS subnets created in the AWS VPC"
}

output "availability_zones" {
  value       = aws_subnet.private_subnet[*].availability_zone
  description = "List of the Availability Zone names used for the VPC creation"
}

output "vpc_id" {
  value       = time_sleep.vpc_resources_wait.triggers["vpc_id"]
  description = "The unique ID of the VPC"
}

output "cidr_block" {
  value       = time_sleep.vpc_resources_wait.triggers["cidr_block"]
  description = "The CIDR block of the VPC for the association."
}

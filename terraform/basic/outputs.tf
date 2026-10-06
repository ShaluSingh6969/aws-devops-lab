output "vpc_id" {
  description = "ID of the Terraform-managed VPC"
  value       = aws_vpc.day6_vpc.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.day6_vpc.cidr_block
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.public_a.id
}
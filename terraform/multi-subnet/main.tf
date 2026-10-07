terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  common_tags = {
    Environment = var.environment
    Project     = "terraform-multi-subnet-lab"
    ManagedBy   = "Terraform"
  }
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(
    local.common_tags,
    {
      Name = "${var.environment}-terraform-vpc"
    }
  )
}

resource "aws_subnet" "public" {
  for_each = var.public_subnets

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true

  tags = merge(
    local.common_tags,
    {
      Name = "${var.environment}-${each.key}"
    }
  )
}

resource "aws_subnet" "count_demo" {
  count = length(var.count_subnets)

  vpc_id     = aws_vpc.main.id
  cidr_block = var.count_subnets[count.index]

  tags = merge(
    local.common_tags,
    {
      Name = "count-demo-${count.index}"
    }
  )
}
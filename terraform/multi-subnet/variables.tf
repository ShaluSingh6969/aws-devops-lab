variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.60.0.0/16"
}

variable "public_subnets" {
  description = "Public subnet configuration"

  type = map(object({
    cidr = string
    az   = string
  }))

  default = {
    public_a = {
      cidr = "10.60.1.0/24"
      az   = "eu-central-1a"
    }

    public_c = {
      cidr = "10.60.3.0/24"
      az   = "eu-central-1c"
    }
  }
}

variable "count_subnets" {
  type = list(string)

  default = [
    "10.60.10.0/24",
    "10.60.11.0/24",
    "10.60.12.0/24"
  ]
}
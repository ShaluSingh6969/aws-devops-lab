# Day 6 - Terraform Fundamentals and AWS Infrastructure as Code

## Goal

The objective of this lab was to move from manually creating AWS infrastructure with the AWS CLI to managing infrastructure declaratively using Terraform.

The focus was not on memorizing Terraform syntax, but on understanding:

- Terraform providers
- resources
- variables
- outputs
- state
- plans
- drift detection
- implicit dependencies
- resource references
- execution order
- dependency graphs
- infrastructure reconciliation

The AWS concepts themselves were already familiar from previous labs, which made it easier to understand Terraform as a way to express the same infrastructure as code.

---

# 1. Terraform Installation

Terraform was installed inside WSL Ubuntu using the official HashiCorp repository.

Verification:

```bash
terraform version
```

and:

```bash
which terraform
```

Terraform was then used from the AWS DevOps lab repository.

---

# 2. Terraform Working Directory

Terraform was initialized inside the directory containing the Terraform configuration:

```text
aws-devops-lab/
└── terraform/
    └── basic/
        ├── main.tf
        ├── variables.tf
        ├── outputs.tf
        ├── terraform.tfstate
        ├── .terraform/
        └── .terraform.lock.hcl
```

Important:

```text
terraform init
```

should normally be executed inside the directory containing the `.tf` files.

---

# 3. Initial Terraform Configuration

The first configuration created one VPC.

Example:

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}

resource "aws_vpc" "day6_vpc" {
  cidr_block           = "10.50.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "day6-terraform-vpc"
  }
}
```

---

# 4. Terraform Provider

The provider tells Terraform which external platform/API it needs to communicate with.

Example:

```hcl
provider "aws" {
  region = "eu-central-1"
}
```

Terraform uses the AWS provider plugin:

```text
hashicorp/aws
```

The provider communicates with AWS APIs.

No AWS credentials were hardcoded in Terraform.

Terraform reused the same AWS credential chain already configured for the AWS CLI.

Conceptually:

```text
Terraform
    |
    v
AWS Provider
    |
    v
AWS Credential Chain
    |
    v
IAM User / Role
    |
    v
AWS APIs
```

---

# 5. Terraform Init

The project was initialized with:

```bash
terraform init
```

This downloaded the required provider and created:

```text
.terraform/
.terraform.lock.hcl
```

The lock file records the selected provider versions/checksums so future runs use consistent dependencies.

---

# 6. Format and Validation

Formatting:

```bash
terraform fmt
```

Validation:

```bash
terraform validate
```

These commands are useful before creating or modifying infrastructure.

---

# 7. Terraform Plan

The first plan showed:

```text
Plan: 1 to add, 0 to change, 0 to destroy.
```

Symbols used by Terraform include:

```text
+  create
~  update in-place
-  destroy
-/+ replace
```

Some resource attributes appeared as:

```text
(known after apply)
```

Examples:

```text
id
arn
default_route_table_id
default_security_group_id
default_network_acl_id
```

These values do not exist until AWS actually creates the resource.

---

# 8. Saved Terraform Plan

Instead of directly applying, the plan was saved:

```bash
terraform plan -out=tfplan
```

Then applied using:

```bash
terraform apply tfplan
```

This provides a more controlled workflow:

```text
Plan
-> review
-> save exact plan
-> apply reviewed plan
```

The `tfplan` file is stored in the current Terraform working directory.

It is a binary file and should not be manually edited.

---

# 9. Terraform State

After `terraform apply`, Terraform created:

```text
terraform.tfstate
```

Terraform state maps Terraform resources to real infrastructure.

Example:

```text
aws_vpc.day6_vpc
        |
        v
vpc-053d4eb469ad22be4
```

State contains information such as:

```text
resource ID
ARN
attributes
tags
route table ID
security group ID
NACL ID
provider information
```

---

# 10. Inspect Terraform State

List managed resources:

```bash
terraform state list
```

Example:

```text
aws_vpc.day6_vpc
```

Inspect a specific resource:

```bash
terraform state show aws_vpc.day6_vpc
```

This displayed values such as:

```text
VPC ID
ARN
default route table
default security group
default NACL
DHCP options
CIDR
tags
```

The same underlying information exists in JSON format inside:

```text
terraform.tfstate
```

Important:

```text
terraform.tfstate
```

should normally not be manually edited.

---

# 11. Desired State vs Actual State

The core Terraform mental model is:

```text
Terraform configuration
= desired state

Terraform state
= Terraform's tracked mapping

AWS
= actual infrastructure

terraform plan
= compare desired state with reality

terraform apply
= reconcile reality toward desired state
```

---

# 12. Drift Detection

A manual change was made outside Terraform using the AWS CLI.

Original Terraform configuration:

```text
Name = day6-terraform-vpc
```

Manual AWS change:

```text
Name = day6-manual-change
```

Terraform then detected the difference:

```bash
terraform plan
```

Output:

```text
~ update in-place

"Name" = "day6-manual-change" -> "day6-terraform-vpc"
```

Summary:

```text
Plan: 0 to add, 1 to change, 0 to destroy.
```

This demonstrated configuration drift.

---

# 13. Drift Reconciliation

The drift correction plan was saved:

```bash
terraform plan -out=tfplan
```

and applied:

```bash
terraform apply tfplan
```

Terraform restored AWS to the value defined in code:

```text
day6-terraform-vpc
```

This demonstrated the IaC principle:

```text
Terraform configuration
should remain the desired source of truth.
```

---

# 14. Variables

Hardcoded values were moved into variables.

Example `variables.tf`:

```hcl
variable "aws_region" {
  description = "AWS region for the lab"
  type        = string
  default     = "eu-central-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.50.0.0/16"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.50.1.0/24"
}
```

Variables are referenced using:

```hcl
var.aws_region
var.vpc_cidr
var.environment
var.public_subnet_cidr
```

---

# 15. Outputs

Example `outputs.tf`:

```hcl
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
```

Outputs can be viewed using:

```bash
terraform output
```

Outputs are useful for:

```text
human-readable results
CI/CD pipelines
module integration
passing values between infrastructure layers
```

---

# 16. Resource References

The subnet referenced the VPC:

```hcl
resource "aws_subnet" "public_a" {
  vpc_id = aws_vpc.day6_vpc.id
}
```

This expression:

```hcl
aws_vpc.day6_vpc.id
```

references an attribute from another Terraform resource.

Terraform resource address:

```text
aws_vpc.day6_vpc
```

breaks down into:

```text
aws_vpc
= resource type

day6_vpc
= local Terraform resource name
```

---

# 17. Implicit Dependencies

Because the subnet referenced:

```hcl
aws_vpc.day6_vpc.id
```

Terraform automatically understood:

```text
Subnet depends on VPC
```

No explicit dependency was required.

Conceptually:

```text
VPC
 |
 v
Subnet
```

This is called an implicit dependency.

---

# 18. Public Subnet

A public subnet was created:

```hcl
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.day6_vpc.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = "eu-central-1a"
  map_public_ip_on_launch = true

  tags = {
    Name        = "day6-public-a"
    Environment = var.environment
  }
}
```

Terraform created:

```text
subnet-098d1c4c1bccdabf0
```

---

# 19. Internet Gateway

An Internet Gateway was added:

```hcl
resource "aws_internet_gateway" "day6_igw" {
  vpc_id = aws_vpc.day6_vpc.id

  tags = {
    Name        = "day6-igw"
    Environment = var.environment
  }
}
```

Dependency:

```text
Internet Gateway
depends on
VPC
```

because of:

```hcl
vpc_id = aws_vpc.day6_vpc.id
```

---

# 20. Route Table

A public route table was created:

```hcl
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.day6_vpc.id

  tags = {
    Name        = "day6-public-rt"
    Environment = var.environment
  }
}
```

---

# 21. Default Internet Route

```hcl
resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.day6_igw.id
}
```

This resource depends on:

```text
Route Table
AND
Internet Gateway
```

Terraform inferred both dependencies automatically.

---

# 22. Route Table Association

The subnet was associated with the route table:

```hcl
resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}
```

Dependency:

```text
Subnet
+
Route Table
    |
    v
Route Table Association
```

---

# 23. Dependency Graph

The infrastructure dependency graph is approximately:

```text
                    VPC
                 /   |   \
                /    |    \
               v     v     v
            Subnet  IGW  Route Table
               |           |     |
               |           |     |
               |           +---> Route
               |                 ^
               |                 |
               +-------> Association
                         ^
                         |
                    Route Table
```

More precisely:

```text
VPC
├── Subnet
├── Internet Gateway
└── Route Table

Route Table + Internet Gateway
└── Default Route

Subnet + Route Table
└── Route Table Association
```

---

# 24. Terraform Creation Order

The order shown in:

```bash
terraform plan
```

should not be treated as the guaranteed resource creation order.

Terraform builds a dependency graph.

Independent resources may be created in parallel.

Example:

```text
Subnet
Internet Gateway
Route Table
```

can all be created after the VPC exists.

Terraform does not need to create these three sequentially.

However:

```text
Default Route
```

cannot be created until:

```text
Route Table
AND
Internet Gateway
```

exist.

Likewise:

```text
Route Table Association
```

cannot be created until:

```text
Subnet
AND
Route Table
```

exist.

---

# 25. Implicit vs Explicit Dependencies

Preferred:

```hcl
vpc_id = aws_vpc.day6_vpc.id
```

This automatically creates an implicit dependency.

Explicit dependency syntax:

```hcl
depends_on = [
  aws_vpc.day6_vpc
]
```

should generally only be used when a real dependency exists but Terraform cannot infer it from resource references.

Rule:

```text
Prefer implicit dependencies.

Use depends_on only when necessary.
```

---

# 26. Terraform Graph

Terraform can expose its dependency graph:

```bash
terraform graph
```

The output uses DOT graph syntax.

The important idea is not the formatting itself, but that Terraform internally builds a directed dependency graph to determine safe resource creation and destruction order.

---

# 27. Terraform and AWS Knowledge

Terraform felt relatively straightforward because the underlying AWS architecture was already understood.

Example:

Manually:

```text
Create VPC
Create subnet
Create IGW
Create route table
Add route
Associate subnet
```

Terraform:

```hcl
resource "aws_vpc" ...

resource "aws_subnet" ...

resource "aws_internet_gateway" ...

resource "aws_route_table" ...

resource "aws_route" ...

resource "aws_route_table_association" ...
```

Terraform does not replace infrastructure knowledge.

It encodes infrastructure knowledge.

---

# 28. Why Terraform Becomes More Powerful Later

The deeper Terraform concepts include:

```text
remote state
state locking
modules
for_each
count
lifecycle
import
moved blocks
resource refactoring
workspaces
provider aliases
CI/CD
policy enforcement
drift management
```

These concepts become more important once infrastructure grows beyond a small lab.

---

# 29. Important Files

```text
main.tf
```

Defines providers and resources.

```text
variables.tf
```

Defines configurable inputs.

```text
outputs.tf
```

Defines values exposed after apply.

```text
terraform.tfstate
```

Tracks Terraform-managed infrastructure.

```text
.terraform.lock.hcl
```

Locks provider dependency versions/checksums.

```text
.terraform/
```

Stores downloaded providers and local Terraform initialization data.

```text
tfplan
```

Binary saved execution plan.

---

# 30. Important Commands

Initialize:

```bash
terraform init
```

Format:

```bash
terraform fmt
```

Validate:

```bash
terraform validate
```

Preview changes:

```bash
terraform plan
```

Save plan:

```bash
terraform plan -out=tfplan
```

Apply saved plan:

```bash
terraform apply tfplan
```

Inspect outputs:

```bash
terraform output
```

List state:

```bash
terraform state list
```

Inspect resource state:

```bash
terraform state show aws_vpc.day6_vpc
```

Display dependency graph:

```bash
terraform graph
```

Check for drift:

```bash
terraform plan
```

---

# 31. Current Managed Infrastructure

Terraform currently manages approximately:

```text
aws_vpc.day6_vpc

aws_subnet.public_a

aws_internet_gateway.day6_igw

aws_route_table.public

aws_route.public_internet

aws_route_table_association.public_a
```

---

# 32. Core Mental Model

The most important model from this lab:

```text
Code
 |
 v
Desired Infrastructure

Terraform State
 |
 v
Mapping between code and infrastructure

AWS
 |
 v
Actual Infrastructure

terraform plan
 |
 v
Compare desired state with real state

terraform apply
 |
 v
Reconcile infrastructure
```

---

# 33. Key Takeaways

- Terraform is declarative Infrastructure as Code.
- AWS knowledge makes Terraform much easier to understand.
- Terraform resources map directly to real AWS resources.
- Terraform state tracks the relationship between code and infrastructure.
- Terraform can detect configuration drift.
- Terraform can restore manually modified resources to their desired configuration.
- Resource references create implicit dependencies.
- Terraform uses a dependency graph rather than blindly following file order.
- Independent resources can be created in parallel.
- `depends_on` should be used only when Terraform cannot infer a real dependency.
- Variables separate configuration from infrastructure logic.
- Outputs expose useful infrastructure values.
- A reviewed saved plan provides a safer apply workflow.
- Terraform configuration should be treated as the desired source of truth.

---

# Terraform Block Status

```text
COMPLETED - Fundamentals
```

Topics covered:

```text
Installation
Provider
Resource
Init
Plan
Apply
Saved Plans
State
State Inspection
Outputs
Variables
Drift Detection
Reconciliation
Resource References
Implicit Dependencies
Dependency Graph
Execution Order
AWS Infrastructure as Code
```
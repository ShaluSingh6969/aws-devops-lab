# Terraform Multi-Subnet Patterns

## Goal

Build reusable AWS infrastructure with Terraform using:

- `for_each`
- map/object variables
- stable resource identities
- `locals`
- `merge()`
- `count`
- `count` vs `for_each`

---

# 1. Multi-Subnet Input

Instead of declaring every subnet separately, subnet configuration was stored in a map:

```hcl
variable "public_subnets" {
  type = map(object({
    cidr = string
    az   = string
  }))

  default = {
    public_a = {
      cidr = "10.60.1.0/24"
      az   = "eu-central-1a"
    }

    public_b = {
      cidr = "10.60.2.0/24"
      az   = "eu-central-1b"
    }
  }
}
```

Structure:

```text
public_subnets
├── public_a
│   ├── cidr
│   └── az
└── public_b
    ├── cidr
    └── az
```

---

# 2. for_each

Subnets were created with:

```hcl
resource "aws_subnet" "public" {
  for_each = var.public_subnets

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.environment}-${each.key}"
    Environment = var.environment
  }
}
```

Important expressions:

```hcl
each.key
each.value.cidr
each.value.az
```

Terraform resource addresses became:

```text
aws_subnet.public["public_a"]
aws_subnet.public["public_b"]
```

The resource identity is based on the map key.

---

# 3. Stable Resource Identity

A third subnet was added:

```hcl
public_c = {
  cidr = "10.60.3.0/24"
  az   = "eu-central-1c"
}
```

Terraform planned only:

```text
aws_subnet.public["public_c"] will be created
```

Existing resources were untouched.

Later, `public_b` was removed.

Terraform removed only:

```text
aws_subnet.public["public_b"]
```

while:

```text
aws_subnet.public["public_a"]
aws_subnet.public["public_c"]
```

remained unchanged.

This demonstrates the main advantage of `for_each`:

```text
resource identity = stable key
```

---

# 4. locals

Shared tags were moved into a local value:

```hcl
locals {
  common_tags = {
    Environment = var.environment
    Project     = "terraform-multi-subnet-lab"
    ManagedBy   = "Terraform"
  }
}
```

A `local` is an internal reusable or derived value.

Mental model:

```text
var.*
→ external input

local.*
→ internal reusable logic

output.*
→ exposed result
```

---

# 5. merge()

Shared tags were combined with resource-specific tags:

```hcl
tags = merge(
  local.common_tags,
  {
    Name = "${var.environment}-${each.key}"
  }
)
```

This produced tags such as:

```text
Environment = dev
Project     = terraform-multi-subnet-lab
ManagedBy   = Terraform
Name        = dev-public_a
```

Adding the new shared tags caused only:

```text
~ update in-place
```

No resources were replaced.

---

# 6. count

A simple `count` example was added:

```hcl
resource "aws_subnet" "count_demo" {
  count = 3

  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.60.${10 + count.index}.0/24"
  availability_zone = "eu-central-1b"
}
```

Terraform addresses were:

```text
aws_subnet.count_demo[0]
aws_subnet.count_demo[1]
aws_subnet.count_demo[2]
```

With `count`, resource identity is based on numeric index.

---

# 7. count with a List

A list-based configuration was used:

```hcl
variable "count_subnets" {
  type = list(string)

  default = [
    "10.60.10.0/24",
    "10.60.11.0/24",
    "10.60.12.0/24"
  ]
}
```

Resource:

```hcl
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
```

---

# 8. count Index Shift Problem

Initial mapping:

```text
[0] -> 10.60.10.0/24
[1] -> 10.60.11.0/24
[2] -> 10.60.12.0/24
```

The middle item was removed:

```text
10.60.11.0/24
```

New list:

```text
[0] -> 10.60.10.0/24
[1] -> 10.60.12.0/24
```

Terraform then planned:

```text
aws_subnet.count_demo[1] must be replaced
aws_subnet.count_demo[2] will be destroyed
```

This happened because Terraform tracks `count` resources by index.

The desired logical action was:

```text
remove only 10.60.11.0/24
```

but Terraform saw:

```text
[1] changed
[2] disappeared
```

This is the main weakness of list-based `count`.

---

# 9. count vs for_each

## count

```text
aws_subnet.example[0]
aws_subnet.example[1]
aws_subnet.example[2]
```

Best suited for:

```text
simple interchangeable resources
fixed-number replicas
resources where numeric identity is acceptable
```

## for_each

```text
aws_subnet.example["public_a"]
aws_subnet.example["public_b"]
aws_subnet.example["public_c"]
```

Best suited for:

```text
subnets
security groups
route tables
IAM roles
DNS records
named infrastructure objects
```

Rule of thumb:

```text
count
→ identity based on position

for_each
→ identity based on stable key
```

For most named infrastructure resources, `for_each` is easier and safer to maintain.

---

# 10. Important Commands

```bash
terraform init
terraform fmt
terraform validate
terraform plan
terraform plan -out=tfplan
terraform apply tfplan
terraform state list
```

---

# Key Takeaways

- `for_each` creates one resource instance per map/set element.
- Map keys become part of Terraform resource identity.
- Stable keys reduce unnecessary resource churn.
- `locals` reduce duplication.
- `merge()` combines maps such as shared and resource-specific tags.
- `count` creates resources using numeric indexes.
- Adding items at the end with `count` is usually fine.
- Removing an item from the middle of a list can shift indexes.
- Index shifts can cause unnecessary replacement/destruction.
- Prefer `for_each` when infrastructure objects have meaningful names.

---

# Production-Style VPC Networking

The next step extended the Terraform lab from basic subnet iteration into a more realistic two-AZ AWS network.

## Target Architecture

```text
VPC 10.60.0.0/16
│
├── Public Subnet A - eu-central-1a
│   └── Public Route Table
│
├── Public Subnet B - eu-central-1b
│   └── Public Route Table
│
├── Private Subnet A - eu-central-1a
│   └── Private Route Table
│
└── Private Subnet B - eu-central-1b
    └── Private Route Table
```

The public route table contains:

```text
10.60.0.0/16 -> local
0.0.0.0/0    -> Internet Gateway
```

The private route table currently contains only:

```text
10.60.0.0/16 -> local
```

No NAT Gateway was added yet, so the private subnets currently have no Internet route.

---

# Unified Subnet Configuration

Instead of maintaining separate resource definitions for public and private subnets, one map describes all subnet properties.

```hcl
variable "subnets" {
  type = map(object({
    cidr   = string
    az     = string
    public = bool
  }))

  default = {
    public_a = {
      cidr   = "10.60.1.0/24"
      az     = "eu-central-1a"
      public = true
    }

    public_b = {
      cidr   = "10.60.2.0/24"
      az     = "eu-central-1b"
      public = true
    }

    private_a = {
      cidr   = "10.60.11.0/24"
      az     = "eu-central-1a"
      public = false
    }

    private_b = {
      cidr   = "10.60.12.0/24"
      az     = "eu-central-1b"
      public = false
    }
  }
}
```

The subnet resource uses the map directly:

```hcl
resource "aws_subnet" "this" {
  for_each = var.subnets

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = each.value.public

  tags = merge(
    local.common_tags,
    {
      Name = "${var.environment}-${each.key}"
      Type = each.value.public ? "public" : "private"
    }
  )
}
```

This creates stable Terraform addresses:

```text
aws_subnet.this["public_a"]
aws_subnet.this["public_b"]
aws_subnet.this["private_a"]
aws_subnet.this["private_b"]
```

---

# Important: Tags Do Not Make a Subnet Public or Private

A tag such as:

```text
Type = private
```

is only metadata.

Actual network behavior depends on configuration such as:

```text
route tables
Internet Gateway routes
public IP assignment
NAT routes
```

During the lab, the private subnets accidentally had:

```hcl
map_public_ip_on_launch = true
```

Terraform plan exposed the problem.

It was corrected to:

```hcl
map_public_ip_on_launch = each.value.public
```

which evaluates to:

```text
public_a  -> true
public_b  -> true

private_a -> false
private_b -> false
```

This was a useful example of why `terraform plan` should always be reviewed before applying.

---

# Refactoring Resources with moved Blocks

The subnet Terraform resource was renamed from:

```text
aws_subnet.public
```

to:

```text
aws_subnet.this
```

Without additional information, Terraform interpreted this as:

```text
old resources removed
+
new resources created
```

and proposed destroying and recreating all four subnets.

To preserve the existing AWS resources, a `moved` block was added:

```hcl
moved {
  from = aws_subnet.public
  to   = aws_subnet.this
}
```

Terraform then understood that this was only a configuration refactor.

Instead of destroying the subnets, Terraform changed their state addresses:

```text
aws_subnet.public["public_a"]
        ↓
aws_subnet.this["public_a"]
```

while keeping the same real AWS subnet.

## Key Lesson

Terraform tracks a resource primarily through its **Terraform address**.

Renaming a resource in code can therefore look like deletion + creation unless Terraform is explicitly told about the move.

Use `moved` blocks when refactoring resource addresses that should continue representing the same infrastructure.

---

# Internet Gateway

The VPC contains an Internet Gateway:

```hcl
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}
```

The Internet Gateway is attached to the VPC, not directly to a subnet.

Whether a subnet can use the Internet Gateway depends on its effective route table.

---

# Public Route Table

```hcl
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
}
```

Internet route:

```hcl
resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}
```

This means:

```text
destination not inside VPC
        ↓
0.0.0.0/0
        ↓
Internet Gateway
```

---

# Filtering Maps with for Expressions

Only public subnets should be associated with the public route table.

Terraform filters the subnet map:

```hcl
resource "aws_route_table_association" "public" {
  for_each = {
    for key, subnet in var.subnets :
    key => subnet
    if subnet.public
  }

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.public.id
}
```

This produces only:

```text
public_a
public_b
```

and therefore:

```text
aws_route_table_association.public["public_a"]
aws_route_table_association.public["public_b"]
```

The expression:

```hcl
if subnet.public
```

acts as a filter.

---

# Private Route Table

The private route table:

```hcl
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
}
```

Private subnet associations use the opposite filter:

```hcl
resource "aws_route_table_association" "private" {
  for_each = {
    for key, subnet in var.subnets :
    key => subnet
    if !subnet.public
  }

  subnet_id      = aws_subnet.this[each.key].id
  route_table_id = aws_route_table.private.id
}
```

This produces:

```text
private_a
private_b
```

The private route table intentionally has no:

```text
0.0.0.0/0
```

route yet.

Therefore the private subnets can communicate with resources inside the VPC through the local route, but currently have no Internet path.

---

# Route Table Verification

The deployed configuration was verified directly with AWS CLI:

```bash
aws ec2 describe-route-tables \
  --filters Name=vpc-id,Values=<VPC_ID> \
  --query 'RouteTables[*].{RouteTableId:RouteTableId,Associations:Associations[*].SubnetId,Routes:Routes[*].[DestinationCidrBlock,GatewayId]}' \
  --output json
```

The public route table showed:

```text
Associations:
- public_a
- public_b

Routes:
10.60.0.0/16 -> local
0.0.0.0/0    -> IGW
```

The private route table showed:

```text
Associations:
- private_a
- private_b

Routes:
10.60.0.0/16 -> local
```

This confirmed that Terraform configuration matched the intended AWS architecture.

---

# Main Route Table

AWS automatically creates a main route table when a VPC is created.

It contained:

```text
10.60.0.0/16 -> local
```

and showed no explicit subnet associations.

All four subnets had explicit associations:

```text
public_a  -> public route table
public_b  -> public route table

private_a -> private route table
private_b -> private route table
```

A subnet without an explicit route-table association would use the VPC's main route table.

---

# What Makes a Subnet Public?

A subnet is not public because:

```text
its name contains "public"
or
its tag says Type=public
```

The important network property is its effective routing.

For IPv4 Internet connectivity, an instance typically needs:

```text
Subnet route:
0.0.0.0/0 -> Internet Gateway

AND

a public IPv4 address / Elastic IP
```

Our public subnets have the IGW route and:

```hcl
map_public_ip_on_launch = true
```

Private subnets have:

```hcl
map_public_ip_on_launch = false
```

and no Internet Gateway default route.

---

# Terraform Plan Review Lesson

An initial refactor produced:

```text
Plan: 11 to add, 0 to change, 4 to destroy
```

This was a warning sign because the existing subnets should not have needed replacement.

After using a `moved` block and correcting the private subnet public-IP setting, the plan became:

```text
Plan: 7 to add, 2 to change, 0 to destroy
```

The two changes were:

```text
private_a:
map_public_ip_on_launch true -> false

private_b:
map_public_ip_on_launch true -> false
```

No existing subnet was destroyed.

## Operational Lesson

Never treat:

```bash
terraform apply
```

as the first step.

The normal workflow should be:

```text
change configuration
        ↓
terraform fmt
        ↓
terraform validate
        ↓
terraform plan
        ↓
understand every create/change/destroy
        ↓
apply
```

Unexpected destruction in a plan should be investigated before applying.

---

# Current Network Mental Model

```text
                        Internet
                           |
                           v
                    Internet Gateway
                           |
                    Public Route Table
                     /             \
                    v               v
              Public A          Public B
               AZ-A              AZ-B


                VPC local routing
                     |
             -------------------
             |                 |
             v                 v
         Private A         Private B
             \                 /
              \               /
               Private Route Table
                local route only
```

A future step can add controlled outbound access for private subnets using a NAT Gateway.

---

# New Terraform Concepts Covered

```text
map(object(...))
for_each
conditional expressions
for expressions
map filtering
locals
merge()
moved blocks
resource-address refactoring
route-table associations
public/private subnet modeling
plan review
AWS-side verification
```

---

# Key Takeaways

- Terraform resource addresses are important parts of resource identity.
- Renaming a Terraform resource can look like destroy + recreate.
- `moved` blocks allow safe refactoring without recreating infrastructure.
- `terraform plan` is a safety mechanism, not just a preview.
- Tags describe resources but do not control network behavior.
- `for` expressions can filter maps for targeted resource creation.
- Public and private subnets can be modeled from one reusable data structure.
- A public subnet needs an effective route to an Internet Gateway.
- Private subnets should not automatically assign public IPs.
- Route-table associations determine which routing policy a subnet uses.
- AWS creates a main route table automatically for every VPC.
- Terraform configuration should always be validated against the actual AWS infrastructure.
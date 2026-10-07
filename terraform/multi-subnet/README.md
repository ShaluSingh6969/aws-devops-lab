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
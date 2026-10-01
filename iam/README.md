# AWS IAM Lab

Hands-on lab covering IAM users, policies, roles, STS temporary credentials, EC2 service roles, and instance profiles.

## Concepts Covered

- IAM users
- AWS managed and customer managed policies
- Implicit Deny
- Explicit Deny
- IAM roles
- Trust policies
- Permission policies
- AWS STS
- Temporary credentials
- AWS CLI profiles
- EC2 service roles
- Instance profiles
- EC2 Instance Metadata Service (IMDSv2)

---

# 1. Verify Current AWS Identity

The following command shows which AWS identity the CLI is currently using.

```bash
aws sts get-caller-identity
```

Example identity:

```text
arn:aws:iam::<ACCOUNT-ID>:user/shalu-admin
```

This command is useful when troubleshooting:

- Which account am I using?
- Which IAM user am I using?
- Am I currently using an assumed role?

---

# 2. Inspect AWS CLI Configuration

```bash
aws configure list
```

AWS CLI configuration is normally stored under:

```text
~/.aws/config
~/.aws/credentials
```

Inspect configuration:

```bash
cat ~/.aws/config
```

List configured profile names without exposing credentials:

```bash
grep '^\[' ~/.aws/credentials
```

> Never commit `~/.aws/credentials`, access keys, or secret keys to Git.

---

# 3. Inspect IAM User

```bash
aws iam get-user
```

List policies attached to the user:

```bash
aws iam list-attached-user-policies \
  --user-name shalu-admin
```

The lab administrator user currently uses:

```text
AdministratorAccess
```

which contains effectively:

```json
{
  "Effect": "Allow",
  "Action": "*",
  "Resource": "*"
}
```

This is convenient for an isolated learning account but is too permissive for most production workloads.

---

# 4. IAM Authorization Model

A useful mental model:

```text
Authentication
= Who are you?

Authorization
= What are you allowed to do?
```

Access keys authenticate an IAM user.

IAM policies determine what that identity can do.

```text
Access Key
≠ Permission
```

---

# 5. Least-Privilege IAM User Lab

Created a lab user:

```bash
aws iam create-user \
  --user-name iam-lab-user
```

The user was given only permission to list S3 buckets.

Policy file:

```text
iam/read-only-s3-policy.json
```

Policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListAllMyBuckets"
      ],
      "Resource": "*"
    }
  ]
}
```

Create the policy:

```bash
aws iam create-policy \
  --policy-name IamLabS3ListOnly \
  --policy-document file://iam/read-only-s3-policy.json
```

Attach it:

```bash
aws iam attach-user-policy \
  --user-name iam-lab-user \
  --policy-arn arn:aws:iam::<ACCOUNT-ID>:policy/IamLabS3ListOnly
```

---

# 6. Separate AWS CLI Profile

An access key was created for `iam-lab-user`.

```bash
aws iam create-access-key \
  --user-name iam-lab-user
```

The credentials were configured under a separate profile:

```bash
aws configure --profile iam-lab
```

Verify:

```bash
aws sts get-caller-identity \
  --profile iam-lab
```

---

# 7. Implicit Deny Lab

The following command succeeded:

```bash
aws s3 ls \
  --profile iam-lab
```

No output was returned because no buckets existed.

The following command failed:

```bash
aws ec2 describe-instances \
  --region eu-central-1 \
  --profile iam-lab
```

Error:

```text
UnauthorizedOperation

...is not authorized to perform:
ec2:DescribeInstances

because no identity-based policy allows
the ec2:DescribeInstances action
```

Reason:

```text
iam-lab-user
        ↓
policy allows only
s3:ListAllMyBuckets
        ↓
request:
ec2:DescribeInstances
        ↓
no matching Allow
        ↓
Implicit Deny
```

Important IAM rule:

```text
No Allow
= Deny
```

---

# 8. Explicit Deny Lab

Policy file:

```text
iam/deny-s3-list-policy.json
```

Policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Deny",
      "Action": "s3:ListAllMyBuckets",
      "Resource": "*"
    }
  ]
}
```

After attaching both an Allow and an Explicit Deny:

```text
Allow
+
Explicit Deny
=
Deny
```

IAM evaluation rule:

```text
Explicit Deny
    ↓
wins over Allow

Explicit Allow
    ↓
allows action

No applicable Allow
    ↓
Implicit Deny
```

---

# 9. IAM Role and STS Lab

Created:

```text
iam-lab-role
```

The role can be assumed by:

```text
iam-lab-user
```

Trust policy file:

```text
iam/trust-policy.json
```

Conceptually:

```json
{
  "Principal": {
    "AWS": "arn:aws:iam::<ACCOUNT-ID>:user/iam-lab-user"
  },
  "Action": "sts:AssumeRole"
}
```

Create role:

```bash
aws iam create-role \
  --role-name iam-lab-role \
  --assume-role-policy-document file://iam/trust-policy.json
```

The role was given EC2 read-only permissions:

```bash
aws iam attach-role-policy \
  --role-name iam-lab-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess
```

---

# 10. Allow User to Assume Role

Policy file:

```text
iam/allow-assume-role.json
```

It allows:

```text
sts:AssumeRole
```

on:

```text
iam-lab-role
```

Attach to user:

```bash
aws iam attach-user-policy \
  --user-name iam-lab-user \
  --policy-arn arn:aws:iam::<ACCOUNT-ID>:policy/IamLabAssumeRole
```

The role was then assumed using:

```bash
aws sts assume-role \
  --role-arn arn:aws:iam::<ACCOUNT-ID>:role/iam-lab-role \
  --role-session-name lab-session \
  --profile iam-lab
```

STS returned temporary:

```text
AccessKeyId
SecretAccessKey
SessionToken
Expiration
```

These credentials automatically expire.

---

# 11. Trust Policy vs Permission Policy

Two separate authorization checks exist.

```text
Gate 1

Can this principal assume the role?

→ Trust Policy
→ sts:AssumeRole
```

Then:

```text
Gate 2

What can the role do after assumption?

→ Role Permission Policies
```

Mental model:

```text
Trust Policy
= WHO can assume the role

Permission Policy
= WHAT the role can do
```

---

# 12. AWS CLI Role Profile

Instead of manually copying STS credentials, a role profile was configured.

```bash
aws configure set role_arn \
  arn:aws:iam::<ACCOUNT-ID>:role/iam-lab-role \
  --profile iam-lab-role
```

```bash
aws configure set source_profile iam-lab \
  --profile iam-lab-role
```

```bash
aws configure set region eu-central-1 \
  --profile iam-lab-role
```

Verify:

```bash
aws sts get-caller-identity \
  --profile iam-lab-role
```

Expected identity:

```text
arn:aws:sts::<ACCOUNT-ID>:assumed-role/iam-lab-role/...
```

---

# 13. IAM User vs IAM Role

```text
IAM User
= long-lived AWS identity
= can have long-lived access keys

IAM Role
= assumed identity
= uses temporary credentials

STS
= issues temporary credentials
```

A limited IAM user can temporarily gain different permissions by assuming a role.

Example:

```text
iam-lab-user
→ can only list S3 buckets

iam-lab-user
→ assumes iam-lab-role

iam-lab-role
→ EC2 ReadOnly

temporary role session
→ can read EC2 information
```

The user does not permanently inherit the role permissions.

---

# 14. EC2 Service Role

Created:

```text
ec2-lab-role
```

Trust policy:

```text
iam/ec2-trust-policy.json
```

Important trust principal:

```json
"Principal": {
  "Service": "ec2.amazonaws.com"
}
```

This allows the EC2 service to use the role.

Attached permission:

```bash
aws iam attach-role-policy \
  --role-name ec2-lab-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
```

---

# 15. EC2 Instance Profile

Created:

```text
ec2-lab-profile
```

```bash
aws iam create-instance-profile \
  --instance-profile-name ec2-lab-profile
```

Attached the role:

```bash
aws iam add-role-to-instance-profile \
  --instance-profile-name ec2-lab-profile \
  --role-name ec2-lab-role
```

Architecture:

```text
EC2
 ↓
ec2-lab-profile
 ↓
ec2-lab-role
 ↓
AmazonS3ReadOnlyAccess
```

An instance profile is the mechanism used to expose an IAM role to EC2.

---

# 16. EC2 Temporary Credentials

After attaching the instance profile to an EC2 instance:

```bash
aws sts get-caller-identity
```

returned an assumed-role identity.

No static credentials were configured on EC2.

Architecture:

```text
EC2
 ↓
Instance Profile
 ↓
IAM Role
 ↓
STS temporary credentials
 ↓
AWS CLI / SDK
```

---

# 17. EC2 Instance Metadata Service (IMDSv2)

Get an IMDSv2 token:

```bash
TOKEN=$(curl -sS -X PUT \
  "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
```

Find attached role:

```bash
curl -sS \
  -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/iam/security-credentials/
```

Query role credentials:

```bash
curl -sS \
  -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/iam/security-credentials/ec2-lab-role
```

The response contains temporary credentials.

**Never copy these credentials into Git or documentation.**

Get instance private IP:

```bash
curl -sS \
  -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/local-ipv4
```

Get instance ID:

```bash
curl -sS \
  -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id
```

---

# Key Takeaways

```text
IAM User
→ long-lived identity

Policy
→ defines permissions

IAM Role
→ temporary assumed identity

Trust Policy
→ who can assume the role

Permission Policy
→ what the role can do

STS
→ temporary credentials

Instance Profile
→ exposes role to EC2

IMDS
→ exposes instance metadata and temporary role credentials
```
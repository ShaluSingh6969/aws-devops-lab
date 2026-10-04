# EC2 IAM Role, S3 Least Privilege & S3 Gateway VPC Endpoint

## Goal

Build a small AWS lab that demonstrates how an EC2 instance accesses Amazon S3 securely using an IAM role, tests IAM authorization behavior with controlled failures, and then routes S3 traffic through an S3 Gateway VPC Endpoint instead of the Internet Gateway.

This lab focuses on four core ideas:

- EC2 should use an **IAM role with temporary credentials**, not static access keys.
- IAM authorization depends on **Action + Resource + Effect**.
- **Explicit Deny overrides Allow**.
- An **S3 Gateway VPC Endpoint** is route-table based and is different from an Interface VPC Endpoint.

---

## Architecture

Initial path:

```text
WSL / local machine
      |
      | AWS CLI + IAM user credentials
      v
AWS APIs

EC2 instance
      |
      | Instance Profile
      v
IAM Role: ec2-s3-lab-role
      |
      | Temporary STS credentials via IMDS
      v
Amazon S3
```

Before adding the S3 Gateway Endpoint:

```text
EC2
 |
 v
Subnet/VPC router
 |
 v
0.0.0.0/0 -> Internet Gateway
 |
 v
S3 public regional endpoint
```

After adding the S3 Gateway Endpoint:

```text
EC2
 |
 v
Subnet/VPC router
 |
 v
S3 managed prefix list -> S3 Gateway Endpoint
 |
 v
Amazon S3
```

The EC2 instance still had a general Internet Gateway route for SSH, but S3 traffic matched the more specific S3 prefix-list route.

---

## Resources Created

### IAM

- Role: `ec2-s3-lab-role`
- Instance profile: `ec2-s3-lab-profile`
- Customer-managed policy: `EC2S3LabPolicy`

### S3

- Bucket: `shalu-devops-lab-20261004`

### Networking

- VPC: `10.30.0.0/16`
- Public subnet: `10.30.1.0/24`
- Internet Gateway
- Public route table
- EC2 Security Group
- S3 Gateway VPC Endpoint

### EC2

- Amazon Linux 2023
- Instance type: `t3.micro`
- Public IP enabled for SSH access during the lab
- IAM instance profile: `ec2-s3-lab-profile`

---

# Part 1 — S3 Bucket

Create the bucket:

```bash
BUCKET_NAME=shalu-devops-lab-20261004

aws s3api create-bucket \
  --bucket "$BUCKET_NAME" \
  --region eu-central-1 \
  --create-bucket-configuration LocationConstraint=eu-central-1
```

Verify:

```bash
aws s3api head-bucket --bucket "$BUCKET_NAME"
aws s3 ls
```

---

# Part 2 — Bucket ARN vs Object ARN

S3 permissions use different ARNs depending on whether the action applies to the bucket itself or to objects inside the bucket.

### Bucket ARN

```text
arn:aws:s3:::shalu-devops-lab-20261004
```

Used for actions such as:

```text
s3:ListBucket
```

### Object ARN

```text
arn:aws:s3:::shalu-devops-lab-20261004/*
```

Used for actions such as:

```text
s3:GetObject
s3:PutObject
```

This distinction matters because an action can be correct while the `Resource` is wrong, which still results in `AccessDenied`.

---

# Part 3 — Least-Privilege S3 Policy

Policy file:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::shalu-devops-lab-20261004"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::shalu-devops-lab-20261004/*"
    }
  ]
}
```

Create the customer-managed policy:

```bash
aws iam create-policy \
  --policy-name EC2S3LabPolicy \
  --policy-document file://iam/ec2-s3-lab-policy.json
```

---

# Part 4 — EC2 Trust Policy

Trust policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

Create the role:

```bash
aws iam create-role \
  --role-name ec2-s3-lab-role \
  --assume-role-policy-document file://iam/ec2-s3-trust-policy.json
```

Attach the S3 permission policy:

```bash
aws iam attach-role-policy \
  --role-name ec2-s3-lab-role \
  --policy-arn arn:aws:iam::<ACCOUNT_ID>:policy/EC2S3LabPolicy
```

---

# Part 5 — Instance Profile

Create the instance profile:

```bash
aws iam create-instance-profile \
  --instance-profile-name ec2-s3-lab-profile
```

Add the role:

```bash
aws iam add-role-to-instance-profile \
  --instance-profile-name ec2-s3-lab-profile \
  --role-name ec2-s3-lab-role
```

Mental model:

```text
EC2
 -> Instance Profile
 -> IAM Role
 -> Permission Policies
```

The instance profile is the wrapper used by EC2 to attach the IAM role.

---

# Part 6 — Verify EC2 Role Credentials

Inside the EC2 instance:

```bash
aws configure list
```

Observed:

```text
access_key : ************.... : iam-role
secret_key : ************.... : iam-role
region     : eu-central-1    : imds
```

The key point is:

```text
TYPE = iam-role
```

The access key and secret key shown here are **temporary role credentials**, not manually created long-lived credentials.

They are issued by AWS STS and delivered to the instance through the EC2 Instance Metadata Service (IMDS).

Verify identity:

```bash
aws sts get-caller-identity
```

Expected form:

```text
arn:aws:sts::<ACCOUNT_ID>:assumed-role/ec2-s3-lab-role/<INSTANCE_ID>
```

This proves the EC2 is operating as an **assumed role session**.

---

# Part 7 — Test S3 Access

List the bucket:

```bash
aws s3 ls s3://shalu-devops-lab-20261004
```

If the bucket is empty, no output is expected. The important point is that there is no `AccessDenied` error.

Create and upload an object:

```bash
echo "hello from ec2 role" > test.txt

aws s3 cp test.txt \
  s3://shalu-devops-lab-20261004/
```

List objects:

```bash
aws s3 ls s3://shalu-devops-lab-20261004
```

Download it:

```bash
aws s3 cp \
  s3://shalu-devops-lab-20261004/test.txt \
  downloaded.txt

cat downloaded.txt
```

This proves:

```text
ListBucket -> works
PutObject  -> works
GetObject  -> works
```

---

# Part 8 — Controlled IAM Failure: Implicit Deny

Remove `s3:PutObject` from the policy while keeping:

```text
s3:ListBucket
s3:GetObject
```

Create a new customer-managed policy version:

```bash
aws iam create-policy-version \
  --policy-arn arn:aws:iam::<ACCOUNT_ID>:policy/EC2S3LabPolicy \
  --policy-document file://iam/ec2-s3-lab-policy.json \
  --set-as-default
```

Test upload again:

```bash
echo "this upload should fail" > blocked.txt

aws s3 cp blocked.txt \
  s3://shalu-devops-lab-20261004/
```

Result:

```text
AccessDenied calling PutObject
```

Reason:

```text
There is no Allow for s3:PutObject
-> implicit deny
```

Important lesson:

```text
Authenticated != authorized for every action
```

---

# Part 9 — Controlled IAM Failure: Explicit Deny

Add an explicit deny for `s3:GetObject` while also keeping an Allow for the same action:

```json
{
  "Effect": "Deny",
  "Action": "s3:GetObject",
  "Resource": "arn:aws:s3:::shalu-devops-lab-20261004/*"
}
```

Create another policy version and make it default.

Using high-level CLI:

```bash
aws s3 cp \
  s3://shalu-devops-lab-20261004/test.txt \
  denied-download.txt
```

Observed error:

```text
403 Forbidden when calling HeadObject
```

The high-level `aws s3 cp` command may call `HeadObject` before downloading an object.

For a clearer API-level test:

```bash
aws s3api get-object \
  --bucket shalu-devops-lab-20261004 \
  --key test.txt \
  denied-download.txt
```

This produced a more direct `AccessDenied` response.

IAM rule proven:

```text
Allow + Explicit Deny
= Deny
```

---

# Part 10 — IAM Policy Evaluation Mental Model

Useful simplified model:

```text
Principal
+
Action
+
Resource
+
Effect
```

All must line up correctly.

Examples:

```text
No matching Allow
-> implicit deny

Matching Allow + matching explicit Deny
-> explicit deny wins

Correct Action + wrong Resource ARN
-> denied
```

---

# Part 11 — Customer-Managed Policy Versions

A customer-managed IAM policy can have up to **5 versions**.

Every new test policy was created using:

```bash
aws iam create-policy-version \
  --policy-arn <POLICY_ARN> \
  --policy-document file://<FILE> \
  --set-as-default
```

Only one version can be the default at a time.

List versions:

```bash
aws iam list-policy-versions \
  --policy-arn arn:aws:iam::<ACCOUNT_ID>:policy/EC2S3LabPolicy
```

---

# Part 12 — Human IAM User vs EC2 Role

A human IAM user can receive a permission policy directly:

```text
IAM User
 -> Permission Policy
 -> AWS API
```

or assume a role:

```text
IAM User
 -> sts:AssumeRole
 -> IAM Role
 -> Permission Policy
 -> AWS API
```

For EC2, the standard pattern is:

```text
EC2
 -> Instance Profile
 -> IAM Role
 -> temporary STS credentials
```

EC2 should not be configured with long-lived IAM user access keys.

---

# Part 13 — Session Manager Access Clarification

From the previous SSM lab, a useful architecture distinction was clarified.

A local WSL machine did **not** connect directly to the private Interface VPC Endpoint.

Instead:

```text
WSL
 -> Internet
 -> AWS Systems Manager service

Private EC2 SSM Agent
 -> Interface VPC Endpoint
 -> AWS Systems Manager service
```

AWS Systems Manager is the intermediary.

The endpoint Security Group allowed TCP/443 from the EC2 Security Group, not from `0.0.0.0/0`.

For a non-admin human user to start a Session Manager session, they need appropriate IAM permissions such as `ssm:StartSession` for the permitted instances/documents. The EC2 side separately needs its own SSM role permissions.

So a working Session Manager session requires:

```text
Human authorization
+
Instance authorization
+
Network path to SSM
```

---

# Part 14 — Interface Endpoint vs Gateway Endpoint

## Interface VPC Endpoint

```text
Creates ENIs
Gets private IP addresses
Placed in selected subnets
Uses Security Groups
Uses AWS PrivateLink
```

Example from previous lab:

```text
SSM / SSMMessages Interface Endpoints
```

## Gateway VPC Endpoint

```text
No ENI
No endpoint private IP
No endpoint Security Group
Associated with route tables
Uses AWS-managed service prefix lists
```

Typical supported services include Amazon S3 and DynamoDB.

For this lab we used an **S3 Gateway VPC Endpoint**.

---

# Part 15 — Create the S3 Gateway VPC Endpoint

```bash
S3_ENDPOINT_ID=$(aws ec2 create-vpc-endpoint \
  --vpc-id "$VPC_ID" \
  --service-name com.amazonaws.eu-central-1.s3 \
  --vpc-endpoint-type Gateway \
  --route-table-ids "$PUBLIC_RT_ID" \
  --tag-specifications \
    'ResourceType=vpc-endpoint,Tags=[{Key=Name,Value=s3-lab-gateway-endpoint}]' \
  --query 'VpcEndpoint.VpcEndpointId' \
  --output text)

echo "$S3_ENDPOINT_ID"
```

Notice what was **not** specified:

```text
No subnet argument
No Security Group
No private endpoint IP
No ENI
```

Instead, the endpoint was associated with a **route table**.

---

# Part 16 — Inspect Route Table

```bash
aws ec2 describe-route-tables \
  --route-table-ids "$PUBLIC_RT_ID" \
  --query 'RouteTables[0].Routes'
```

Observed routes:

```text
10.30.0.0/16 -> local
0.0.0.0/0    -> Internet Gateway
pl-6ea54007   -> vpce-035088fc1c0b79a3c
```

The `pl-...` entry is an **AWS-managed prefix list** representing the regional S3 IP ranges.

Conceptually:

```text
Destination matches S3 prefix list
-> use S3 Gateway Endpoint

Otherwise
-> normal route evaluation continues
```

The S3 route is more specific than `0.0.0.0/0`, so S3 traffic uses the Gateway Endpoint.

---

# Part 17 — Guest OS Routing vs AWS VPC Routing

Inside the EC2 instance, Linux typically sees something like:

```text
default via 10.30.1.1 dev eth0
```

The EC2 operating system does not know directly about:

```text
igw-...
vpce-...
pl-...
```

Its job is simply:

```text
send non-local traffic to the subnet/VPC router
```

Then AWS evaluates the VPC route table associated with the subnet.

Mental model:

```text
EC2 guest routing table
        |
        v
Subnet/VPC router
        |
        v
Subnet-associated VPC route table
        |
        +--> local
        +--> Internet Gateway
        +--> S3 Gateway Endpoint
```

This is an important distinction between **guest OS routing** and **cloud network routing**.

---

# Part 18 — Traceroute Experiment

Command:

```bash
sudo traceroute -T -p 443 s3.eu-central-1.amazonaws.com
```

Observed output:

```text
traceroute to s3.eu-central-1.amazonaws.com (...), 30 hops max
1  <S3-IP>  ...
```

Traceroute showed the S3 destination effectively as the first visible hop.

Why?

AWS virtual networking does not expose all internal forwarding components as normal IP router hops that respond to traceroute TTL-expiry probes.

Therefore traceroute does **not** reliably prove whether the path used:

```text
Internet Gateway
```

or:

```text
S3 Gateway Endpoint
```

The route-table entry is stronger evidence:

```text
S3 prefix list -> S3 Gateway Endpoint
```

The strongest practical proof would be a private instance with:

```text
no public IP
no NAT Gateway
no Internet Gateway path
S3 Gateway Endpoint route present
```

and then successfully accessing S3.

---

# Part 19 — Accessing the Same Bucket from WSL

The S3 Gateway Endpoint only changes the network path for workloads using the associated VPC route table.

The local WSL machine is outside the VPC.

So:

```text
EC2
 -> S3 Gateway Endpoint
 -> S3

WSL
 -> Internet
 -> S3 public regional endpoint
 -> S3
```

Both can access the same S3 bucket if their IAM permissions allow it.

A publicly reachable S3 API endpoint does **not** mean that the bucket or its objects are publicly readable.

---

# Part 20 — Cleanup

Cleanup was performed in dependency-safe order.

## 1. Terminate EC2

```bash
aws ec2 terminate-instances \
  --instance-ids "$EC2_INSTANCE_ID"

aws ec2 wait instance-terminated \
  --instance-ids "$EC2_INSTANCE_ID"
```

Delete key pair:

```bash
aws ec2 delete-key-pair --key-name s3-lab-key
rm -f ~/s3-lab-key.pem
```

## 2. Delete S3 Gateway Endpoint

```bash
aws ec2 delete-vpc-endpoints \
  --vpc-endpoint-ids "$S3_ENDPOINT_ID"
```

## 3. Empty and delete S3 bucket

```bash
aws s3 rm \
  s3://shalu-devops-lab-20261004 \
  --recursive

aws s3api delete-bucket \
  --bucket shalu-devops-lab-20261004 \
  --region eu-central-1
```

## 4. Remove IAM role dependencies

Detach policy:

```bash
aws iam detach-role-policy \
  --role-name ec2-s3-lab-role \
  --policy-arn arn:aws:iam::<ACCOUNT_ID>:policy/EC2S3LabPolicy
```

Remove role from instance profile:

```bash
aws iam remove-role-from-instance-profile \
  --instance-profile-name ec2-s3-lab-profile \
  --role-name ec2-s3-lab-role
```

Delete instance profile:

```bash
aws iam delete-instance-profile \
  --instance-profile-name ec2-s3-lab-profile
```

Delete role:

```bash
aws iam delete-role \
  --role-name ec2-s3-lab-role
```

## 5. Delete old policy versions

Attempting to delete the managed policy initially produced:

```text
DeleteConflict:
This policy has more than one version.
Before you delete a policy, you must delete the policy's versions.
The default version is deleted with the policy.
```

List versions:

```bash
aws iam list-policy-versions \
  --policy-arn arn:aws:iam::<ACCOUNT_ID>:policy/EC2S3LabPolicy
```

Delete every **non-default** version:

```bash
aws iam delete-policy-version \
  --policy-arn arn:aws:iam::<ACCOUNT_ID>:policy/EC2S3LabPolicy \
  --version-id v1
```

Repeat for all non-default versions.

Do **not** manually delete the current default version.

Then delete the policy:

```bash
aws iam delete-policy \
  --policy-arn arn:aws:iam::<ACCOUNT_ID>:policy/EC2S3LabPolicy
```

## 6. Delete network resources

Check ENIs first:

```bash
aws ec2 describe-network-interfaces \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'NetworkInterfaces[*].[NetworkInterfaceId,Status,Description]' \
  --output table
```

Delete Security Group:

```bash
aws ec2 delete-security-group \
  --group-id "$PUBLIC_SG_ID"
```

Delete subnet:

```bash
aws ec2 delete-subnet \
  --subnet-id "$PUBLIC_SUBNET_ID"
```

Delete custom route table:

```bash
aws ec2 delete-route-table \
  --route-table-id "$PUBLIC_RT_ID"
```

Detach Internet Gateway:

```bash
aws ec2 detach-internet-gateway \
  --internet-gateway-id "$IGW_ID" \
  --vpc-id "$VPC_ID"
```

Delete Internet Gateway:

```bash
aws ec2 delete-internet-gateway \
  --internet-gateway-id "$IGW_ID"
```

Delete VPC:

```bash
aws ec2 delete-vpc \
  --vpc-id "$VPC_ID"
```

---

# Troubleshooting Lessons

| Symptom | Likely meaning |
|---|---|
| `AccessDenied` on `PutObject` | IAM authorization failure; action not allowed or explicitly denied |
| `403 Forbidden` from `HeadObject` during `aws s3 cp` | High-level CLI performed a metadata/object check before transfer |
| `aws s3 ls` gives no output but no error | Bucket is accessible but empty |
| `DeleteConflict` deleting IAM managed policy | Non-default policy versions still exist |
| Traceroute shows S3 as first visible hop | AWS internal virtual routing is not exposed as normal router hops |

---

# Key Mental Models

## IAM

```text
Authentication answers:
Who are you?

Authorization answers:
What are you allowed to do?
```

An identity can authenticate successfully and still be denied a specific API action.

## EC2 role credentials

```text
EC2
 -> Instance Profile
 -> IAM Role
 -> STS temporary credentials
 -> IMDS
 -> AWS CLI / SDK credential provider chain
```

## IAM evaluation

```text
No matching Allow
-> implicit deny

Allow + Explicit Deny
-> Deny
```

## S3 ARNs

```text
Bucket-level action
-> bucket ARN

Object-level action
-> bucket/* ARN
```

## VPC routing

```text
Instance OS
-> subnet/VPC router
-> subnet-associated route table
-> destination target
```

## Gateway Endpoint

```text
Route-table based
No ENI
No endpoint private IP
No endpoint Security Group
```

## Interface Endpoint

```text
ENI based
Private IPs
Security Groups
PrivateLink
```

---

# Interview-Ready Questions

### Why should EC2 use an IAM role instead of static AWS credentials?

IAM roles provide temporary, automatically rotated credentials. Applications can obtain them through the standard AWS credential provider chain without storing long-lived secrets on the instance.

### What is the difference between an IAM trust policy and a permission policy?

A trust policy defines **who may assume a role**. A permission policy defines **what actions the resulting identity may perform on which resources**.

### What happens if both Allow and Deny match an IAM request?

An explicit Deny wins.

### Why do `s3:ListBucket` and `s3:GetObject` use different resource ARNs?

`ListBucket` acts on the bucket resource itself, while `GetObject` acts on individual objects inside the bucket.

### How is an S3 Gateway Endpoint different from an Interface Endpoint?

A Gateway Endpoint modifies VPC route tables and does not create ENIs or use endpoint Security Groups. An Interface Endpoint creates private ENIs inside selected subnets and normally uses Security Groups through AWS PrivateLink.

### Can traceroute prove that an S3 Gateway Endpoint is being used?

Not reliably. AWS virtual networking components are not necessarily visible as normal traceroute hops. The VPC route table and a private-subnet/no-NAT connectivity test are stronger evidence.

### If an EC2 instance has both an Internet Gateway route and an S3 Gateway Endpoint route, which path is used for S3?

The S3 destination matches the AWS-managed S3 prefix-list route, which is more specific than the generic `0.0.0.0/0` route, so S3 traffic uses the Gateway Endpoint.

---

# Day 4 Outcome

By the end of this lab, the following were demonstrated practically:

- EC2 role-based AWS authentication without manually configured static credentials
- Temporary STS credentials supplied through IMDS
- Least-privilege S3 access
- Bucket ARN vs object ARN
- Implicit IAM deny
- Explicit IAM deny overriding Allow
- IAM managed-policy versioning
- Difference between human IAM permissions and EC2 service roles
- Difference between Interface and Gateway VPC Endpoints
- S3 Gateway Endpoint routing through an AWS-managed prefix list
- Guest OS routing vs VPC route-table routing
- Limitations of traceroute in AWS virtual networking
- Dependency-aware AWS resource cleanup

---

# Next Session — Day 5

Start with a short Day 4 recap, then move into a more production-style availability lab:

```text
Application Load Balancer
        |
        v
Target Group
   |        |
   v        v
 EC2      EC2
   \        /
    Auto Scaling Group
          |
          v
      CloudWatch
```

Planned topics:

- Application Load Balancer (ALB)
- Target groups and health checks
- Launch Templates
- Auto Scaling Groups (ASG)
- Load balancer and application Security Group separation
- Health-based instance replacement
- CloudWatch metrics
- Controlled instance/application failure
- Observing how AWS detects and recovers from failure


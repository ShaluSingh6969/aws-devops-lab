# AWS EC2 and VPC Networking Lab

Hands-on AWS networking lab covering custom VPC creation, subnets, route tables, Internet Gateway, Security Groups, EC2, IAM instance profiles, and connectivity troubleshooting.

Primary region:

```text
eu-central-1
```

---

# Architecture

```text
Internet
   |
   |
Internet Gateway
   |
   |
VPC: 10.10.0.0/16
   |
   └── Public Subnet: 10.10.1.0/24
          |
          ├── Route Table
          │      10.10.0.0/16 → local
          │      0.0.0.0/0    → Internet Gateway
          │
          └── EC2
                 Private IP: 10.10.1.x
                 Public IPv4
                 Security Group
                 IAM Instance Profile
```

---

# 1. Create VPC

```bash
aws ec2 create-vpc \
  --cidr-block 10.10.0.0/16 \
  --region eu-central-1 \
  --tag-specifications \
  'ResourceType=vpc,Tags=[{Key=Name,Value=devops-lab-vpc}]'
```

Store VPC ID:

```bash
export VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=devops-lab-vpc" \
  --query 'Vpcs[0].VpcId' \
  --output text)
```

Verify:

```bash
echo $VPC_ID
```

---

# 2. Enable VPC DNS

```bash
aws ec2 modify-vpc-attribute \
  --vpc-id $VPC_ID \
  --enable-dns-support '{"Value":true}'
```

```bash
aws ec2 modify-vpc-attribute \
  --vpc-id $VPC_ID \
  --enable-dns-hostnames '{"Value":true}'
```

---

# 3. Create Public Subnet

```bash
aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.10.1.0/24 \
  --availability-zone eu-central-1a \
  --tag-specifications \
  'ResourceType=subnet,Tags=[{Key=Name,Value=public-subnet-a}]'
```

Store subnet ID:

```bash
export PUBLIC_SUBNET_ID=$(aws ec2 describe-subnets \
  --filters "Name=tag:Name,Values=public-subnet-a" \
  --query 'Subnets[0].SubnetId' \
  --output text)
```

The subnet determines which private IP range an EC2 network interface receives its address from.

Example:

```text
Subnet: 10.10.1.0/24

EC2 private IP:
10.10.1.237
```

---

# 4. VPC vs Subnet

```text
VPC
= overall isolated AWS network
= defines overall address space

Subnet
= smaller network carved from VPC
= belongs to one Availability Zone
= provides private IP range for resources
```

Example:

```text
VPC
10.10.0.0/16

└── subnet
    10.10.1.0/24
```

Every EC2 instance must have an ENI in a subnet.

Every subnet belongs to a VPC.

---

# 5. Create Internet Gateway

```bash
aws ec2 create-internet-gateway \
  --tag-specifications \
  'ResourceType=internet-gateway,Tags=[{Key=Name,Value=devops-lab-igw}]'
```

Store ID:

```bash
export IGW_ID=$(aws ec2 describe-internet-gateways \
  --filters "Name=tag:Name,Values=devops-lab-igw" \
  --query 'InternetGateways[0].InternetGatewayId' \
  --output text)
```

Attach it to the VPC:

```bash
aws ec2 attach-internet-gateway \
  --internet-gateway-id $IGW_ID \
  --vpc-id $VPC_ID
```

An Internet Gateway alone does **not** make a subnet public.

---

# 6. Create Public Route Table

```bash
aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --tag-specifications \
  'ResourceType=route-table,Tags=[{Key=Name,Value=public-route-table}]'
```

Store ID:

```bash
export PUBLIC_RT_ID=$(aws ec2 describe-route-tables \
  --filters "Name=tag:Name,Values=public-route-table" \
  --query 'RouteTables[0].RouteTableId' \
  --output text)
```

Create default route:

```bash
aws ec2 create-route \
  --route-table-id $PUBLIC_RT_ID \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id $IGW_ID
```

Associate route table with subnet:

```bash
aws ec2 associate-route-table \
  --route-table-id $PUBLIC_RT_ID \
  --subnet-id $PUBLIC_SUBNET_ID
```

Inspect:

```bash
aws ec2 describe-route-tables \
  --route-table-ids $PUBLIC_RT_ID
```

Observed routes:

```text
10.10.0.0/16 → local
0.0.0.0/0    → Internet Gateway
```

---

# 7. Route Origin

The local route showed:

```text
Origin: CreateRouteTable
```

because AWS automatically creates the local VPC route when the route table is created.

Example:

```text
10.10.0.0/16 → local
```

The internet route showed:

```text
Origin: CreateRoute
```

because it was explicitly added using:

```bash
aws ec2 create-route
```

Mental model:

```text
CreateRouteTable
→ automatically created with route table

CreateRoute
→ explicitly added afterward
```

---

# 8. Public Subnet Definition

A subnet becomes public when its route table contains a route to an Internet Gateway.

```text
Subnet
+
0.0.0.0/0 → Internet Gateway
=
Public Subnet
```

For an EC2 instance to communicate directly with the public internet it normally also needs:

```text
Public subnet
+
public IPv4/EIP
+
route to Internet Gateway
+
Security Group allowing required traffic
```

---

# 9. Create Security Group

```bash
aws ec2 create-security-group \
  --group-name devops-lab-sg \
  --description "Security group for DevOps lab EC2" \
  --vpc-id $VPC_ID
```

Store ID:

```bash
export SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=devops-lab-sg" \
  --query 'SecurityGroups[0].GroupId' \
  --output text)
```

---

# 10. SSH Access

Get local public IP:

```bash
curl -s https://checkip.amazonaws.com
```

Allow TCP/22 only from the local public IP:

```bash
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 22 \
  --cidr <PUBLIC-IP>/32
```

This avoids exposing SSH to the entire internet.

---

# 11. HTTP Access

Allow HTTP from anywhere:

```bash
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0
```

Security Group mental model:

```text
Route Table
= Where can traffic go?

Security Group
= Is the traffic allowed?
```

Security Groups are stateful.

Return traffic for an allowed connection is automatically permitted.

---

# 12. Create EC2 SSH Key

```bash
aws ec2 create-key-pair \
  --key-name devops-lab-key \
  --query 'KeyMaterial' \
  --output text > devops-lab-key.pem
```

Restrict permissions:

```bash
chmod 400 devops-lab-key.pem
```

Never commit private keys to Git.

---

# 13. Retrieve Amazon Linux AMI

```bash
export AMI_ID=$(aws ssm get-parameter \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query 'Parameter.Value' \
  --output text)
```

Verify:

```bash
echo $AMI_ID
```

---

# 14. Launch EC2

```bash
aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type t3.micro \
  --subnet-id $PUBLIC_SUBNET_ID \
  --security-group-ids $SG_ID \
  --associate-public-ip-address \
  --key-name devops-lab-key \
  --iam-instance-profile Name=ec2-lab-profile \
  --tag-specifications \
  'ResourceType=instance,Tags=[{Key=Name,Value=devops-lab-ec2}]'
```

Store instance ID:

```bash
export INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=devops-lab-ec2" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)
```

Wait until running:

```bash
aws ec2 wait instance-running \
  --instance-ids $INSTANCE_ID
```

Inspect networking:

```bash
aws ec2 describe-instances \
  --instance-ids $INSTANCE_ID \
  --query \
  'Reservations[0].Instances[0].[State.Name,PrivateIpAddress,PublicIpAddress,IamInstanceProfile.Arn]' \
  --output table
```

Observed architecture:

```text
EC2
Private IP: 10.10.1.x
Public IPv4: assigned
Instance Profile: ec2-lab-profile
```

---

# 15. SSH Into EC2

```bash
ssh -i devops-lab-key.pem \
  ec2-user@<PUBLIC-IP>
```

---

# 16. Verify Internet Connectivity

From EC2:

```bash
curl -I https://aws.amazon.com
```

Traffic path:

```text
EC2
 ↓
public subnet
 ↓
route table
 ↓
0.0.0.0/0
 ↓
Internet Gateway
 ↓
Internet
```

---

# 17. Verify IAM Role

Inside EC2:

```bash
aws sts get-caller-identity
```

Expected:

```text
arn:aws:sts::<ACCOUNT-ID>:assumed-role/ec2-lab-role/...
```

No static AWS credentials were configured on the server.

Test S3 permission:

```bash
aws s3 ls
```

---

# 18. Install nginx

```bash
sudo dnf install -y nginx
```

Enable and start:

```bash
sudo systemctl enable --now nginx
```

Verify locally:

```bash
curl http://localhost
```

Check listener:

```bash
sudo ss -lntp | grep ':80'
```

---

# 19. Test HTTP Externally

From WSL:

```bash
curl -I http://<PUBLIC-IP>
```

Traffic path:

```text
WSL
 ↓
Internet
 ↓
AWS Internet Gateway
 ↓
VPC
 ↓
Public Subnet
 ↓
EC2 ENI
 ↓
Security Group allows TCP/80
 ↓
Linux networking stack
 ↓
nginx :80
```

---

# 20. Security Group Failure Lab

Started a temporary HTTP server:

```bash
python3 -m http.server 8080
```

Verified locally:

```bash
curl http://localhost:8080
```

The application was listening, but the Security Group had no rule for TCP/8080.

External request:

```bash
curl -v \
  --connect-timeout 5 \
  http://<PUBLIC-IP>:8080
```

failed.

This proves:

```text
application listening
+
routing works
+
public IP exists

BUT

Security Group blocks TCP/8080

→ external connection fails
```

---

# 21. Temporarily Allow TCP/8080

```bash
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 8080 \
  --cidr 0.0.0.0/0
```

Retry:

```bash
curl http://<PUBLIC-IP>:8080
```

The request succeeded.

Remove the rule:

```bash
aws ec2 revoke-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 8080 \
  --cidr 0.0.0.0/0
```

The connection then failed again.

---

# 22. Network Troubleshooting Model

Useful diagnostic sequence:

```text
Is the application listening?
        ↓
ss -lntp

Is the destination routable?
        ↓
route table / public IP / IGW

Is AWS permitting the connection?
        ↓
Security Group

Is there another network filter?
        ↓
NACL / operating-system firewall
```

Useful distinction:

```text
Security Group blocks traffic
→ usually timeout

Security Group allows traffic
but nothing listening
→ connection refused

Security Group allows traffic
and service is listening
→ connection succeeds
```

---

# 23. Local Route Inspection

When accessing an EC2 instance directly by IP:

```bash
curl http://<PUBLIC-IP>
```

DNS is not involved.

Linux checks its routing table instead.

From WSL:

```bash
ip route get <PUBLIC-IP>
```

Other useful tools:

```bash
traceroute <PUBLIC-IP>
```

```bash
tracepath <PUBLIC-IP>
```

```bash
mtr <PUBLIC-IP>
```

Not every intermediate AWS router will necessarily appear because AWS internal networking is abstracted and routers may not respond to traceroute probes.

---

# 24. Public vs Private AWS Subnets

Public subnet:

```text
route table contains
0.0.0.0/0 → Internet Gateway
```

Private subnet:

```text
no direct default route to Internet Gateway
```

Private resources remain reachable through internal VPC networking where routing and security policies permit it.

Later, a NAT Gateway can allow private resources to initiate internet connections without exposing them directly to inbound internet traffic.

---

# 25. Cleanup

Lab resources should not be left running unnecessarily.

Terminate EC2:

```bash
aws ec2 terminate-instances \
  --instance-ids $INSTANCE_ID
```

Wait:

```bash
aws ec2 wait instance-terminated \
  --instance-ids $INSTANCE_ID
```

Delete AWS key pair:

```bash
aws ec2 delete-key-pair \
  --key-name devops-lab-key
```

Delete local key:

```bash
rm devops-lab-key.pem
```

Delete Security Group:

```bash
aws ec2 delete-security-group \
  --group-id $SG_ID
```

Find route table association:

```bash
aws ec2 describe-route-tables \
  --route-table-ids $PUBLIC_RT_ID \
  --query 'RouteTables[0].Associations'
```

Disassociate custom route table:

```bash
aws ec2 disassociate-route-table \
  --association-id <ASSOCIATION-ID>
```

Delete route table:

```bash
aws ec2 delete-route-table \
  --route-table-id $PUBLIC_RT_ID
```

Detach Internet Gateway:

```bash
aws ec2 detach-internet-gateway \
  --internet-gateway-id $IGW_ID \
  --vpc-id $VPC_ID
```

Delete Internet Gateway:

```bash
aws ec2 delete-internet-gateway \
  --internet-gateway-id $IGW_ID
```

Delete subnet:

```bash
aws ec2 delete-subnet \
  --subnet-id $PUBLIC_SUBNET_ID
```

Delete VPC:

```bash
aws ec2 delete-vpc \
  --vpc-id $VPC_ID
```

---

# Cost Rule

For learning labs:

```text
CREATE
  ↓
TEST
  ↓
INSPECT
  ↓
BREAK
  ↓
TROUBLESHOOT
  ↓
DOCUMENT
  ↓
DESTROY
```

Do not leave temporary EC2 instances or other billable resources running when they are not being used.

---

# Key Takeaways

```text
VPC
= isolated AWS network

Subnet
= network segment inside a VPC

Route Table
= determines where packets go

Internet Gateway
= provides VPC connectivity to/from the internet

Security Group
= stateful virtual firewall around ENIs

EC2
= compute instance attached to an ENI in a subnet

Instance Profile
= attaches IAM role to EC2
```
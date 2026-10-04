# AWS Day 3 – SSM Session Manager, Private EC2 Access, IAM Failure Testing, and VPC Endpoints

## Goal

Build and troubleshoot secure access to a private EC2 instance using **AWS Systems Manager Session Manager** without exposing SSH to the internet.

The lab covered:

- A custom **VPC (Virtual Private Cloud)**
- Public and private subnets
- **IGW (Internet Gateway)**
- Public and private route tables
- **NAT (Network Address Translation) Gateway**
- Private EC2 instance with no public IP
- **SSM (AWS Systems Manager) Session Manager**
- IAM role and instance profile
- SSM Agent
- Session Manager Plugin on WSL
- Network failure testing
- IAM permission failure testing
- **VPC Interface Endpoints**
- **AWS PrivateLink**
- Private DNS for SSM endpoints
- Removal of NAT dependency
- Full cleanup

## 1. Initial Architecture

```text
Laptop / WSL
    |
    | AWS CLI
    v
AWS Systems Manager
    ^
    |
    | HTTPS
    |
Private EC2
10.20.10.x
    |
Private Route Table
0.0.0.0/0 -> NAT Gateway
    |
NAT Gateway in Public Subnet
    |
Public Route Table
0.0.0.0/0 -> IGW
    |
Internet / AWS public SSM endpoint
```

The private EC2 had no public IP, no inbound SSH rule, and no bastion host.

## 2. Important Full Forms

| Acronym | Full Form | Meaning |
|---|---|---|
| VPC | Virtual Private Cloud | Isolated AWS network |
| IGW | Internet Gateway | VPC-level internet gateway |
| NAT | Network Address Translation | Rewrites source/destination addresses |
| SG | Security Group | Stateful ENI/resource firewall |
| ENI | Elastic Network Interface | Virtual network interface in AWS |
| IAM | Identity and Access Management | AWS identity and permissions |
| STS | Security Token Service | Issues temporary AWS credentials |
| SSM | AWS Systems Manager | AWS management service |
| IMDS | Instance Metadata Service | EC2 metadata and temporary credentials |
| API | Application Programming Interface | Service interface used by AWS CLI/SDK |
| HTTPS | Hypertext Transfer Protocol Secure | HTTP over TLS, usually TCP/443 |
| TCP | Transmission Control Protocol | Layer 4 connection-oriented protocol |
| DNS | Domain Name System | Resolves names to IP addresses |
| CIDR | Classless Inter-Domain Routing | IP range notation |
| AWS PrivateLink | Private connectivity technology behind Interface VPC Endpoints | Keeps service traffic private |

## 3. Lab Network

VPC:

```text
10.20.0.0/16
vpc-0d2da0992affe50f2
```

Public subnet:

```text
10.20.1.0/24
subnet-01d516d8f2c1e8960
eu-central-1a
```

Private subnet:

```text
10.20.10.0/24
subnet-00c214ab80165ceab
eu-central-1a
```

Private route table:

```text
rtb-0e27e2ff9e10da090
10.20.0.0/16 -> local
0.0.0.0/0   -> NAT Gateway
```

Public route table:

```text
rtb-060bdc8879740b8e6
10.20.0.0/16 -> local
0.0.0.0/0   -> IGW
```

Internet Gateway:

```text
igw-0ac7fe5aca73e50ca
```

NAT Gateway:

```text
nat-06c3f39b6b161aa90
```

## 4. Why NAT Was Needed Initially

The private EC2 had no public IPv4 address, so direct public internet access through an IGW would not work.

```text
Private EC2 private IP
        |
        v
NAT Gateway
        |
source rewritten to NAT Gateway Elastic IP
        |
        v
IGW
        |
        v
AWS public SSM endpoint
```

The NAT Gateway uses its own Elastic IP; it does not reuse another EC2 instance's public IP.

## 5. Internet Gateway Placement

An IGW is attached to the **VPC**, not directly to a subnet.

A subnet becomes public when its route table contains:

```text
0.0.0.0/0 -> IGW
```

## 6. Security Group Behavior

The private EC2 Security Group had:

```text
Inbound: none
Outbound: allow all
```

Default outbound rule:

```text
Protocol: -1
Destination: 0.0.0.0/0
```

`-1` means all protocols.

A Security Group is stateful. Return traffic for an allowed connection is automatically permitted, but a brand-new outbound connection still needs an outbound rule. In this lab, the default outbound allow-all rule already allowed HTTPS to AWS SSM.

## 7. IAM Role for SSM

Role:

```text
ssm-lab-role
```

Instance profile:

```text
ssm-lab-profile
```

Managed policy:

```text
AmazonSSMManagedInstanceCore
```

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

Mental model:

```text
Trust policy = WHO may assume the role
Permission policy = WHAT the role can do
```

## 8. User IAM vs EC2 IAM

Two identities were involved:

```text
Private EC2
-> ssm-lab-role
-> AmazonSSMManagedInstanceCore
```

and:

```text
shalu-admin
-> calls SSM StartSession API
```

Useful commands:

```bash
aws sts get-caller-identity
aws configure list
```

## 9. Private EC2

Instance:

```text
i-0600f8eda0489abf6
```

Private IP:

```text
10.20.10.201
```

The instance had no public IP and no inbound SSH rule.

## 10. SSM Agent Registration

Command:

```bash
aws ssm describe-instance-information \
  --query 'InstanceInformationList[*].[InstanceId,PingStatus,PlatformName,AgentVersion]' \
  --output table
```

Observed:

```text
InstanceId: i-0600f8eda0489abf6
PingStatus: Online
PlatformName: Amazon Linux
AgentVersion: 3.3.5226.0
```

This proved:

```text
SSM Agent running
+
IAM role valid
+
network path through NAT
=
instance registered with SSM
```

## 11. Session Manager Plugin on WSL

The first `start-session` failed because the local Session Manager Plugin was missing.

Installation:

```bash
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" \
  -o "session-manager-plugin.deb"
```

```bash
sudo dpkg -i session-manager-plugin.deb
```

Verification:

```bash
session-manager-plugin
```

## 12. First Successful SSM Session

```bash
aws ssm start-session \
  --target i-0600f8eda0489abf6
```

Inside the instance:

```bash
whoami
```

returned:

```text
ssm-user
```

Hostname:

```text
ip-10-20-10-201.eu-central-1.compute.internal
```

This used no SSH, no TCP/22, no public IP, and no bastion host.

## 13. How Session Manager Traffic Works

The EC2 does not wait for a fresh inbound connection from the laptop.

```text
SSM Agent on EC2
-> initiates outbound connection
-> AWS Systems Manager
```

Then:

```text
Laptop / AWS CLI
-> AWS SSM API
-> StartSession
```

AWS uses the already-established management channel to reach the agent. Therefore no inbound Security Group rule is required.

## 14. EC2 Network Inspection

Inside the SSM session:

```bash
ip addr
```

showed:

```text
ens5
10.20.10.201/24
altname eni-0780333d3c0a4cf96
```

Routing:

```bash
ip route
```

showed:

```text
default via 10.20.10.1 dev ens5
```

The instance only knows its local default gateway. AWS VPC routing later applies the subnet route table.

The route table also showed the AWS-provided VPC DNS resolver path to `10.20.0.2`.

## 15. SSM Agent Process Tree

```bash
sudo systemctl status amazon-ssm-agent
```

showed processes including:

```text
amazon-ssm-agent
ssm-agent-worker
ssm-session-worker
sh
```

The active shell was created under an `ssm-session-worker`, confirming it was not SSH.

## 16. Network Failure Test

The private default route was deleted:

```bash
aws ec2 delete-route \
  --route-table-id rtb-0e27e2ff9e10da090 \
  --destination-cidr-block 0.0.0.0/0
```

The private route table then only had:

```text
10.20.0.0/16 -> local
```

Effects:

```text
LastPingDateTime stopped advancing
new SSM sessions could not fully establish
some start-session commands hung after receiving a SessionId
```

## 17. PingStatus vs LastPingDateTime

`PingStatus` remained `Online` for some time even after the network path was removed.

But:

```text
LastPingDateTime stopped changing
```

This showed:

```text
PingStatus = recent known state
LastPingDateTime = stronger evidence of continuing agent communication
```

## 18. Restoring the NAT Route

```bash
aws ec2 create-route \
  --route-table-id rtb-0e27e2ff9e10da090 \
  --destination-cidr-block 0.0.0.0/0 \
  --nat-gateway-id nat-06c3f39b6b161aa90
```

After waiting, the heartbeat resumed and Session Manager worked again.

## 19. Stale Session Cleanup

Active sessions were inspected with:

```bash
aws ssm describe-sessions \
  --state Active \
  --query 'Sessions[*].[SessionId,Target,Status,StartDate]' \
  --output table
```

Stale sessions were terminated using:

```bash
aws ssm terminate-session \
  --session-id <SESSION_ID>
```

Local plugin cleanup:

```bash
pkill -f session-manager-plugin
```

## 20. IAM Failure Test

The policy was detached from the EC2 role:

```bash
aws iam detach-role-policy \
  --role-name ssm-lab-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
```

A new session failed with:

```text
AccessDeniedException
```

and specifically:

```text
ssmmessages:CreateDataChannel
```

The failing identity was the EC2's assumed role session:

```text
arn:aws:sts::<ACCOUNT_ID>:assumed-role/ssm-lab-role/i-0600f8eda0489abf6
```

This proved the network path worked, but IAM authorization was missing.

## 21. Network Failure vs IAM Failure

Network failure:

```text
NAT route removed
-> LastPingDateTime stops
-> session hangs / TargetNotConnected
```

IAM failure:

```text
network works
-> request reaches AWS
-> AccessDeniedException
```

## 22. IAM Recovery

```bash
aws iam attach-role-policy \
  --role-name ssm-lab-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
```

After the heartbeat updated again, Session Manager worked.

## 23. Moving to VPC Endpoints

The goal was to remove the NAT dependency for SSM.

```text
Private EC2
↓
private VPC traffic
↓
Interface VPC Endpoint
↓
AWS Systems Manager
```

No public internet path was required.

## 24. Interface VPC Endpoint

An Interface VPC Endpoint creates ENIs inside selected subnets and is powered by AWS PrivateLink.

Each endpoint ENI has a private IP and can use a Security Group.

## 25. Endpoint Security Group

A separate endpoint SG was created.

Inbound rule:

```text
TCP/443
Source = private EC2 Security Group
```

Private EC2 SG ID:

```text
sg-0d6143e47f92dde93
```

Using a Security Group reference is preferable to hardcoding `10.20.10.201/32` because the EC2 private IP may change and multiple instances can share the same SG.

## 26. SSM VPC Endpoints

Two Interface VPC Endpoints were created:

```text
com.amazonaws.eu-central-1.ssm
com.amazonaws.eu-central-1.ssmmessages
```

Endpoint IDs:

```text
vpce-0acf0ca8fd3fd17b3
vpce-066df8a3245560fc0
```

Private DNS was enabled.

## 27. Private DNS

With Private DNS enabled, normal AWS service names can resolve inside the VPC to endpoint ENI private IPs.

Useful commands:

```bash
getent hosts ssm.eu-central-1.amazonaws.com
getent hosts ssmmessages.eu-central-1.amazonaws.com
```

or:

```bash
dig ssm.eu-central-1.amazonaws.com
```

## 28. Inspecting Endpoint ENIs

```bash
aws ec2 describe-vpc-endpoints \
  --query 'VpcEndpoints[*].{Endpoint:VpcEndpointId,Service:ServiceName,Subnets:SubnetIds,ENIs:NetworkInterfaceIds}' \
  --output json
```

```bash
aws ec2 describe-network-interfaces \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'NetworkInterfaces[*].{ENI:NetworkInterfaceId,Subnet:SubnetId,PrivateIP:PrivateIpAddress,Description:Description}' \
  --output table
```

An interface endpoint creates an endpoint ENI in every selected subnet, typically one subnet per AZ for multi-AZ redundancy.

## 29. Why NAT Was No Longer Needed

With interface endpoints:

```text
Private EC2 private IP
↓
VPC local routing
↓
Endpoint ENI private IP
↓
AWS Systems Manager
```

No source masquerading was required because the path stayed private.

Difference:

```text
NAT Gateway
= private EC2 reaches public service endpoint using translated public source IP

Interface Endpoint
= private EC2 reaches AWS service using private IPs
```

## 30. Final Proof – SSM Without NAT

The private default route to NAT was removed again.

The private route table only contained:

```text
10.20.0.0/16 -> local
```

Despite that:

```text
LastPingDateTime continued advancing
PingStatus remained Online
```

and a new session succeeded:

```bash
aws ssm start-session \
  --target i-0600f8eda0489abf6
```

This proved the final architecture:

```text
Private EC2
↓
Private DNS
↓
SSM Interface Endpoint ENI
↓
AWS Systems Manager
```

with:

```text
No public IP
No SSH
No bastion
No NAT route
```

## 31. Final Architecture

```text
Laptop / WSL
        |
        | AWS API
        v
AWS Systems Manager
        ^
        |
AWS PrivateLink
        ^
        |
Interface VPC Endpoints
(ssm + ssmmessages)
        ^
        |
        | TCP/443
        |
Private EC2
10.20.10.201
```

## 32. Cleanup

Resources deleted after the lab:

```text
SSM interface endpoints
EC2 instance
endpoint ENIs
custom Security Groups
NAT Gateway
Elastic IP
public subnet
private subnet
custom route tables
Internet Gateway
VPC
```

The Internet Gateway had to be detached from the VPC before it could be deleted.

## 33. Default VPC Discovery

The account also contained another VPC with existing subnets, Security Groups, route tables, NACLs, and an Internet Gateway.

Those resources were not created by this lab and were left untouched.

Important cleanup rule:

```text
Only delete resources belonging to the current lab VPC.
```

## 34. Troubleshooting Signals

```text
TargetNotConnected
-> instance/session communication channel unavailable
```

```text
LastPingDateTime stops advancing
-> agent communication has stopped
```

```text
AccessDeniedException
-> network reached AWS, but IAM permission is missing
```

```text
Starting session... then hangs
-> StartSession API succeeded, but data channel cannot complete
```

## 35. SSM Dependency Chain

```text
SSM Agent running
+
EC2 IAM role authorized
+
network path to SSM service
+
user IAM permission to StartSession
+
Session Manager Plugin installed locally
=
working private shell
```

## 36. Main Lessons

A private instance can be managed with:

```text
No TCP/22 exposure
No public IP
No bastion host
```

Using SSM with Interface VPC Endpoints allows management traffic to remain private and removes the NAT dependency for SSM.

The lab also demonstrated how to distinguish network, IAM, and local-client failures from their actual symptoms rather than guessing.

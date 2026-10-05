# Highly Available Web Application on AWS

## Goal

Build a production-style highly available web architecture on AWS using:

- Application Load Balancer (ALB)
- Auto Scaling Group (ASG)
- Private EC2 instances
- Public and private subnets across multiple Availability Zones
- NAT Gateway for outbound access
- Target Groups and health checks
- Systems Manager (SSM)
- CloudWatch target tracking
- Controlled failure and scaling tests

The main objective was not just to create resources, but to understand how they interact in a production-style environment.

---

# 1. Final Architecture

```text
                              Internet
                                  |
                                  v
                    +---------------------------+
                    | Application Load Balancer |
                    |     Public Subnets        |
                    |   eu-central-1a / 1b      |
                    +-------------+-------------+
                                  |
                                  v
                           Target Group
                                  |
                     +------------+------------+
                     |                         |
                     v                         v
              Private EC2 A             Private EC2 B
              eu-central-1a             eu-central-1b
                     \                         /
                      \                       /
                       +---------------------+
                       | Auto Scaling Group  |
                       +---------------------+
                                  |
                                  v
                              CloudWatch
```

Outbound path for private EC2 instances:

```text
Private EC2
    |
    v
Private Route Table
0.0.0.0/0 -> NAT Gateway
    |
    v
NAT Gateway in Public Subnet
    |
    v
Public Route Table
0.0.0.0/0 -> Internet Gateway
    |
    v
Internet
```

---

# 2. Core Concepts Learned

## 2.1 Public vs Private Subnets

A subnet is not public just because it exists inside a VPC.

A subnet is considered public when its route table contains:

```text
0.0.0.0/0 -> Internet Gateway
```

A private subnet does not have a direct route to the Internet Gateway.

Example:

```text
Public Subnet
10.40.1.0/24
0.0.0.0/0 -> IGW

Private Subnet
10.40.11.0/24
0.0.0.0/0 -> NAT Gateway
```

---

## 2.2 `map-public-ip-on-launch`

This subnet attribute controls whether newly launched EC2 instances automatically receive public IPv4 addresses.

Example:

```bash
aws ec2 modify-subnet-attribute \
  --subnet-id "$SUBNET_A" \
  --map-public-ip-on-launch
```

Important:

```text
Public subnet
!=
All EC2 instances automatically have public IPs
```

The subnet must have:

```text
0.0.0.0/0 -> IGW
```

and an EC2 instance still needs a public IP to communicate directly with the internet.

For backend EC2 instances in this architecture, public IPs were intentionally avoided.

---

# 3. VPC Layout

VPC:

```text
10.40.0.0/16
```

Subnets:

```text
Public Subnet A
10.40.1.0/24
eu-central-1a

Public Subnet B
10.40.2.0/24
eu-central-1b

Private Subnet A
10.40.11.0/24
eu-central-1a

Private Subnet B
10.40.12.0/24
eu-central-1b
```

The ALB was placed in both public subnets.

The Auto Scaling Group launched backend EC2 instances into both private subnets.

---

# 4. NAT Gateway

## What is a NAT Gateway?

NAT stands for:

```text
Network Address Translation
```

A public NAT Gateway allows resources with only private IP addresses to initiate outbound internet connections.

Example:

```text
EC2 Private IP
10.40.11.25
    |
    v
NAT Gateway
    |
    v
Internet Gateway
    |
    v
Internet
```

The destination address does not change.

The source address is translated.

Conceptually:

```text
Before NAT:

src = 10.40.11.25
dst = Internet server

After NAT:

src = NAT Gateway public Elastic IP
dst = Internet server
```

The NAT Gateway remembers the connection state so return traffic can be translated back to the original private EC2 instance.

---

## NAT Gateway vs Internet Gateway

### Internet Gateway

```text
- attached to the VPC
- provides internet connectivity
- used by public subnets
- route target: igw-...
```

### NAT Gateway

```text
- created inside a public subnet
- has a private IP
- public NAT Gateway has an Elastic IP
- performs source NAT
- allows private EC2 instances to initiate outbound connections
- does not allow unsolicited inbound internet connections
```

Traffic path:

```text
Private EC2
-> NAT Gateway
-> Internet Gateway
-> Internet
```

Not:

```text
Internet
-> NAT Gateway
-> Private EC2
```

for new unsolicited connections.

---

# 5. Security Groups

Two security groups were used.

## ALB Security Group

Inbound:

```text
TCP 80
Source: 0.0.0.0/0
```

Outbound:

```text
TCP 80
Destination: EC2 Security Group
```

## EC2 Security Group

Inbound:

```text
TCP 80
Source: ALB Security Group
```

Outbound:

```text
Allow all
```

This created the intended trust relationship:

```text
Internet
-> ALB
-> EC2
```

but prevented:

```text
Internet
-> EC2 directly
```

---

# 6. Security Group Statefulness

Security Groups are stateful.

Example:

```text
Inbound SSH allowed
Outbound rules empty
```

If the connection was initiated inbound and allowed, return traffic is automatically allowed because AWS tracks the connection state.

This is separate from the default rule:

```text
Outbound
All traffic -> 0.0.0.0/0
```

Default outbound allow-all allows new outbound connections.

Statefulness means return traffic for established connections does not need a matching opposite-direction rule.

---

# 7. NACL Recap

NACL stands for:

```text
Network Access Control List
```

Characteristics:

```text
- applied at subnet level
- stateless
- supports ALLOW and DENY rules
- rules evaluated by number
- both directions must be configured independently
```

Comparison:

```text
Security Group
- ENI / instance level
- stateful
- allow rules only

NACL
- subnet level
- stateless
- allow and deny rules
```

Traffic must pass both layers.

It is better to think:

```text
NACL allows
AND
Security Group allows
=
traffic passes
```

rather than saying one takes precedence over the other.

---

# 8. Launch Template

The Launch Template defined how Auto Scaling instances should be created.

Main properties:

```text
AMI
Instance Type
Security Group
User Data
IAM Instance Profile
```

The backend instances used Amazon Linux 2023.

Example user data:

```bash
#!/bin/bash
dnf install -y nginx
systemctl enable nginx
systemctl start nginx

HOSTNAME=$(hostname)

cat > /usr/share/nginx/html/index.html <<HTML
<html>
  <body>
    <h1>Day 5 HA Lab</h1>
    <p>Served by: $HOSTNAME</p>
  </body>
</html>
HTML
```

This made it easy to identify which backend instance served each request.

---

# 9. Target Group

A Target Group represents the backend pool used by the ALB.

Configuration:

```text
Protocol: HTTP
Port: 80
Target Type: instance
Health Check Path: /
Health Check Matcher: HTTP 200
```

Important distinction:

```text
Security Group
-> determines whether traffic is allowed

Target Group
-> determines which backend receives traffic
```

---

# 10. Application Load Balancer

The ALB was internet-facing and deployed across both public subnets.

Traffic flow:

```text
Client
-> ALB DNS
-> Listener :80
-> Target Group
-> healthy EC2 instance
```

Before EC2 targets existed, the ALB returned:

```text
503 Service Temporarily Unavailable
```

This proved:

```text
Client -> ALB -> Listener
```

was working, but there were no healthy backend targets yet.

---

# 11. ALB Listener

A listener was created on:

```text
HTTP :80
```

with the default action:

```text
Forward -> Target Group
```

The listener decides what to do with requests arriving at a specific port.

---

# 12. Auto Scaling Group

ASG configuration:

```text
Min Size: 2
Desired Capacity: 2
Max Size: 4
```

The ASG launched instances across the two private subnets.

Responsibilities:

```text
Launch Template
-> HOW an instance is created

Private Subnets
-> WHERE instances are launched

Desired Capacity
-> HOW MANY instances should exist

Target Group
-> WHERE instances are registered

Health Check
-> whether instances should remain in service
```

---

# 13. ALB Health vs EC2 Running State

Important:

```text
EC2 running
!=
Application healthy
```

An EC2 instance can be:

```text
State = running
```

while the Target Group still reports:

```text
initial
unhealthy
```

because the application may still be starting.

In this lab:

```text
Health Check Interval: 30 seconds
Healthy Threshold: 2
Health Check Path: /
```

After nginx started, the targets became:

```text
healthy
```

---

# 14. Load Balancing Test

Repeated requests showed traffic being distributed across both private instances.

Example:

```text
Served by: ip-10-40-12-52.eu-central-1.compute.internal
Served by: ip-10-40-11-215.eu-central-1.compute.internal
```

This proved:

```text
ALB
-> Target Group
-> multiple healthy EC2 instances
```

was working correctly.

---

# 15. Self-Healing Test

One ASG-managed instance was deliberately terminated.

Expected behavior:

```text
1. Instance terminated
2. ALB stopped routing traffic to it
3. Requests continued through surviving instance
4. ASG detected capacity below desired
5. ASG launched replacement instance
6. Replacement registered with Target Group
7. Health checks passed
8. ALB started routing to replacement
```

Important separation:

```text
ALB
-> protects traffic from unhealthy targets

ASG
-> restores desired capacity
```

These are separate responsibilities.

---

# 16. ASG Activity Events

Useful command:

```bash
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name day5-web-asg \
  --max-items 20 \
  --query 'Activities[*].[StartTime,StatusCode,Description,Cause,StatusMessage]' \
  --output table
```

This showed:

```text
Launching a new EC2 instance
Terminating EC2 instance
WaitingForInstanceWarmup
WaitingForELBConnectionDraining
```

ASG activity history is extremely useful when troubleshooting why capacity changed.

---

# 17. Systems Manager

SSM stands for:

```text
AWS Systems Manager
```

The backend instances had no public IP and no SSH access.

Instead, SSM was used.

Architecture:

```text
Private EC2
-> NAT Gateway
-> Internet Gateway
-> AWS SSM public endpoint
```

No Interface VPC Endpoint was required because NAT already provided outbound access.

Comparison with previous lab:

```text
Without NAT:
Interface Endpoints required

With NAT:
SSM can reach public AWS endpoints
```

---

# 18. SSM IAM Role

An EC2 role was created and attached through an instance profile.

AWS-managed policy:

```text
AmazonSSMManagedInstanceCore
```

Flow:

```text
EC2
-> Instance Profile
-> IAM Role
-> AmazonSSMManagedInstanceCore
-> SSM
```

Important:

```text
EC2-side role
!=
Human-side permission
```

The EC2 role allows the SSM Agent to communicate with AWS.

A human user still needs permissions such as:

```text
ssm:StartSession
ssm:SendCommand
ssm:DescribeSessions
ssm:TerminateSession
```

depending on the operation.

---

# 19. SSM Agent Behavior

The SSM Agent runs as a system service on Amazon Linux.

At boot:

```text
EC2 boots
-> amazon-ssm-agent starts
-> agent checks IMDS
-> receives IAM role temporary credentials
-> connects outbound to Systems Manager
-> registers
-> remains available for commands / sessions
```

---

# 20. Real SSM Registration Failure

One running instance did not register with Systems Manager.

Console output showed:

```text
SSM Agent unable to acquire credentials

no valid credentials could be retrieved for ec2 identity

Default Host Management Err:
Systems Manager's instance management role is not configured
```

Root cause:

The instance had originally booted without the SSM-enabled IAM instance profile.

The profile was attached later to the running instance.

One existing instance successfully recovered and registered.

The other did not.

This demonstrated that manually mutating running ASG instances can lead to inconsistent state.

---

# 21. Better ASG Practice

For Auto Scaling environments:

```text
Do not rely on manually modifying individual instances.
```

Better pattern:

```text
Update Launch Template
-> create new version
-> ASG launches replacement instances
-> configuration exists from boot
```

This follows the idea of immutable infrastructure.

Instances should be treated as:

```text
replaceable cattle
```

rather than:

```text
manually maintained pets
```

Manual IAM profile association can be acceptable for:

```text
one-off EC2
emergency troubleshooting
migration
```

but should not be the normal configuration mechanism for ASG instances.

---

# 22. CloudWatch and Target Tracking

ASG metrics were enabled:

```bash
aws autoscaling enable-metrics-collection \
  --auto-scaling-group-name day5-web-asg \
  --granularity 1Minute
```

A target tracking policy was created based on:

```text
ASGAverageCPUUtilization
```

Target:

```text
20%
```

Concept:

```text
Average CPU above target
-> scale out

Average CPU below target for sustained period
-> scale in
```

---

# 23. CPU Load Test

CPU load was generated through SSM Run Command.

This avoided:

```text
public IP
SSH
opening port 22
```

and preserved the private architecture.

The stressed instance reached approximately:

```text
68.5% CPU
```

The other instances remained near idle.

---

# 24. Scale-Out Result

CloudWatch alarm:

```text
AlarmHigh
State: ALARM
Threshold: 20%
```

Scaling event:

```text
Desired Capacity:
2 -> 4
```

ASG launched two new EC2 instances.

Important:

Target tracking does not necessarily scale by exactly one instance.

It can increase capacity by more than one if AWS estimates that more capacity is needed to move the metric toward the target.

---

# 25. Scale-In Alarm

The low alarm had approximately:

```text
Threshold: 14%
Evaluation Periods: 15
Period: 60 seconds
```

After the load ended, all four instances showed CPU around:

```text
0.23% - 0.27%
```

The low alarm moved to:

```text
ALARM
```

but scale-in was not immediate.

This demonstrated that:

```text
Scale-out
-> aggressive / fast

Scale-in
-> conservative / gradual
```

AWS avoids removing capacity too quickly.

---

# 26. Scale-In Result

Scaling happened in steps:

```text
4 -> 3
3 -> 2
```

ASG events showed:

```text
WaitingForELBConnectionDraining
```

This means the instance was removed from service and the ALB was allowed to finish active connections before termination.

Scale-in path:

```text
Low CPU sustained
-> AlarmLow
-> Target Tracking Policy
-> Desired Capacity reduced
-> Instance selected for termination
-> Target removed from service
-> Connection draining
-> EC2 terminated
```

---

# 27. Connection Draining

Before terminating an instance, the load balancer allows existing connections to finish.

This avoids abruptly dropping active user requests.

Conceptually:

```text
Stop new traffic
-> wait for existing connections
-> terminate backend
```

---

# 28. Basic vs Detailed EC2 Monitoring

Observed CPU metrics were approximately 5 minutes apart.

This is because EC2 basic monitoring typically provides:

```text
5-minute metric granularity
```

Detailed monitoring provides:

```text
1-minute metric granularity
```

This affects how quickly scaling signals can be observed.

---

# 29. Useful Commands

## Check Current AWS Identity

```bash
aws sts get-caller-identity
```

## Check Current Region

```bash
aws configure get region
```

## Check ASG State

```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names day5-web-asg
```

## Check ASG Instances

```bash
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names day5-web-asg \
  --query 'AutoScalingGroups[0].Instances[*].[InstanceId,AvailabilityZone,HealthStatus,LifecycleState]' \
  --output table
```

## Check Target Health

```bash
aws elbv2 describe-target-health \
  --target-group-arn "$TARGET_GROUP_ARN"
```

## Check Scaling Activities

```bash
aws autoscaling describe-scaling-activities \
  --auto-scaling-group-name day5-web-asg \
  --max-items 20 \
  --output table
```

## Check SSM Managed Instances

```bash
aws ssm describe-instance-information \
  --query 'InstanceInformationList[*].[InstanceId,PingStatus,LastPingDateTime,AgentVersion]' \
  --output table
```

## Check CloudWatch Alarms

```bash
aws cloudwatch describe-alarms \
  --query 'MetricAlarms[?contains(AlarmName, `day5-web-asg`)].[AlarmName,StateValue,Threshold]' \
  --output table
```

## Check CPU Utilization

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value="$INSTANCE_ID" \
  --statistics Average \
  --period 300 \
  --start-time "$(date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
```

---

# 30. Cleanup Order

Cleanup was performed in dependency-safe order.

Recommended order:

```text
1. Delete scaling policy
2. Scale ASG to zero
3. Delete ASG
4. Delete ALB listener
5. Delete ALB
6. Delete Target Group
7. Delete Launch Template
8. Delete SSM IAM resources
9. Delete NAT Gateway
10. Release Elastic IP
11. Delete Security Groups
12. Delete private subnets
13. Delete public subnets
14. Delete route tables
15. Detach Internet Gateway
16. Delete Internet Gateway
17. Delete VPC
```

---

# 31. Security Group Cleanup Issue

Even after all ENIs were gone, Security Groups could not initially be deleted.

Reason:

```text
ALB-SG
egress -> EC2-SG

EC2-SG
ingress <- ALB-SG
```

This created a circular Security Group reference.

Even though neither SG was attached to an ENI, AWS still considered the SG references dependencies.

The rules had to be removed first.

Example:

```bash
aws ec2 revoke-security-group-ingress \
  --group-id "$EC2_SG_ID" \
  --protocol tcp \
  --port 80 \
  --source-group "$ALB_SG_ID"
```

and then remove the ALB egress rule referencing the EC2 SG.

After removing the cross-references, both Security Groups could be deleted.

---

# 32. ENI Cleanup Check

ENI stands for:

```text
Elastic Network Interface
```

Useful command:

```bash
aws ec2 describe-network-interfaces \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'NetworkInterfaces[*].[NetworkInterfaceId,Status,Description,PrivateIpAddress,Attachment.InstanceId]' \
  --output table
```

Important lesson:

```text
No ENI dependency
does not necessarily mean
no Security Group dependency
```

Security Groups can still reference each other.

---

# 33. Main Troubleshooting Lessons

## 503 from ALB

Meaning:

```text
ALB reachable
Listener working
No healthy backend target
```

## EC2 running but target unhealthy

Possible causes:

```text
application not started
health check path incorrect
Security Group blocked
bootstrap still running
port not listening
```

## ASG Instances Empty

Check:

```bash
aws autoscaling describe-scaling-activities
```

Possible causes:

```text
Launch Template issue
AMI problem
quota
subnet issue
Security Group mismatch
permission issue
```

## SSM Instance Missing

Check:

```text
IAM profile
SSM Agent
network path
agent registration
```

## Security Group DeleteConflict / DependencyViolation

Check:

```text
ENIs
other Security Group references
ALB
VPC endpoints
instances
```

---

# 34. Interview-Ready Mental Model

## High Availability

```text
ALB
-> spreads traffic

Multiple AZs
-> protects against single-AZ failure

ASG
-> maintains desired number of instances

Target Group health checks
-> keeps traffic away from unhealthy backends

CloudWatch
-> provides scaling signals
```

---

## Inbound Traffic

```text
Internet
-> Internet Gateway
-> Public ALB
-> Target Group
-> Private EC2
```

---

## Outbound Traffic

```text
Private EC2
-> NAT Gateway
-> Internet Gateway
-> Internet
```

---

## Self-Healing

```text
Instance fails
-> ALB removes unhealthy backend
-> ASG notices capacity loss
-> ASG launches replacement
```

---

## Auto Scaling

```text
Metric rises
-> CloudWatch alarm
-> Target Tracking policy
-> Desired Capacity increases

Metric falls
-> Low alarm
-> stabilization
-> connection draining
-> capacity decreases
```

---

# 35. What I Should Remember vs What I Can Look Up

Do not memorize every AWS CLI command.

Remember:

```text
Architecture
Resource relationships
Traffic flow
Failure behavior
Troubleshooting order
Security boundaries
Scaling behavior
```

Commands can be looked up.

Useful AWS CLI patterns:

```text
create-*       -> create resource
describe-*     -> inspect state
modify-*       -> update configuration
associate-*    -> attach resources
authorize-*    -> add SG permissions
revoke-*       -> remove SG permissions
put-*          -> create/update policy
terminate-*    -> terminate EC2
delete-*       -> remove resource
```

---

# 36. Key Takeaways

- Backend EC2 instances should normally remain private.
- The ALB should be the controlled inbound entry point.
- NAT Gateway provides outbound internet access for private resources.
- Security Groups should express trust relationships using SG references where possible.
- ALB health and EC2 running state are different concepts.
- ALB protects traffic from unhealthy targets.
- ASG restores capacity.
- CloudWatch provides scaling signals.
- Target tracking can scale by more than one instance.
- Scale-out is aggressive; scale-in is conservative.
- ASG instances should be replaceable and configured through Launch Templates.
- Manually mutating ASG instances can create configuration drift.
- SSM allows private instance management without SSH/public IPs.
- Cleanup requires understanding dependencies, not just deleting resources randomly.
- Security Group references can create circular dependencies even when no ENIs remain.

---

# 37. Final Architecture Summary

```text
                         Internet
                            |
                            v
                    Internet Gateway
                            |
                            v
            +-------------------------------+
            |      Public Subnets           |
            |                               |
            |  ALB                 NAT GW   |
            +---+-----------------------+---+
                |                       |
                | HTTP                  | outbound
                v                       ^
           Target Group                 |
                |                       |
        +-------+-------+               |
        |               |               |
        v               v               |
 Private EC2 A     Private EC2 B -------+
        \               /
         \             /
          Auto Scaling Group
                 |
                 v
             CloudWatch
```

---

# Day 5 Status

```text
COMPLETED
```

Topics completed:

```text
VPC architecture
Public/private subnets
NAT Gateway
ALB
Target Groups
Security Groups
Launch Templates
Auto Scaling
Health checks
Self-healing
SSM
CloudWatch
Target Tracking
Scale-out
Scale-in
Connection draining
Cleanup troubleshooting
```
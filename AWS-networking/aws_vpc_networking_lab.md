# AWS Day 2 – VPC Networking, Bastion Host, NAT Gateway, Security Groups, and NACLs

## Goal

Build and troubleshoot a small AWS network containing:

- A custom **VPC (Virtual Private Cloud)**
- A public subnet
- A private subnet
- An **IGW (Internet Gateway)**
- Public and private route tables
- Two EC2 instances
- **SGs (Security Groups)**
- A bastion host
- A **NAT (Network Address Translation) Gateway**
- A custom **NACL (Network Access Control List)**
- Practical failure testing for SSH, HTTP, package downloads, and return traffic

---

# 1. Core Network Architecture

The lab architecture was:

```text
Internet
   |
   v
Internet Gateway
   |
   v
VPC 10.10.0.0/16
   |
   +-------------------------------+
   |                               |
   v                               v
Public Subnet                 Private Subnet
10.10.1.0/24                 10.10.10.0/24
   |                               |
Public EC2                      Private EC2
Public + Private IP             Private IP only
```

The public subnet had a route:

```text
0.0.0.0/0 -> Internet Gateway
```

The private subnet initially had only:

```text
10.10.0.0/16 -> local
```

Therefore, the private EC2 could communicate inside the VPC but could not directly access the internet.

---

# 2. Important Full Forms

| Acronym | Full Form | Meaning |
|---|---|---|
| VPC | Virtual Private Cloud | Isolated AWS network |
| IGW | Internet Gateway | Connects a VPC to the public internet |
| ENI | Elastic Network Interface | Virtual network interface used by VPC resources |
| SG | Security Group | Stateful firewall attached to an ENI/resource |
| NACL | Network Access Control List | Stateless subnet-level traffic filter |
| NAT | Network Address Translation | Rewrites IP addresses for network communication |
| CIDR | Classless Inter-Domain Routing | Notation used to define IP ranges |
| SSH | Secure Shell | Remote shell protocol, normally TCP/22 |
| HTTP | Hypertext Transfer Protocol | Web protocol, normally TCP/80 |
| HTTPS | Hypertext Transfer Protocol Secure | HTTP over TLS, normally TCP/443 |
| TCP | Transmission Control Protocol | Connection-oriented Layer 4 protocol |
| TLS | Transport Layer Security | Encryption layer used by HTTPS |
| IAM | Identity and Access Management | AWS identity and permissions system |
| STS | Security Token Service | Issues temporary AWS credentials |
| IMDS | Instance Metadata Service | EC2 metadata and temporary credential endpoint |
| SSM | Systems Manager | AWS management service; Session Manager can replace SSH/bastions |

---

# 3. Public IP vs Private IP

An EC2 instance can have:

```text
Private IP
+
optional Public IP
```

The operating system normally sees the private IP.

AWS handles the mapping between the public IP and the private ENI address.

A public IP alone is not sufficient for internet connectivity.

The subnet also needs a route such as:

```text
0.0.0.0/0 -> IGW
```

A useful model is:

```text
Public IP
+ Internet Gateway
+ route table
+ Security Group
+ NACL
+ application listener
= working public service
```

---

# 4. How Internet Routing Reaches AWS

DNS does not tell packets how to reach an AWS Internet Gateway.

DNS only performs:

```text
hostname -> IP address
```

After DNS resolution, routing happens separately.

The local host normally only knows:

```text
destination is not local
-> send to default gateway
```

Internet routers then use routing information such as **BGP (Border Gateway Protocol)** to forward traffic toward the network advertising the destination IP prefix.

Conceptually:

```text
Laptop
  |
Default Gateway
  |
ISP
  |
Internet routing / BGP
  |
AWS network
  |
Internet Gateway
  |
AWS VPC networking
  |
ENI / EC2
```

AWS advertises public IP prefixes to the internet.

Public routers do not know the internal VPC subnet or private EC2 address.

That mapping is handled inside AWS.

---

# 5. Route Tables

A route table answers:

> Where should traffic go for a particular destination?

Example:

```text
Destination       Target
10.10.0.0/16      local
0.0.0.0/0         igw-...
```

Important:

`DestinationCidrBlock` refers to the packet destination, not the source.

AWS routing uses longest-prefix matching.

The special target:

```text
local
```

represents AWS internal routing inside the VPC.

---

# 6. Public and Private Subnets

A subnet is considered public when its route table contains a direct route:

```text
0.0.0.0/0 -> Internet Gateway
```

A private subnet does not have such a direct route.

Typical private subnet:

```text
10.10.0.0/16 -> local
```

A private EC2 can still communicate with other VPC resources through the local route.

---

# 7. ENI – Elastic Network Interface

An ENI is AWS's virtual network interface.

It can contain or be associated with:

- Private IP addresses
- Public IP mapping
- MAC address
- Security Groups
- Subnet placement

Conceptually:

```text
EC2
 |
ENI
 |
Subnet / VPC
```

An EC2 instance can have one or more ENIs.

Other VPC-connected services such as load balancers, RDS, ElastiCache, and EKS worker nodes also use network interfaces.

---

# 8. Security Groups

A Security Group is a stateful firewall associated with an ENI/resource.

Important properties:

```text
Stateful
ALLOW rules only
Resource/ENI level
```

If inbound traffic is allowed, the response is automatically allowed back.

Example:

```text
Inbound:
TCP/22 from MY_PUBLIC_IP/32
```

means SSH is allowed only from that exact public IPv4 address.

`/32` represents exactly one IPv4 address.

For HTTP:

```text
TCP/80 from 0.0.0.0/0
```

means HTTP is allowed from any IPv4 address.

Security Groups can also reference other Security Groups.

Example:

```text
private-ec2-sg

Inbound:
TCP/22
Source = bastion-sg
```

This means SSH to the private instance is allowed from resources associated with `bastion-sg`.

---

# 9. Multiple Security Groups on One ENI

An ENI can have multiple Security Groups.

Example:

```text
Public EC2 ENI
 |
 +-- bastion-sg
 |     SSH/22 from MY_PUBLIC_IP/32
 |
 +-- web-sg
       HTTP/80 from 0.0.0.0/0
```

AWS effectively combines the ALLOW rules.

However, when using:

```bash
aws ec2 modify-network-interface-attribute \
  --network-interface-id <ENI_ID> \
  --groups <SG_ID>
```

the supplied group list becomes the complete Security Group list for that ENI.

It does not append the new SG automatically.

This caused the earlier HTTP SG to be removed when only `bastion-sg` was supplied.

---

# 10. Bastion Host

The public EC2 acted as a bastion host.

The private EC2 had no public IP.

Traffic path:

```text
Laptop
  |
  | SSH over internet
  v
Public EC2 / Bastion
  |
  | VPC local routing
  v
Private EC2
```

The private EC2 Security Group allowed SSH only from the bastion Security Group.

SSH through the bastion was performed using a ProxyCommand:

```bash
ssh \
  -i /home/singh/devops-lab-key.pem \
  -o "ProxyCommand=ssh -i /home/singh/devops-lab-key.pem -W %h:%p ec2-user@<PUBLIC_EC2_IP>" \
  ec2-user@<PRIVATE_EC2_IP>
```

The private key remained on the local machine.

It was not copied to the bastion.

---

# 11. SSH Authentication Failure Incident

The first private EC2 was launched without:

```bash
--key-name devops-lab-key
```

The network path worked, but SSH returned:

```text
Permission denied (publickey)
```

This was an important troubleshooting signal.

It meant:

```text
routing works
Security Groups work
TCP/22 reaches sshd
but authentication fails
```

The instance was recreated with the correct EC2 key pair.

After that, SSH through the bastion worked.

---

# 12. NAT Gateway

NAT stands for **Network Address Translation**.

A NAT Gateway allows private instances to initiate outbound IPv4 internet connections without exposing them directly to inbound internet connections.

Architecture:

```text
Private EC2
  |
Private Route Table
0.0.0.0/0 -> NAT Gateway
  |
NAT Gateway in Public Subnet
  |
Public Route Table
0.0.0.0/0 -> IGW
  |
Internet
```

The NAT Gateway has an Elastic IP.

For outbound traffic it performs source address translation:

```text
Private EC2 private IP
        |
        v
NAT Gateway
        |
source rewritten to NAT public EIP
        |
        v
Internet
```

Return traffic is mapped back using NAT connection state.

The private EC2 itself still has no public IP.

---

# 13. Why NAT Gateway Still Needs an Internet Gateway

A NAT Gateway gives private resources a public source identity through its Elastic IP.

But the Internet Gateway is still the VPC internet edge.

Therefore:

```text
Private EC2
-> NAT Gateway
-> Internet Gateway
-> Internet
```

The NAT Gateway does not replace the Internet Gateway.

---

# 14. NACL – Network Access Control List

A NACL is a subnet-level traffic filter.

Important properties:

```text
Subnet level
Stateless
ALLOW and DENY rules
Ordered rule evaluation
```

A subnet can be associated with only one NACL at a time.

One NACL can be associated with multiple subnets.

---

# 15. Default NACL

The VPC's default NACL contained:

```text
Inbound:
100     ALLOW ALL
*       DENY ALL

Outbound:
100     ALLOW ALL
*       DENY ALL
```

Because rule 100 matches everything first, the final deny rule is normally never reached.

The public and private subnets were initially both associated with the same default NACL.

---

# 16. Custom NACL

A custom NACL was created.

Immediately after creation:

```text
Inbound:
* DENY ALL

Outbound:
* DENY ALL
```

This is different from the default NACL.

The custom NACL also showed:

```text
IsDefault: false
```

and initially had no subnet associations.

---

# 17. OwnerId

The NACL output contained:

```text
OwnerId: <AWS_ACCOUNT_ID>
```

This is the AWS account ID, not the IAM user that created the NACL.

For example:

```text
arn:aws:iam::<AWS_ACCOUNT_ID>:user/shalu-admin
```

contains both:

```text
AWS account ID
+
IAM user name
```

The IAM user performs the API action.

The AWS account owns the resource.

---

# 18. Custom NACL Inbound Rules

The following rules were created:

```text
100 ALLOW TCP/22 from MY_PUBLIC_IP/32
110 ALLOW TCP/80 from 0.0.0.0/0
*   DENY everything else
```

In AWS output:

```text
Protocol: 6
```

means TCP.

`Egress: false` means inbound.

---

# 19. NACL Rule Evaluation

NACL rules are processed from lowest rule number upward.

Example:

```text
90   DENY TCP/80
100  ALLOW ALL
*    DENY ALL
```

HTTP matches rule 90 first and is denied.

Evaluation stops at the first matching rule.

---

# 20. Stateless NACL Experiment

The custom NACL was associated with the public subnet while outbound traffic still had only the final default DENY rule.

Inbound SSH and HTTP were allowed.

However:

```bash
curl -v --connect-timeout 5 http://<PUBLIC_EC2_IP>
```

timed out.

SSH also timed out.

Reason:

```text
Client ephemeral port -> EC2:80 or EC2:22
              inbound allowed

EC2:80 or EC2:22 -> Client ephemeral port
              outbound denied
```

This experimentally proved:

```text
NACLs are stateless.
```

Both directions must be explicitly allowed.

---

# 21. Ephemeral Ports

A client normally opens a connection from a temporary high-numbered source port.

Example:

```text
Client:52344 -> EC2:80
```

The response is:

```text
EC2:80 -> Client:52344
```

Therefore the outbound NACL must allow the client's ephemeral destination port.

A broad lab rule was created:

```text
TCP 1024-65535
Destination 0.0.0.0/0
ALLOW
```

After this rule was added, SSH recovered.

---

# 22. Why HTTP Still Failed After NACL Fix

SSH started working, but HTTP still failed.

Inspection showed that the public EC2 currently had only:

```text
bastion-sg
```

attached.

That Security Group allowed SSH but did not allow HTTP.

The original HTTP-capable Security Group had been removed earlier when:

```bash
aws ec2 modify-network-interface-attribute \
  --network-interface-id <ENI_ID> \
  --groups $BASTION_SG_ID
```

was used.

The fix was to add TCP/80 to `bastion-sg`.

---

# 23. Timeout vs Connection Refused

After the Security Group allowed HTTP, `curl` changed from:

```text
Connection timed out
```

to:

```text
Connection refused
```

This was a very important troubleshooting clue.

Mental model:

```text
Timeout
-> traffic is probably being silently dropped
-> routing, NACL, SG, firewall, or path issue

Connection refused
-> target host was reached
-> TCP stack rejected connection
-> usually no application is listening on that port
```

---

# 24. Nginx Was Not Installed

The current public EC2 was a newly launched instance.

The previous nginx installation had existed on an older EC2 instance that had already been destroyed.

Therefore:

```bash
sudo systemctl status nginx
```

showed that the nginx service did not exist.

Verification commands:

```bash
rpm -q nginx
```

```bash
which nginx
```

---

# 25. Package Download Failure Due to NACL

Installing nginx:

```bash
sudo dnf -v install -y nginx
```

failed while contacting an Amazon Linux repository over HTTPS.

Example error:

```text
Curl error (28): Timeout was reached
```

The repository used HTTPS:

```text
TCP/443
```

The EC2 initiated the connection as:

```text
EC2:ephemeral-port -> repository:443
```

The custom NACL did not permit all traffic needed for the package repository workflow.

A TCP/443 outbound rule was tried, but the operation still timed out.

For the purpose of this lab, the public subnet was re-associated with the default allow-all NACL.

After restoring the default NACL:

```bash
sudo dnf -v install -y nginx
```

worked successfully.

This confirmed that the custom NACL configuration was the network control causing the package download failure.

---

# 26. Nginx Verification

After installation:

```bash
sudo systemctl start nginx
sudo systemctl enable nginx
```

Local test:

```bash
curl http://localhost
```

External test from WSL:

```bash
curl -v http://<PUBLIC_EC2_IP>
```

Both worked.

---

# 27. Important Troubleshooting Signals Learned

### Timeout

```text
Connection timed out
```

Likely causes:

- Security Group drops traffic
- NACL drops traffic
- route missing
- network path unavailable
- firewall silently drops traffic

### Connection Refused

```text
Connection refused
```

Usually means:

- host is reachable
- network path works
- destination port has no listener

### Permission Denied (publickey)

```text
Permission denied (publickey)
```

Means:

- TCP connection reached SSH server
- routing and firewall path are working
- SSH authentication failed

---

# 28. End-to-End Public HTTP Packet Path

A useful final mental model:

```text
Client
  |
  | DNS resolves hostname if one is used
  v
Public destination IP
  |
Internet routing / BGP
  |
AWS network
  |
IGW - Internet Gateway
  |
VPC routing
  |
Subnet
  |
NACL
  |
ENI
  |
Security Group
  |
EC2 operating system
  |
TCP port 80
  |
nginx/application
```

For HTTPS:

```text
IP
↓
TCP
↓
TLS
↓
HTTP
```

For plain HTTP:

```text
IP
↓
TCP
↓
HTTP
```

---

# 29. Key Mental Models

```text
DNS
= name -> IP
```

```text
Route Table
= where should traffic go?
```

```text
Internet Gateway
= VPC internet edge
```

```text
Security Group
= stateful ENI/resource firewall
```

```text
NACL
= stateless subnet firewall
```

```text
ENI
= virtual network interface
```

```text
NAT Gateway
= outbound IPv4 access for private resources
```

```text
Application listener
= process that must actually accept traffic on the destination port
```

---

# 30. Practical Troubleshooting Order

When an application is unreachable, check approximately in this order:

```text
1. DNS resolution
2. Destination IP
3. Route table
4. Internet Gateway / NAT path
5. NACL
6. Security Group
7. ENI / subnet placement
8. Operating-system firewall
9. Is the process running?
10. Is it listening on the expected IP and port?
11. Application logs
```

Useful commands:

```bash
curl -v http://<IP>
```

```bash
curl -v https://<HOST>
```

```bash
ssh -v user@host
```

```bash
ss -lntp
```

```bash
sudo systemctl status nginx
```

```bash
ip route
```

---

# 31. Main Lessons From the Lab

The most important lesson was that successful connectivity depends on multiple independent layers.

For public HTTP:

```text
route works
AND
NACL allows request and response
AND
Security Group allows request
AND
EC2 is reachable
AND
application is listening
```

A failure at any one of these layers can make the complete request fail.

The failure message helps identify which layer is most likely responsible.

The lab also demonstrated why understanding packet flow is more useful than memorizing AWS service definitions.

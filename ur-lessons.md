# AWS, Cloud Computing, and DevOps Lessons

This guide is a learning path for managing AWS cloud infrastructure as a DevOps or cloud engineer. It uses the Shopease project in this folder as a practical example. Work through the sections in order, practice in a personal AWS account, and keep notes about what you changed and why.

> **Cost reminder:** AWS resources can incur charges while they exist, even when you are not actively using them. Check the current AWS pricing for a service before creating it. Destroy practice infrastructure when you finish, and verify in the AWS Console that paid resources were removed.

## 1. What cloud computing means

Cloud computing means renting computing resources over a network instead of buying and operating all the hardware yourself. AWS provides services through its console, command-line interface (CLI), APIs, and infrastructure-as-code tools such as Terraform.

Learn these basic ideas:

- **On-demand resources:** create or remove resources when workloads need them.
- **Pay for use:** charges depend on the services, sizes, regions, and time used. Some resources also charge for requests or data transfer.
- **Regions and Availability Zones:** a region is a geographic area; an Availability Zone (AZ) is an isolated location within a region. Using multiple AZs can improve availability, but does not protect against every failure.
- **Scalability:** change capacity to meet workload needs. Scaling can be vertical (a larger machine) or horizontal (more machines).
- **Shared responsibility:** AWS secures the underlying cloud infrastructure. You are responsible for how you configure identities, networks, data, operating systems, and applications. The split depends on the service.
- **High availability and disaster recovery:** high availability reduces interruptions; disaster recovery plans how to restore service after a larger failure. They require deliberate design and testing.

### The Shopease request path

```text
Browser -> public Application Load Balancer -> target group -> EC2 instances running Nginx
                                      Auto Scaling Group maintains the EC2 fleet
```

The VPC and subnets provide the network, security groups filter traffic, and the launch template describes new EC2 instances. Terraform records and manages the desired infrastructure configuration.

## 2. Essential networking

Learn these terms before troubleshooting cloud systems:

- **IP address:** identifies a network interface. IPv4 addresses are written as four numbers, such as `10.0.1.5`.
- **CIDR notation:** describes an address range. `10.0.0.0/16` is a larger range than `10.0.1.0/24`.
- **VPC:** a logically isolated AWS network in a region.
- **Subnet:** a range of VPC IP addresses associated with one AZ.
- **Route table:** rules that direct network traffic. A subnet is public when its routes provide a path to an internet gateway and its resources have public addressing as needed; the subnet name alone does not make it public.
- **Internet gateway (IGW):** connects a VPC to the internet when routes and addressing permit it.
- **NAT gateway:** lets private-subnet resources initiate outbound internet connections without accepting unsolicited inbound internet connections. It has ongoing cost.
- **Security group:** stateful virtual firewall attached to a resource's network interface. Inbound and outbound rules specify allowed traffic.
- **Network ACL:** stateless subnet-level filter. It is an additional control and is not a replacement for security groups.
- **DNS:** translates names to addresses. The ALB provides a DNS name clients can use.
- **Port and protocol:** for example, HTTP commonly uses TCP port 80 and HTTPS commonly uses TCP port 443.

In this project, the ALB security group accepts HTTP from the internet. The EC2 security group accepts HTTP only from the ALB security group. This limits direct web access to the instances. The current public subnets also assign public IPv4 addresses to launched instances, which is convenient for a class project but is not required for a production design. A common production pattern puts application instances in private subnets and provides controlled outbound access, such as through NAT or VPC endpoints.

### Networking practice

1. Draw the request path and label each security group, route, subnet, AZ, port, and protocol.
2. Explain why an internet gateway alone does not make a subnet public.
3. Explain why a security group rule allowing traffic from another security group is often safer than allowing it from every IP.
4. Use the VPC console or AWS CLI to inspect routes and security group rules. Do not change production rules as a learning exercise.

## 3. Identity and access management (IAM)

IAM controls who can do what in AWS.

- **Principal:** a user, role, or AWS service making a request.
- **Policy:** a document describing allowed or denied actions on resources, optionally under conditions.
- **Role:** an identity that can be assumed temporarily. Workloads and human users should generally use roles and short-lived credentials where possible.
- **Least privilege:** grant only the access needed for a task, for only as long as it is needed.
- **MFA:** adds a second authentication factor to help protect accounts.
- **Credential hygiene:** never commit access keys, passwords, private SSH keys, or state files containing secrets to Git.

For local Terraform use, configure the AWS CLI with an appropriate named profile or use your organization's identity federation. Do not paste credentials into Terraform files, shell scripts, or source control. Give Terraform's identity only the permissions needed to manage the project's resources. Avoid using the account root identity for routine work.

Useful initial setup and inspection commands:

```powershell
aws configure --profile shopease
aws sts get-caller-identity --profile shopease
```

The identity command helps confirm which AWS account and principal your CLI will use. Set a profile for Terraform by using the standard AWS profile environment variable in your shell, or by configuring a profile in the AWS provider. Do not print or share credentials when troubleshooting.

## 4. Linux and web server basics

The EC2 machine runs Ubuntu Linux. Learn enough Linux to inspect startup, storage, networking, and services:

```bash
whoami
hostname
df -h
free -h
ip addr
ip route
systemctl status nginx --no-pager
journalctl -u nginx --no-pager -n 100
curl -I http://localhost/
```

The `ec2-script.sh` file is EC2 user data. On first boot it updates package metadata, installs Nginx and Git, downloads the website, copies it into `/var/www/html`, sets file ownership and permissions, and enables and starts Nginx. It writes output to `/var/log/shopease-user-data.log`. Cloud-init also records logs under `/var/log/`.

User data is useful for bootstrapping, but long installs can make instance startup slower and external downloads can fail. For production, consider building versioned machine images, using a deployment system, and making deployments repeatable and observable. Avoid putting secrets in user data: it can be accessible through instance metadata and management interfaces.

### Storage concepts

- **EBS volume:** persistent block storage attached to an EC2 instance, normally in the same AZ as that instance.
- **Root volume:** the boot disk holding the operating system. This project configures it as an encrypted 20 GiB `gp3` volume in the launch template.
- **Ephemeral instance storage:** local storage tied to the lifetime of certain instance types; it is not a substitute for durable data storage.
- **S3:** object storage for files and backups, accessed through APIs rather than mounted as a normal block disk by default.
- **Snapshots:** point-in-time EBS backups stored by AWS. Backups need retention, access controls, and restore tests.

The ASG can replace an instance at any time. Treat instance-local data as disposable unless you have designed and tested a separate persistence strategy. The launch template disk setting applies to newly launched instances; changing it does not automatically enlarge every existing instance's filesystem.

## 5. Terraform and infrastructure as code

Infrastructure as code (IaC) describes infrastructure in files so that changes can be reviewed, repeated, and tracked. Terraform compares the configuration with its state and the real infrastructure, then proposes actions.

### Terraform building blocks

- **Provider:** plugin that talks to a platform, here AWS.
- **Resource:** infrastructure Terraform creates or manages, such as `aws_vpc` or `aws_lb`.
- **Data source:** reads information managed elsewhere, such as the latest matching Ubuntu AMI.
- **Input variable:** configurable value, such as `aws_region` or `root_volume_size`.
- **Output:** value Terraform displays, such as the ALB URL.
- **Reference:** an expression such as `aws_vpc.shopease_vpc.id`; references also create dependency ordering.
- **State:** Terraform's record of managed resources and their attributes. State can contain sensitive data. Protect it and do not publish it.
- **Plan:** preview of proposed infrastructure changes.
- **Apply:** performs the approved plan.
- **Module:** reusable group of Terraform configuration.
- **Provider lock file:** records provider selections and checksums for repeatable installs.

### Safe Terraform workflow

From the project folder, after configuring AWS credentials and installing Terraform:

```powershell
terraform fmt -check
terraform init
terraform validate
terraform plan
terraform apply
```

Read the plan before applying. Pay attention to resources marked for replacement or deletion, unexpected instance counts, and public network exposure. `terraform apply` changes real AWS resources and may incur charges. When prompted, approve only a plan you understand.

For a disposable practice environment, after checking the plan and confirming it contains only resources you intend to remove:

```powershell
terraform plan -destroy
terraform destroy
```

Do not destroy shared or production infrastructure. Terraform state should be backed up and access-controlled. For a team, use a secured remote backend with state locking and encryption, such as an appropriately configured S3 backend. Never edit state by hand unless following a deliberate recovery procedure.

### Change exercises using this project

1. Change `root_volume_size` through a variable value and inspect the plan. Identify which launch template version changes and what happens to existing instances.
2. Change `desired_capacity` and explain the cost and availability effect.
3. Add a variable for the AWS region, then make subnet AZ selection consistent with that region.
4. Add tags consistently to resources for ownership, environment, and cost reporting.
5. Inspect Terraform's dependency graph and explain why the ALB waits for the subnets and security group.
6. Move networking into a module only after you can explain the current resource references and state implications.

## 6. Compute, load balancing, and scaling

- **EC2:** virtual machines with a selected AMI, instance type, network settings, storage, and IAM role.
- **AMI:** machine image used to launch an instance. This project looks up the latest matching Canonical Ubuntu 24.04 x86_64 image.
- **Launch template:** reusable instance settings, including the AMI, type, key pair, security group, user data, and root disk.
- **Application Load Balancer (ALB):** Layer 7 load balancer for HTTP and HTTPS. It accepts client traffic and routes it to targets.
- **Listener:** port and protocol where the ALB accepts requests, plus rules for routing them.
- **Target group:** collection of back-end targets and their health check configuration.
- **Health check:** request used to decide whether a target can receive traffic. A running EC2 instance is not necessarily a healthy web target.
- **Auto Scaling Group (ASG):** maintains a desired number of instances and can replace unhealthy instances.
- **Target tracking:** scaling policy that adjusts capacity to keep a metric near a target. This project targets average CPU utilization of 50%.

The ASG spans two AZs, aims for two instances, and permits one to three instances. The ALB listener forwards HTTP requests to the target group. The target group checks `/` and accepts status codes 200–399. These settings are a learning baseline, not a universal production capacity or security recommendation.

### Troubleshooting a 502 response

An ALB 502 often means it could not get a valid response from a target. Trace the path in order:

1. Does the ALB DNS name resolve, and does the listener exist on port 80?
2. Is the target group associated with the listener?
3. Are targets registered and healthy? Read the health-check reason.
4. Does the EC2 security group permit HTTP from the ALB security group?
5. Is Nginx running and listening on port 80?
6. Did user data complete? Inspect cloud-init and Shopease logs.
7. Can the instance reach the package and source repositories it needs during boot?
8. Did a recent launch template change create a new version, and are instances actually using it?

Useful AWS CLI inspection commands (after configuring the CLI and selecting the correct region/profile):

```powershell
aws elbv2 describe-target-health --target-group-arn <target-group-arn>
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names shopease-asg
aws ec2 describe-instances --filters Name=tag:Project,Values=shopease
```

Replace placeholders with actual values. Avoid terminating instances as a first response. Use health reasons and logs to find the cause, then let the ASG replace an instance only when replacement is appropriate.

## 7. DevOps practices

DevOps combines development and operations practices so software can be delivered reliably. It is a culture and set of workflows, not just a tool.

- **Version control:** use Git branches and small commits; review changes before merging.
- **CI (continuous integration):** automatically checks changes, such as formatting, linting, and tests.
- **CD (continuous delivery/deployment):** packages and releases changes through controlled environments.
- **Artifact:** versioned build output, such as a container image or machine image.
- **Pipeline:** automated steps that build, test, scan, and deploy an artifact.
- **Environment promotion:** move the same tested artifact through development, staging, and production with controlled configuration.
- **Rollback:** restore a known-good version when a deployment causes problems.
- **Infrastructure review:** inspect Terraform plans in code review before changes are applied.
- **Immutable deployment:** replace instances with instances built from a known version rather than making undocumented changes by hand.

For this project, a useful next CI pipeline could run Terraform formatting and validation on pull requests. A later deployment pipeline could build a versioned artifact, deploy it to a test environment, check health, and then promote it. Use short-lived AWS credentials from the CI identity provider and restrict the pipeline role's permissions.

## 8. Security foundations

Use these habits from the beginning:

1. Enable MFA for human AWS access and use roles or identity federation where possible.
2. Follow least privilege for IAM permissions.
3. Keep secrets out of Git, images, user data, logs, and Terraform variables committed to the repository.
4. Encrypt data in transit with HTTPS and at rest where supported; manage encryption keys deliberately.
5. Keep operating systems and dependencies patched; rebuild and replace instances in a controlled way.
6. Limit public network access. Expose only required ports and use private subnets for workloads when practical.
7. Log administrative and application activity, restrict log access, and define retention.
8. Back up important data and test restoration, not just backup creation.
9. Scan code, dependencies, container images, and infrastructure configuration.
10. Review AWS security findings and remediate based on risk and business impact.

This project's SSH key pair registers a public key, but it does not itself open SSH access: the EC2 security group currently has no port 22 ingress. For administration, prefer Systems Manager Session Manager with a suitable instance role and network access. If SSH is deliberately configured, restrict the source to a trusted address and remove temporary access afterward.

## 9. Observability and incident response

Observability helps you understand what a system is doing from its outputs:

- **Metrics:** numerical measurements over time, such as CPU, request count, latency, and error rate.
- **Logs:** event records from applications, operating systems, and AWS services.
- **Traces:** follow one request across multiple services.
- **Alerts:** notify a person or system when a meaningful condition needs action.
- **Dashboard:** presents operational signals in one place.
- **Runbook:** clear steps for diagnosing and responding to a known issue.

Start with questions the system must answer: Is the site reachable? Are ALB targets healthy? Is latency rising? Are errors increasing? Is the ASG replacing instances? Are costs or capacity unexpectedly high? Use CloudWatch metrics and alarms, ALB access logs where appropriate, and centralized application logs. Avoid collecting secrets or unnecessary personal data in logs.

During an incident, establish impact, inspect recent changes and health signals, mitigate safely, communicate status, and record a timeline. Afterward, identify contributing causes and improve automation, monitoring, or documentation. Avoid blame; focus on making the system easier to operate.

## 10. Reliability and architecture

Design around failure instead of assuming components never fail:

- Use multiple AZs for appropriate components.
- Keep application instances replaceable and avoid relying on local instance state.
- Define health checks that test useful behavior without being too fragile.
- Set capacity limits and understand what happens when maximum capacity is reached.
- Document recovery objectives: **RTO** is the target time to restore service; **RPO** is the acceptable amount of data loss measured in time.
- Test backups, replacement, and recovery procedures.
- Reduce deployment risk with health gates, gradual rollout, and rollback options.
- Understand dependencies such as DNS, certificates, identity, package repositories, and external APIs.

The current Shopease site is static, so a more durable future design could serve static assets from S3 behind CloudFront, with TLS certificates and a controlled deployment pipeline. That is an architectural exercise, not a required change to this EC2 learning project.

## 11. Cost management

Cloud cost is an operational responsibility. Before and after a lab:

- Estimate expected costs using AWS pricing information for your region and usage.
- Set a budget and billing alerts; alerts may not stop resources automatically.
- Tag resources with project, owner, and environment where appropriate.
- Stop or destroy unused resources. Stopped EC2 instances may still have EBS and other charges.
- Watch for load balancers, NAT gateways, public IPv4 addresses, snapshots, and data transfer charges.
- Choose instance and storage sizes based on measured needs, then review them regularly.
- Use Cost Explorer and billing tools to investigate unexpected spending.

For the Shopease configuration, the ALB, EC2 instances, EBS root disks, public IPv4 addresses, and network traffic may all affect cost. Scaling activity can change the bill.

## 12. A practical learning roadmap

### Stage 1: Foundations

- Learn Linux shell basics, Git, IP/CIDR, DNS, HTTP, TLS, and JSON.
- Draw the Shopease architecture and explain each component aloud.
- Set up AWS CLI access safely and confirm the active identity.

### Stage 2: Terraform

- Read `main.tf`, `variable.tf`, and `ec2-script.sh` line by line.
- Run `terraform fmt -check`, `terraform validate`, and `terraform plan`.
- Practice changing a variable and reading the plan before applying.
- Learn state protection, remote backends, locking, and module design.

### Stage 3: AWS operations

- Inspect EC2, VPC, ALB, target group, and ASG state in both the console and CLI.
- Diagnose an unhealthy target using health reasons and instance logs.
- Configure CloudWatch alarms and create a short runbook.
- Practice backup and recovery with noncritical data.

### Stage 4: Delivery and security

- Add CI checks for formatting, validation, and security scanning.
- Use a controlled deployment process and versioned artifacts.
- Use IAM roles and short-lived credentials for automation.
- Add HTTPS, logging, monitoring, and a tested rollback plan.

### Stage 5: Production design

- Compare EC2, containers, and serverless options for a workload.
- Design private networking, identity, data protection, resilience, and recovery.
- Estimate cost and capacity; review actual metrics after deployment.
- Document architecture decisions, service ownership, and incident procedures.

## 13. Glossary

| Term | Meaning |
| --- | --- |
| AWS | Amazon Web Services, a cloud service provider. |
| AZ | Availability Zone, an isolated location within an AWS region. |
| CIDR | Notation describing an IP address range, such as `10.0.0.0/16`. |
| EC2 | AWS virtual machine service. |
| EBS | Persistent block storage for EC2. |
| IAM | AWS identity and access management service. |
| IaC | Infrastructure as code: managing infrastructure through versioned configuration. |
| AMI | Machine image used to launch EC2 instances. |
| ALB | Application Load Balancer for HTTP/HTTPS application traffic. |
| ASG | Auto Scaling Group that maintains and scales a fleet of EC2 instances. |
| S3 | AWS object storage service. |
| VPC | Virtual Private Cloud, an isolated AWS network. |
| RTO | Recovery Time Objective: target time to restore a service. |
| RPO | Recovery Point Objective: acceptable data loss measured in time. |
| CI/CD | Continuous integration and continuous delivery or deployment. |

## 14. Keep learning

Cloud services, pricing, and best practices change. For real deployments, check current AWS documentation, service quotas, regional availability, and pricing. Treat this guide as a study plan and the project as a practice environment; always review the live Terraform plan and AWS account before making changes.

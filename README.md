# Shopease

Shopease is a static website served by Nginx on Ubuntu EC2 instances. An AWS
Application Load Balancer (ALB) accepts public HTTP traffic and forwards it to
instances managed by an Auto Scaling Group (ASG).

## Website URL

Use Terraform to print the current public URL:

```powershell
terraform output -raw application_url
```

The site is currently served over HTTP, not HTTPS.

## How the deployment works

1. Terraform creates a VPC, two public subnets, an internet gateway, and routing.
2. Terraform creates an internet-facing ALB with an HTTP listener on port 80.
3. The ALB forwards requests to an EC2 target group on port 80.
4. The ASG launches Ubuntu EC2 instances from the launch template.
5. EC2 user data runs [`ec2-script.sh`](./ec2-script.sh), which installs Nginx
   and Git, clones the website, copies it into `/var/www/html`, and starts Nginx.
6. The ALB checks `GET /` on each instance. A target must return HTTP 200-399 to
   become healthy.

The ALB security group allows public HTTP traffic. The EC2 security group only
allows HTTP traffic from the ALB security group.

## What caused the Bad Gateway

The browser showed **502 Bad Gateway** because the ALB had no healthy web
server to forward the request to.

The EC2 user-data script had a blank line before its `#!/bin/bash` interpreter
line. A script's interpreter line must be the first line, starting at the very
first byte of the file. With the blank line before it, cloud-init could not
execute the script as intended. Nginx was not installed or started, so the
instances did not answer the ALB health checks.

The ALB reported `Target.FailedHealthChecks`, and the EC2 cloud-init logs showed
that the `scripts_user` module failed. The script was corrected so that
`#!/bin/bash` is the first line.

Running `terraform apply` published the changed user data as a new launch
template version, but did not itself replace every already-running instance.
The old instances had to be replaced by the ASG so that they would start with
the corrected user data.

## Troubleshooting steps

### 1. Confirm the public endpoint and response

From the project directory:

```powershell
terraform output -raw application_url
```

Open the printed URL in a browser. To check the HTTP status from PowerShell:

```powershell
try {
  $response = Invoke-WebRequest -Uri (terraform output -raw application_url) -UseBasicParsing
  "HTTP $($response.StatusCode)"
} catch {
  $_.Exception.Message
}
```

Typical meanings:

- **HTTP 200**: the ALB returned a page successfully.
- **HTTP 502**: the ALB could not get a usable response from a backend target.
- **Timeout / connection failure**: check the ALB address, listener, public
  subnet routing, and ALB security group.

### 2. Check ALB target health

In the AWS Console, open **EC2 → Target Groups → `shopease-tg` → Targets**.
Inspect the target state and its health-check reason.

With AWS CLI, get the target group ARN and health details:

```powershell
$targetGroupArn = aws elbv2 describe-target-groups `
  --names shopease-tg `
  --query 'TargetGroups[0].TargetGroupArn' `
  --output text

aws elbv2 describe-target-health `
  --target-group-arn $targetGroupArn `
  --output table
```

Wait for newly launched targets to finish registration and health checks.
`initial` or `registration in progress` is not necessarily a failure. A target
that remains `unhealthy` needs further investigation; use the displayed reason
rather than repeatedly terminating instances.

### 3. Check the ASG and launch template

In the AWS Console, open **EC2 → Auto Scaling Groups → `shopease-asg`**. Check
that the group has its expected capacity and that its in-service instances use
the latest launch-template version.

With AWS CLI:

```powershell
aws autoscaling describe-auto-scaling-groups `
  --auto-scaling-group-names shopease-asg `
  --query 'AutoScalingGroups[0].{Desired:DesiredCapacity,Instances:Instances[*].{Id:InstanceId,Health:HealthStatus,Lifecycle:LifecycleState,Version:LaunchTemplate.Version}}' `
  --output json
```

An EC2 instance can be running while its web server is not working. Check both
the ASG health and the target-group health.

### 4. Check EC2 user-data and Nginx

For an instance that remains unhealthy, inspect its boot logs:

- `/var/log/cloud-init-output.log`
- `/var/log/cloud-init.log`
- `/var/log/shopease-user-data.log`

The first two are cloud-init logs. The Shopease log is created by the startup
script after it begins running. If it does not exist, user data may not have
started.

If you can connect using AWS Systems Manager Session Manager or SSH, check:

```bash
sudo cloud-init status --long
sudo systemctl status nginx --no-pager
sudo ss -lntp | grep ':80'
curl -I http://localhost/
```

Use Session Manager where available. If using SSH, allow port 22 only from a
trusted IP address temporarily; never open SSH to `0.0.0.0/0`. Remove the
temporary rule when finished.

### 5. Validate and apply Terraform changes

After changing the Terraform configuration or user-data script:

```powershell
terraform validate
terraform plan
terraform apply
```

Review the plan before approving it. Terraform may update a launch template
without replacing existing instances. Check the ASG and target group afterward.

If an old instance is still unhealthy after a fix has been applied, terminate
only that confirmed unhealthy ASG member and keep desired capacity unchanged so
the group launches a replacement:

```powershell
aws autoscaling terminate-instance-in-auto-scaling-group `
  --instance-id i-REPLACE_WITH_UNHEALTHY_INSTANCE_ID `
  --no-should-decrement-desired-capacity
```

Do not terminate all instances at once. Wait for at least one replacement to
become `healthy` before taking any further action. If new instances also fail,
stop replacing them and inspect their logs and health-check reason.

### 6. Confirm recovery

Recovery is confirmed when:

1. The target group shows the current instances as **Healthy**.
2. The public application URL returns **HTTP 200**.
3. The home page and its assets load in a browser.

During the recovery for this incident, both replacement targets became healthy
and a request to the ALB returned HTTP 200.

## Ask someone else to check the site

Send your friend this message:

> Could you check my Shopease website? Open
> http://shopease-alb-1899170923.us-east-1.elb.amazonaws.com and tell me whether
> the home page and images load. If it does not work, please send me a
> screenshot, the approximate time you tried, and the exact error you saw.

They can also try another browser or a phone using mobile data. If it still
fails, ask them to report whether they saw a **502 Bad Gateway**, a blank page,
or a browser connection error.

## Project files

- [`main.tf`](./main.tf) — AWS provider, networking, security groups, ALB,
  target group, launch template, ASG, scaling policy, and application URL output.
- [`variable.tf`](./variable.tf) — AWS region, project name, instance type, and
  Ubuntu AMI owner variables.
- [`ec2-script.sh`](./ec2-script.sh) — EC2 user-data bootstrap script that
  deploys the site and starts Nginx.
- `terraform.tfstate` — Terraform's local state. **Do not publish or share this
  file**; state can contain sensitive infrastructure details.

## Important notes

- The application currently uses public HTTP and has no HTTPS certificate.
- Terraform apply and AWS instance replacement can incur AWS charges.
- Do not share AWS credentials, private SSH keys, or the Terraform state file.

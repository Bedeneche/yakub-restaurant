# Terraform and provider setup: tells Terraform which AWS plugin version to use.
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.69.1" # Pins the AWS provider version for consistent behavior.
    }
  }
}

# AWS provider: configures the region where resources are created.
provider "aws" {
  region = var.aws_region # Reads the region from variable.tf.
}

# Networking: creates the isolated virtual network for Shopease.
resource "aws_vpc" "shopease_vpc" {
  cidr_block           = "10.0.0.0/16" # Private IP address range available inside this VPC.
  enable_dns_support   = true           # Allows resources in the VPC to use DNS resolution.
  enable_dns_hostnames = true           # Gives eligible instances DNS hostnames.

  tags = {
    Name = "shopease-vpc"
  }
}


# Public subnets: place resources in separate Availability Zones for availability.
resource "aws_subnet" "shopease_public_a" {
  vpc_id                  = aws_vpc.shopease_vpc.id # Places this subnet inside the Shopease VPC.
  cidr_block              = "10.0.1.0/24"           # IP range assigned to this subnet.
  availability_zone       = "us-east-1a"            # First Availability Zone.
  map_public_ip_on_launch = true                    # Automatically gives launched instances public IPv4 addresses.

  tags = {
    Name = "shopease-public-a"
  }
}


resource "aws_subnet" "shopease_public_b" {
  vpc_id                  = aws_vpc.shopease_vpc.id # Places this subnet inside the Shopease VPC.
  cidr_block              = "10.0.2.0/24"           # A different IP range from subnet A.
  availability_zone       = "us-east-1b"            # Second Availability Zone for redundancy.
  map_public_ip_on_launch = true                    # Automatically gives launched instances public IPv4 addresses.

  tags = {
    Name = "shopease-public-b"
  }
}


# Internet gateway: provides the VPC a path to and from the public internet.
resource "aws_internet_gateway" "shopease_igw" {
  vpc_id = aws_vpc.shopease_vpc.id # Attaches the gateway to this VPC.

  tags = {
    Name = "shopease-igw"
  }
}


# Public route table: directs internet-bound subnet traffic through the gateway.
resource "aws_route_table" "shopease_public_rt" {
  vpc_id = aws_vpc.shopease_vpc.id # Creates this route table in the Shopease VPC.

  route {
    cidr_block = "0.0.0.0/0"                         # Matches traffic going to any IPv4 address.
    gateway_id = aws_internet_gateway.shopease_igw.id # Sends matching traffic through the internet gateway.
  }

  tags = {
    Name = "shopease-public-rt"
  }
}


# Associates the public route table with each public subnet.
resource "aws_route_table_association" "shopease_public_a" {
  subnet_id      = aws_subnet.shopease_public_a.id       # Applies the public route table to subnet A.
  route_table_id = aws_route_table.shopease_public_rt.id # The route table containing the internet route.
}

resource "aws_route_table_association" "shopease_public_b" {
  subnet_id      = aws_subnet.shopease_public_b.id       # Applies the public route table to subnet B.
  route_table_id = aws_route_table.shopease_public_rt.id # The route table containing the internet route.
}


# ALB security group: permits public HTTP requests and allows outbound responses.
resource "aws_security_group" "shopease_alb_sg" {
  name        = "shopease-alb-sg"
  description = "Allow HTTP traffic to the Shopease load balancer"
  vpc_id      = aws_vpc.shopease_vpc.id

  ingress {
    description = "Allow HTTP from website visitors"
    from_port   = 80            # Start of the allowed TCP port range.
    to_port     = 80            # End of the allowed TCP port range (HTTP).
    protocol    = "tcp"         # Applies this rule to TCP traffic.
    cidr_blocks = ["0.0.0.0/0"] # Accepts HTTP from any IPv4 address.
  }

  egress {
    from_port   = 0             # AWS ignores port values when all protocols are selected.
    to_port     = 0             # AWS ignores port values when all protocols are selected.
    protocol    = "-1"          # Allows all outbound protocols.
    cidr_blocks = ["0.0.0.0/0"] # Allows outbound traffic to any IPv4 address.
  }

  tags = {
    Name = "shopease-alb-sg"
  }
}


# EC2 security group: accepts HTTP only from the ALB, keeping instances behind it.
resource "aws_security_group" "shopease_ec2_sg" {
  name        = "shopease-ec2-sg"
  description = "Allow web traffic from the Shopease load balancer"
  vpc_id      = aws_vpc.shopease_vpc.id

  ingress {
    description     = "Allow HTTP from the load balancer"
    from_port       = 80                                      # Allows HTTP on port 80.
    to_port         = 80                                      # Keeps the allowed port range to HTTP only.
    protocol        = "tcp"                                   # Applies this rule to TCP traffic.
    security_groups = [aws_security_group.shopease_alb_sg.id] # Allows requests from the ALB security group only.
  }

  egress {
    from_port   = 0             # AWS ignores port values when all protocols are selected.
    to_port     = 0             # AWS ignores port values when all protocols are selected.
    protocol    = "-1"          # Allows all outbound protocols.
    cidr_blocks = ["0.0.0.0/0"] # Allows instances to reach any IPv4 destination, such as package repositories.
  }

  tags = {
    Name = "shopease-ec2-sg"
  }
}


# Key pair: registers the local SSH public key with AWS for optional instance access.
resource "aws_key_pair" "shopease_key" {
  key_name   = "shopease-key" # Name assigned to the public key in AWS.
  public_key = trimspace(file(pathexpand("~/.ssh/id_ed25519.pub"))) # Reads and trims the local public key file.

  tags = {
    Name = "shopease-key"
  }
}



# Ubuntu AMI lookup: selects the latest matching Ubuntu 24.04 machine image.
data "aws_ami" "ubuntu" {
  most_recent = true                # Chooses the newest image matching all filters below.
  owners      = [var.ubuntu_ami_owner] # Restricts results to Canonical's AWS account.

  filter {
    name   = "name" # Filters by AMI name.
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"] # Ubuntu 24.04 Noble, 64-bit server images.
  }

  filter {
    name   = "virtualization-type" # Filters by virtualization technology.
    values = ["hvm"]               # Selects hardware virtual machine images.
  }

  filter {
    name   = "architecture" # Filters by processor architecture.
    values = ["x86_64"]     # Matches the x86_64 instance architecture.
  }
}


# Launch template: defines how the Auto Scaling Group creates each web server.
resource "aws_launch_template" "shopease_web" {
  name_prefix   = "shopease-web-"             # Prefix for generated launch template names.
  image_id      = data.aws_ami.ubuntu.id       # Ubuntu image selected by the AMI lookup above.
  instance_type = var.instance_type            # EC2 size, configured in variable.tf.
  key_name      = aws_key_pair.shopease_key.key_name # Registered SSH key pair name.

  # Configures the EC2 instance's root disk, where Ubuntu and the web server run.
  block_device_mappings {
    device_name = "/dev/sda1" # Linux device name used for the root disk.

    ebs {
      volume_size           = var.root_volume_size # Disk capacity in GiB, set in variable.tf.
      volume_type           = "gp3"                # General-purpose SSD type for balanced cost and performance.
      delete_on_termination = true                  # Remove this disk when its EC2 instance is terminated.
      encrypted             = true                  # Encrypt data stored on this EBS disk.
    }
  }

  vpc_security_group_ids = [
    aws_security_group.shopease_ec2_sg.id # Applies the EC2 rules that allow HTTP from the ALB.
  ]

  user_data = base64encode(
    file("${path.module}/ec2-script.sh") # Reads the startup script from this Terraform module's directory.
  )

  tag_specifications {
    resource_type = "instance" # Applies these tags to instances launched from this template.

    tags = {
      Name    = "shopease-web-server"
      Project = var.project_name
    }
  }
}


# Target group: tracks web servers and routes ALB requests to healthy instances.
resource "aws_lb_target_group" "shopease_tg" {
  name     = "shopease-tg"           # AWS name for this group of web targets.
  port     = 80                       # Sends requests to web servers on HTTP port 80.
  protocol = "HTTP"                  # Uses unencrypted HTTP between ALB and instances.
  vpc_id   = aws_vpc.shopease_vpc.id # Limits targets to this VPC.

  health_check {
    enabled             = true             # Turns on regular health checks.
    path                = "/"              # Requests the website home page.
    protocol            = "HTTP"           # Checks the target over HTTP.
    port                = "traffic-port"  # Checks the same port used for target traffic.
    matcher             = "200-399"        # Treats HTTP responses 200 through 399 as healthy.
    interval            = 30               # Runs a check every 30 seconds.
    timeout             = 5                # Waits up to 5 seconds for a response.
    healthy_threshold   = 2                # Requires two passing checks to mark a target healthy.
    unhealthy_threshold = 3                # Requires three failing checks to mark a target unhealthy.
  }

  tags = {
    Name    = "shopease-tg"
    Project = var.project_name
  }
}


# Application Load Balancer: public entry point for website traffic.
resource "aws_lb" "shopease_alb" {
  name               = "shopease-alb"                              # AWS name for the load balancer.
  internal           = false                                       # Gives it a public internet-facing address.
  load_balancer_type = "application"                              # Supports HTTP/HTTPS application traffic.
  security_groups    = [aws_security_group.shopease_alb_sg.id]      # Applies the ALB's public HTTP access rules.

  subnets = [
    aws_subnet.shopease_public_a.id, # Places ALB nodes in the first Availability Zone.
    aws_subnet.shopease_public_b.id  # Places ALB nodes in the second Availability Zone.
  ]

  tags = {
    Name    = "shopease-alb"
    Project = var.project_name
  }
}


# HTTP listener: accepts browser requests and forwards them to the target group.
resource "aws_lb_listener" "shopease_http" {
  load_balancer_arn = aws_lb.shopease_alb.arn # Attaches this listener to the ALB.
  port              = 80                      # Listens for standard HTTP traffic.
  protocol          = "HTTP"                  # Uses HTTP; HTTPS is not configured here.

  default_action {
    type             = "forward"                        # Forwards accepted requests to targets.
    target_group_arn = aws_lb_target_group.shopease_tg.arn # Selects the Shopease web server target group.
  }

  tags = {
    Name    = "shopease-http-listener"
    Project = var.project_name
  }
}


# Auto Scaling Group: maintains web server capacity across the public subnets.
resource "aws_autoscaling_group" "shopease_asg" {
  name             = "shopease-asg" # AWS name for the group.
  min_size         = 1               # Keeps at least one instance running.
  desired_capacity = 2               # Aims to keep two instances running normally.
  max_size         = 3               # Allows scaling up to three instances.
  vpc_zone_identifier = [
    aws_subnet.shopease_public_a.id, # Allows instances to launch in the first zone.
    aws_subnet.shopease_public_b.id  # Allows instances to launch in the second zone.
  ]

  target_group_arns = [
    aws_lb_target_group.shopease_tg.arn # Registers instances with the ALB target group.
  ]

  launch_template {
    id      = aws_launch_template.shopease_web.id # Uses the Shopease web server launch template.
    version = "$Latest"                            # Uses its newest version for new instances.
  }

  health_check_type         = "ELB" # Uses load balancer health checks to assess instance health.
  health_check_grace_period = 300   # Allows 5 minutes for a new instance to start the web server.

  wait_for_capacity_timeout = "0" # Does not make Terraform wait for the group to reach desired capacity.

  tag {
    key                 = "Name"                    # Tag key identifying the instance name.
    value               = "shopease-asg-instance"   # Name tag value applied to each launched instance.
    propagate_at_launch = true                       # Copies this tag to instances at launch.
  }

  tag {
    key                 = "Project"            # Tag key used to group resources by project.
    value               = var.project_name     # Gets the project label from variable.tf.
    propagate_at_launch = true                 # Copies this tag to instances at launch.
  }
}


# CPU scaling policy: adjusts the number of instances to keep average CPU near 50%.
resource "aws_autoscaling_policy" "shopease_cpu_scaling" {
  name                   = "shopease-cpu-scaling"                   # AWS name for this scaling policy.
  policy_type            = "TargetTrackingScaling"                   # Lets AWS add or remove instances automatically.
  autoscaling_group_name = aws_autoscaling_group.shopease_asg.name   # Applies the policy to the Shopease ASG.

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization" # Tracks average CPU use across the group.
    }

    target_value = 50.0 # Adds or removes capacity to keep average CPU near 50 percent.
  }
}

# Output: prints the public HTTP address assigned to the ALB after deployment.
output "application_url" {
  description = "Public URL for the Shopease application through the Application Load Balancer"
  value       = "http://${aws_lb.shopease_alb.dns_name}"
}

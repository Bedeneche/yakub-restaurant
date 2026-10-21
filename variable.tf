
variable "aws_region" {
  description = "AWS region for the Shopease infrastructure"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "shopease"
}

variable "instance_type" {
  description = "EC2 instance type for the web server"
  type        = string
  default     = "t3.micro"
}

variable "root_volume_size" {
  description = "Size in GiB of each EC2 instance root EBS volume" # Documents this setting in Terraform output.
  type        = number # Accepts a numeric disk size, measured in GiB.
  default     = 20     # Gives each newly launched instance a 20 GiB root disk unless overridden.
}


variable "ubuntu_ami_owner" {
  description = "Official Canonical AWS account ID for Ubuntu images"
  type        = string
  default     = "099720109477"
}

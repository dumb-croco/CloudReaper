provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      ManagedBy   = "Terraform"
      Component   = "workload"
      ManagedByTool = "cloudreaper"
    }
  }
}

locals {
  common_tags = {
    project      = var.project_name
    expiry_time  = var.expiry_time
    managed-by   = "cloudreaper"
    ttl_hours    = tostring(var.ttl_hours)
  }
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "web" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.micro"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-web"
  })
}

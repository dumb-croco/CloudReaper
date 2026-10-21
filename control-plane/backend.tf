terraform {
  backend "s3" {
    bucket         = "cloudreaper-state"
    key            = "cloudreaper/control-plane/terraform.tfstate"
    region         = "ap-south-1"
    encrypt        = true
    use_lockfile   = true
  }

  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

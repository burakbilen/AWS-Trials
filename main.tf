terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

# aws
provider "aws" {
  region = var.AWS_REGION
}

# create vpc
resource "aws_vpc" "main" {
  cidr_block           = "10.3.0.0/16"
  instance_tenancy     = "default"
  enable_dns_hostnames = "true"

  tags = {
    Name = "main"
  }
}

# create subnets
resource "aws_subnet" "public_subnets" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = element(var.public_subnet_cidrs, count.index)
  availability_zone       = element(var.availability_zones, count.index)
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-${count.index + 1}"
  }
}

# create gateway
resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "internet-gw"
  }
}

# create route in order to have access to public subnets from internet
resource "aws_route_table" "public_route" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }

  tags = {
    Name = "Route public subnets"
  }
}

# associate public subnets with public_route
resource "aws_route_table_association" "public_subnet_assoc" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = element(aws_subnet.public_subnets[*].id, count.index)
  route_table_id = aws_route_table.public_route.id
}


# create security group
resource "aws_security_group" "public" {
  name        = "public-sg"
  description = "Public internet access"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "public-sg"
    Role = "public"
  }
}

resource "aws_security_group_rule" "public_out" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.public.id
}

resource "aws_security_group_rule" "public_in_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["${var.my_ip}"]
  security_group_id = aws_security_group.public.id
}

resource "aws_security_group_rule" "public_in_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["${var.my_ip}"]
  security_group_id = aws_security_group.public.id
}

resource "aws_security_group_rule" "public_in_https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["${var.my_ip}"]
  security_group_id = aws_security_group.public.id
}


# create aws key-pair
resource "aws_key_pair" "linux_public_key" {
  key_name   = "linux_public_key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC2IpUCX6MZMKN8OnJXZEtYlQCaXHjfqnPwRgrqD8we/6n5TpMMpX0afZas/dL5WwCESpmhq6KFDi0u3wW8bEZT7oBnyr55B0qasrQ76ItO+7IMfZVHdugQ1scw5Oo7+O3o+CeivWMCYLjDKD4QGeir3UDWTSeweO2M97nhi4uY3r0mHOhzqKhEDUDfxnSiBLw0qFfUdnyh8GxHSUJRw0Fdxo8Rrl4EO6LE2nhzWnQ4M1ScpoiH995mSZiFm036gOf/1n4Ve2VzgtpPwACab/ppsfW5JsRh0KZslGE64Igv7ipNKIKzMuhfTghpPfbFBevJj3tjPCp5tzFECsNzWMFaEt+z1c+7CUMV9ict6Z66itGEqon9aZHgV2g2LrCSRk4hD4FjX1dJHEypwBy6lmgO5jvY7K9woS/EypLk+czmP/KtI6W1XhjSNLSGOkpBjubtqiqIWztA6wtXt6B7ASLFchVmMt2Cuc/NX9qW1jTz37pJCgldf0FBrFTHgsacd0k= burak@DESKTOP-H4HEL09"
}


# create auto scaling group
# ami-070b208e993b59cea (64-bit (x86)) -- Amazon Linux 2 AMI (HVM) - Kernel 5.10, SSD Volume Type

data "template_file" "user_data" {
  template = <<EOF
#!/bin/bash -xe
sudo yum update -y
sudo yum install -y httpd.x86_64
sudo systemctl start httpd.service
sudo systemctl enable httpd.service
EOF
}

resource "aws_launch_template" "launch_template" {
  name_prefix   = "webservers-"
  image_id      = "ami-070b208e993b59cea"
  instance_type = "t2.micro"
  key_name      = "linux_public_key"
  #vpc_security_group_ids = [aws_security_group.public.id]

  user_data = base64encode(data.template_file.user_data.rendered)

  network_interfaces {
    associate_public_ip_address = true
    delete_on_termination       = true
    security_groups             = [aws_security_group.public.id]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "webservers" {
  desired_capacity    = 2
  max_size            = 2
  min_size            = 2
  vpc_zone_identifier = aws_subnet.public_subnets.*.id

  launch_template {
    id      = aws_launch_template.launch_template.id
    version = "$Latest"
  }
}

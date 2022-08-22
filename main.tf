terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.2.0"
    }
  }
}

provider "aws" {
  profile = "default"
  region = "us-east-1"
}

resource "tls_private_key" "private_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "local_file" "private_key" {
  content         = tls_private_key.private_key.private_key_pem
  filename        = "webserver_key.pem"
  file_permission = 0400
}

resource "aws_key_pair" "webserver_key" {
  key_name = "webserver_key"
  public_key = tls_private_key.private_key.public_key_openssh 
}

resource "aws_security_group" "app-sg" {
  name        = "http-ssh"
  description = "Allow"
  ingress {
    description = "http"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "https"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "db"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "security-group"
  }
}

resource "aws_launch_configuration" "launch-conf" {
  image_id        = "ami-090fa75af13c156b4"
  instance_type   = "t2.micro"
  security_groups = [aws_security_group.app-sg.name]
  key_name        = aws_key_pair.webserver_key.key_name
  user_data       = file("udata.sh")

lifecycle {
    create_before_destroy = true
}

}

resource "aws_autoscaling_group" "asg" {
  launch_configuration = aws_launch_configuration.launch-conf.id
  availability_zones   = ["us-east-1a"]
  desired_capacity     = 2
  min_size             = 2
  max_size             = 4
  load_balancers       = [aws_elb.elb.name]
  tag {
    key                 = "Name"
    value               = "terraform-asg-example"
    propagate_at_launch = true
  }
}

resource "aws_elb" "elb" {
  name               = "load-balancer"
  security_groups    = [aws_security_group.app-sg.id]
  //security_groups    = [aws_security_group.alb.id]
  availability_zones = ["us-east-1a"]
  listener {
    lb_port           = 80
    lb_protocol       = "http"
    instance_port     = 80
    instance_protocol = "http"
  }

}

resource "aws_efs_file_system" "myfilesystem" {

  lifecycle_policy {

    transition_to_ia = "AFTER_30_DAYS"
  }
  tags = {
    Name = "Myfilesystem"
  }
}

resource "aws_efs_access_point" "test" {
  file_system_id = aws_efs_file_system.myfilesystem.id
}

resource "aws_efs_file_system_policy" "policy" {
  file_system_id = aws_efs_file_system.myfilesystem.id
  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Id": "Policy01",
    "Statement": [
        {
            "Sid": "Statement",
            "Effect": "Allow",
            "Principal": {
                "AWS": "*"
            },
            "Resource": "${aws_efs_file_system.myfilesystem.arn}",
            "Action": [
                "elasticfilesystem:ClientMount",
                "elasticfilesystem:ClientRootAccess",
                "elasticfilesystem:ClientWrite"
            ],
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "false"
                }
            }
        }
    ]
}
POLICY
}

resource "aws_efs_mount_target" "alpha" {
  file_system_id = aws_efs_file_system.myfilesystem.id
  subnet_id      = aws_subnet.alpha.id
}

resource "aws_vpc" "fone" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "alpha" {
  vpc_id            = aws_vpc.fone.id
  availability_zone = "us-east-1a"
  cidr_block        = "10.0.1.0/24"
}

resource "aws_db_instance" "db" {
  allocated_storage    = 10
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t2.micro"
  db_name              = "base"
  username             = var.db_username
  password             = var.db_password
  //parameter_group_name = aws_db_parameter_group.db.id
  //db_subnet_group_name = aws_db_subnet_group.db.id
  vpc_security_group_ids = [ aws_security_group.app-sg.id ]
  publicly_accessible  = false
  skip_final_snapshot  = true
  multi_az             = false
}

resource "aws_cloudwatch_metric_alarm" "elb" {
  alarm_name          = "RequestCounter"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  period              = "60"
  metric_name         = "RequestCount"
  namespace           = "AWS/ELB"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "ELB req counter"
}

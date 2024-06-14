
##VPC Configuration:

##Use Terraform to define a VPC with both public and private subnets, spanning multiple AZs.

provider "aws" {
  region = "us-east-1"  
}

resource "aws_vpc" "demo-vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "demo-vpc"
  }
}

resource "aws_subnet" "private-subnet-1" {
  vpc_id     = aws_vpc.demo-vpc.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  tags = {
    Name = "private-subnet-1"
  }
}

resource "aws_subnet" "private-subnet-2" {
  vpc_id     = aws_vpc.demo-vpc.id
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-east-1b"
  tags = {
    Name = "private-subnet-2"
  }
}

resource "aws_subnet" "public-subnet-1" {
  vpc_id     = aws_vpc.demo-vpc.id
  cidr_block = "10.0.3.0/24"
  map_public_ip_on_launch = true 
  availability_zone = "us-east-1a"
  tags = {
    Name = "public-subnet-1"
  }
}

resource "aws_subnet" "public-subnet-2" {
  vpc_id     = aws_vpc.demo-vpc.id
  cidr_block = "10.0.4.0/24"
  map_public_ip_on_launch = true 
  availability_zone = "us-east-1b"
  tags = {
    Name = "public-subnet-2"
  }
}

resource "aws_internet_gateway" "demo-igw" {
  vpc_id = aws_vpc.demo-vpc.id
  tags = {
    Name = "demo-vpc-IGW"
    }
}

resource "aws_route_table" "public-route-table" {
  vpc_id = aws_vpc.demo-vpc.id
  tags = {
    Name = "public-route-table"
  }
}

resource "aws_route" "public-route" {
  route_table_id         = aws_route_table.public-route-table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.demo-igw.id
}

resource "aws_route_table_association" "public-subnet-1-association" {
  subnet_id      = aws_subnet.public-subnet-1.id
  route_table_id = aws_route_table.public-route-table.id
}

resource "aws_route_table_association" "public-subnet-2-association" {
  subnet_id      = aws_subnet.public-subnet-2.id
  route_table_id = aws_route_table.public-route-table.id
}

##RDS Database Setup:

##Deploy an RDS MySQL instance in the private subnet. Configure it for multi-AZ deployment for high availability.

resource "aws_db_subnet_group" "demo_db_subnet_group" {
  name       = "demo_db_subnet_group"
  subnet_ids = [aws_subnet.private-subnet-1.id, aws_subnet.private-subnet-2.id]

  tags = {
    Name = "demo-db-subnet-group"
  }
}

resource "aws_db_instance" "demo_db_instance" {
  allocated_storage    = 10
  db_name              = "mydb"
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t3.micro"
  username             = "admin"
  password             = "password"
  db_subnet_group_name = aws_db_subnet_group.demo_db_subnet_group.name
  multi_az             = true
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot  = true
  publicly_accessible  = false
}

##EC2 Instance Setup:

##Launch EC2 instances using an AMI that is pre-configured with WordPress. Place these instances in the public subnet.

resource "aws_security_group" "wordpress_sg" {
  name = "wordpress-sg"
  vpc_id = aws_vpc.demo_vpc.id
  
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

#resource "aws_instance" "wordpress_instance_1" {
  #ami           = "ami-0998c26ebd3b7d23d"
  #instance_type = "t2.micro"
  #subnet_id     = aws_subnet.public_subnet_1.id
  #vpc_security_group_ids = [aws_security_group.wordpress_sg.id]

  #tags = {
    #Name = "WordPress-Instance-1"
  #}
#}

#resource "aws_instance" "wordpress_instance_2" {
  #ami           = "ami-0998c26ebd3b7d23d"
  #instance_type = "t2.micro"
  #subnet_id     = aws_subnet.public_subnet_2.id
  #vpc_security_group_ids = [aws_security_group.wordpress_sg.id]

  #tags = {
    #Name = "WordPress-Instance-2"
  #}
#}


##Elastic Load Balancer (ELB) Setup:

##Create an ELB to distribute incoming traffic evenly across the EC2 instances.

resource "aws_lb" "wordpress_lb" {
  name               = "wordpress-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.wordpress_sg.id]
  subnets            = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]

}

resource "aws_lb_target_group" "wordpress_tg" {
  name     = "wordpress-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.demo_vpc.id

  health_check {
    interval            = 30
    path                = "/"
    protocol            = "HTTP"
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
  }

}

resource "aws_lb_listener" "wordpress_listener" {
  load_balancer_arn = aws_lb.wordpress_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }
}

##Auto Scaling Setup:

** Configure an Auto Scaling group for the EC2 instances to scale in and out based on demand.

resource "aws_launch_template" "wordpress_lt" {
  name_prefix   = "wordpress-"
  image_id      = "ami-0998c26ebd3b7d23d" 
  instance_type = "t2.micro"

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.wordpress_sg.id]
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "WordPress-ASG-Instance"
    }
  }
}

resource "aws_autoscaling_group" "wordpress_asg" {
  launch_template {
    id      = aws_launch_template.wordpress_lt.id
    version = "$Latest"
  }

  vpc_zone_identifier = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
  min_size            = 2
  max_size            = 4
  desired_capacity    = 2
  
  target_group_arns = [aws_elb.wordpress_elb.arn]

}

resource "aws_autoscaling_policy" "scale_out" {
  name                   = "scale-out"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.wordpress_asg.name
}

resource "aws_autoscaling_policy" "scale_in" {
  name                   = "scale-in"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.wordpress_asg.name
}

##Security Group Configuration:

## Define security groups for both the RDS instance and EC2 instances to restrict access appropriately.

resource "aws_security_group" "rds_sg" {
  name        = "rds-sg"
  vpc_id      = aws_vpc.demo_vpc.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "rds-sg"
  }
}

# EC2 instance security group is created above 

##DNS Configuration:

##Use Route 53 to manage the domain and point it to the ELB.

resource "aws_route53_zone" "my_domain" {
  name = "example.com."
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.my_domain.zone_id
  name    = "www.example.com" 
  type    = "A"

  alias {
    name                   = aws_lb.wordpress_alb.dns_name
    zone_id                = aws_lb.wordpress_alb.zone_id
    evaluate_target_health = true
  }
}

##SSL/TLS Setup:

##Implement AWS Certificate Manager (ACM) to provision a free SSL/TLS certificate and associate it with the ELB for secure connections.


resource "aws_acm_certificate" "wordpress_ssl_cert" {
  domain_name       = "example.com"  
  validation_method = "DNS"

  tags = {
    Name = "wordpress-ssl-cert"
  }
}

resource "aws_acm_certificate_validation" "wordpress_cert_validation" {
  certificate_arn         = aws_acm_certificate.wordpress_ssl_cert.arn
  validation_record_fqdns = [aws_acm_certificate.wordpress_ssl_cert.domain_validation_options.0.resource_record_name]
}


resource "aws_lb_listener" "wordpress_https_listener" {
  load_balancer_arn = aws_lb.wordpress_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"  

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }

  certificate_arn = aws_acm_certificate.wordpress_ssl_cert.arn
}




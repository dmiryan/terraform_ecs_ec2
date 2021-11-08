provider "aws" {
  region = "eu-west-1"
}
////
data "aws_iam_policy_document" "ecs_agent" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_agent" {
  name               = "ecs-agent"
  assume_role_policy = data.aws_iam_policy_document.ecs_agent.json
}
/*
resource "aws_iam_role_policy_attachment" "ecs_agent" {
  role       =  aws_iam_role.ecs_agent.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}
*/
resource "aws_iam_instance_profile" "ecs_agent" { 
  name = "ecs-agent"
  role = aws_iam_role.ecs_agent.name
}


resource "aws_vpc" "default" {
  cidr_block = "10.32.0.0/16"
}

data "aws_availability_zones" "available_zones" {
  state = "available"
}

resource "aws_subnet" "public" {
  //count                   = 2
  cidr_block              = "10.32.1.0/24"
  //availability_zone       = data.aws_availability_zones.available_zones.names[count.index]
  vpc_id                  = aws_vpc.default.id
  map_public_ip_on_launch = true
}

resource "aws_subnet" "public2" {
  //count                   = 2
  cidr_block              = "10.32.2.0/24"
  //availability_zone       = data.aws_availability_zones.available_zones.names[count.index]
  vpc_id                  = aws_vpc.default.id
  map_public_ip_on_launch = true
}


resource "aws_subnet" "private" {
  //count             = 2
  cidr_block          = "10.32.11.0/24"
  //availability_zone = data.aws_availability_zones.available_zones.names[count.index]
  vpc_id            = aws_vpc.default.id
}

resource "aws_internet_gateway" "gateway" {
  vpc_id = aws_vpc.default.id
}

resource "aws_route" "internet_access" {
  route_table_id         = aws_vpc.default.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gateway.id
}

resource "aws_eip" "gateway" {
  //count      = 2
  vpc        = true
  depends_on = [aws_internet_gateway.gateway]
}

resource "aws_nat_gateway" "gateway" {
  //count         = 2
  subnet_id     = aws_subnet.public.id
  allocation_id = aws_eip.gateway.id
}

resource "aws_route_table" "private" {
  //count  = 2
  vpc_id = aws_vpc.default.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.gateway.id
  }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "lb" {
  name        = "example-alb-security-group"
  vpc_id      = aws_vpc.default.id

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "default" {
  name            = "example-lb"
  subnets         = [aws_subnet.public.id,aws_subnet.public2.id]
  security_groups = [aws_security_group.lb.id]
}

resource "aws_lb_target_group" "hello_world" {
  name        = "example-target-group"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.default.id
  target_type = "ip"
}

resource "aws_lb_listener" "hello_world" {
  load_balancer_arn = aws_lb.default.id
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_lb_target_group.hello_world.id
    type             = "forward"
  }
}

resource "aws_ecs_task_definition" "hello_world" {
  family                   = "hello-world-app"
  network_mode             = "awsvpc" # 
  requires_compatibilities = ["EC2"]
  cpu                      = 1024
  memory                   = 2048

/*
 container_definitions = jsonencode([
    {
      name      = "hello-world-app"
      image     = "dmiryan.mymir"
      cpu       = 100
      memory    = 128
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
        }
      ]
    }
  ])
}*/

  container_definitions = <<DEFINITION
[
  {
    "image": "dmiryan/mymir",
    "cpu":  1024,
    "memory": 1024,
    "name": "hello-world-app",
    "networkMode": "awsvpc",
    "portMappings": [
      {
        "containerPort": 80,
        "hostPort": 80
      }
    ]  
  }
]
DEFINITION
}


resource "aws_security_group" "hello_world_task" {
  name        = "example-task-security-group"
  vpc_id      = aws_vpc.default.id

  ingress {
    protocol        = "tcp"
    from_port       = 80
    to_port         = 80
    security_groups = [aws_security_group.lb.id]
  }

  ingress {
    protocol        = "tcp"
    from_port       = 22
    to_port         = 22
    cidr_blocks     = ["0.0.0.0/0"]
  }
  

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_ecs_cluster" "main" {
  name = "example-cluster"
}

resource "aws_ecs_service" "hello_world" {
  name            = "hello-world-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.hello_world.arn
  desired_count   = var.app_count
  deployment_minimum_healthy_percent = 100
  launch_type     = "EC2"

  network_configuration {
    security_groups = [aws_security_group.hello_world_task.id]
    subnets         = [aws_subnet.private.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.hello_world.id
    container_name   = "hello-world-app"
    container_port   = 80
  }

  depends_on = [aws_lb_listener.hello_world]
}

resource "aws_route53_record" "mymir" { // type A record within hostedzone
  zone_id = "Z07089102IY5M85NBMNMH"
  name    = "mymir.xyz"
  type    = "A"

  alias {
    name                   = aws_lb.default.dns_name // redirect to 
    zone_id                = aws_lb.default.zone_id  // aws requred argument for alb
    evaluate_target_health = true
  }
}

#autoscaling group section
resource "aws_launch_configuration" "ecs_launch_config" {
    image_id             = "ami-06c11ea68c61e5570"
    iam_instance_profile = aws_iam_instance_profile.ecs_agent.name
    security_groups      = [aws_security_group.hello_world_task.id]
    user_data            = "#!/bin/bash\necho ECS_CLUSTER=example-cluster >> /etc/ecs/ecs.config"
    instance_type        = "t3.large"
    key_name             = aws_key_pair.ed1.id
}

resource "aws_key_pair" "ed1" {
  key_name   = "ed1"
  public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP12xI6YgHVc5r/rR5qWIzILPIdanVnL6Lx/qZ0pZPT1"

 }

resource "aws_autoscaling_group" "failure_analysis_ecs_asg" {
    name                      = "asg"
    vpc_zone_identifier       = [aws_subnet.public.id]
    launch_configuration      = aws_launch_configuration.ecs_launch_config.name

    desired_capacity          = 1
    min_size                  = 1
    max_size                  = 10
    health_check_grace_period = 300
    health_check_type         = "EC2"
}

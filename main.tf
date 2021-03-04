##### Initialize
provider "aws" {
  version = "3.6.0"
  access_key = ""
  secret_key = ""
  region = "us-east-1"
}

##### Use Default AWS VPC
resource "aws_default_vpc" "main" {
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "Default VPC"
  }
}

resource "aws_default_subnet" "aza" {
  availability_zone = "${var.region}a"

  tags = {
    Name = "Default subnet for ${var.region}a"
  }
}

resource "aws_default_subnet" "azb" {
  availability_zone = "${var.region}b"

  tags = {
    Name = "Default subnet for ${var.region}b"
  }
}

resource "aws_default_subnet" "azc" {
  availability_zone = "${var.region}c"

  tags = {
    Name = "Default subnet for ${var.region}c"
  }
}

resource "aws_security_group" "lb" {
  name        = "ECS-Ingress-ALB-SG"
  description = "Controls access to the ECS ALB"
  vpc_id      = aws_default_vpc.main.id

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

resource "aws_security_group" "http" {
  name        = "Plain-HTTP"
  description = "HTTP Access Allowed"
  vpc_id      = aws_default_vpc.main.id

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol    = "tcp"
    from_port   = 8080
    to_port     = 8080
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

##### Create Load Balancer
resource "aws_alb" "main" {
  name            = "limon-ecs-alb-dev"
  subnets         = [aws_default_subnet.aza.id, aws_default_subnet.azb.id, aws_default_subnet.azc.id]
  security_groups = [aws_security_group.lb.id]
}

resource "aws_alb_target_group" "dev" {
  name                 = "limon-be-tg-dev"
  port                 = 80
  protocol             = "HTTP"
  vpc_id               = aws_default_vpc.main.id
  target_type          = "ip"
  deregistration_delay = 30

  health_check {
    path                = "/api/greet?name=Limon"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# Redirect all traffic from the ALB to the target group
resource "aws_alb_listener" "http" {
  load_balancer_arn = aws_alb.main.id
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_alb_target_group.dev.arn
    type             = "forward"
  }
}

# Create Task Execution Role
resource "aws_iam_role" "ecs_task_exec_role" {
  name = "limonTaskExecutionRole"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "task-exec-attach" {
  role       = aws_iam_role.ecs_task_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "cwlogs-exec-attach" {
  role       = aws_iam_role.ecs_task_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

##### Create ECS Cluster
resource "aws_ecs_cluster" "main" {
  name               = "limonhost-dev-fargate-cluster"
  capacity_providers = ["FARGATE_SPOT", "FARGATE"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    base              = 0
    weight            = 100
  }

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    base              = 0
    weight            = 0
  }

  setting {
    name  = "containerInsights"
    value = "disabled"
  }
}

resource "aws_service_discovery_private_dns_namespace" "limon_api" {
  name        = "limon.local"
  description = "LimonCloud Namespace"
  vpc         = aws_default_vpc.main.id
}

resource "aws_ecs_task_definition" "limon_api" {
  family                   = "dev-limon-api"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_exec_role.arn
  cpu                      = 256
  memory                   = 512

  container_definitions = <<DEFINITION
[
  {
    "cpu": 256,
    "image": "nginx:latest",
    "memory": 512,
    "name": "dev-limon-api",
    "networkMode": "awsvpc",
    "portMappings": [
      {
        "containerPort": 8080,
        "hostPort": 8080
      }
    ],
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "dev-limon-fargate-logs",
        "awslogs-region": "us-east-1",
        "awslogs-stream-prefix": "limon-api",
        "awslogs-create-group": "true"
      }
    },
    "environment" : [
      {"name": "ENV_PARAMETRESI_1", "value": "Merhaba"},
      {"name": "ENV_PARAMETRESI_2", "value": "AWS"}
    ]
  }
]
DEFINITION
}

resource "aws_service_discovery_service" "dev_limon_api" {
  name = "dev-limon-api"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.limon_api.id

    dns_records {
      ttl  = 10
      type = "A"
    }

    routing_policy = "MULTIVALUE"
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

resource "aws_ecs_service" "limon-api" {
  name                              = "dev-limon-api-service"
  cluster                           = aws_ecs_cluster.main.id
  task_definition                   = aws_ecs_task_definition.limon_api.arn
  desired_count                     = 1
  platform_version                  = "1.4.0"
  launch_type                       = "FARGATE"
  health_check_grace_period_seconds = 10

  network_configuration {
    security_groups  = [aws_security_group.http.id]
    subnets          = [aws_default_subnet.aza.id, aws_default_subnet.azb.id, aws_default_subnet.azc.id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn   = aws_service_discovery_service.dev_limon_api.arn
    container_name = "dev-limon-api"
  }

  load_balancer {
    target_group_arn = aws_alb_target_group.dev.id
    container_name   = "dev-limon-api"
    container_port   = 8080
  }
  
  lifecycle {
    ignore_changes = [desired_count]
  }

  depends_on = [aws_alb_listener.http]
}

##### Auto Scaling
resource "aws_appautoscaling_target" "limon_target" {
  max_capacity       = 10
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.limon-api.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "limon_scaling_policy" {
  name               = "scaling-policy"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.limon_target.resource_id
  scalable_dimension = aws_appautoscaling_target.limon_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.limon_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }

    target_value       = 50
    scale_in_cooldown  = 300
    scale_out_cooldown = 300
  }
}

# Create CodeBuild Service Role
resource "aws_iam_policy" "codebuild_perms" {
  name        = "codeBuildPermissionPolicy"
  path        = "/"
  description = "Main policy that CodeBuild uses"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "codebuild:CreateReportGroup",
        "codebuild:CreateReport",
        "codebuild:UpdateReport",
        "codebuild:BatchPutTestCases"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role" "codebuild_svc_role" {
  name = "codeBuildServiceRole"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "codebuild.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "codebuild_s3_attach" {
  role       = aws_iam_role.codebuild_svc_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "codebuild_ecr_attach" {
  role       = aws_iam_role.codebuild_svc_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

resource "aws_iam_role_policy_attachment" "codebuild_ecs_attach" {
  role       = aws_iam_role.codebuild_svc_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonECS_FullAccess"
}

resource "aws_iam_role_policy_attachment" "codebuild_main_attach" {
  role       = aws_iam_role.codebuild_svc_role.name
  policy_arn = aws_iam_policy.codebuild_perms.arn
}

##### CodeBuild Stuff
##### Core
resource "aws_codebuild_project" "limonultation" {
  name           = "limon-api-cicd"
  description    = "limon-api build and ship project"
  build_timeout  = "30"
  queued_timeout = "480"
  service_role   = aws_iam_role.codebuild_svc_role.arn
  source_version = "develop"

  artifacts {
    type = "NO_ARTIFACTS"
  }

  cache {
    type  = "LOCAL"
    modes = ["LOCAL_DOCKER_LAYER_CACHE"]
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:4.0-20.08.14"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true
  
    environment_variable {
      name  = "ENV"
      value = "dev"
    }

    environment_variable {
      name  = "APP"
      value = "limon-api"
    }

    environment_variable {
      name  = "CLUSTER_NAME"
      value = aws_ecs_cluster.main.name
    }
  }

  source {
    type                = "GITHUB"
    location            = "https://github.com/LimonCloud/fargate-demo-source"
    git_clone_depth     = 1
    report_build_status = true

    git_submodules_config {
      fetch_submodules = false
    }
  }
}
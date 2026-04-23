resource "aws_ecs_cluster" "fcg" {
  name = "${local.name_prefix}-cluster"
  tags = local.common_tags
}

resource "aws_iam_role" "ecs_instance" {
  name = "${local.name_prefix}-ecs-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ecs_instance" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs" {
  name = "${local.name_prefix}-ecs-instance-profile"
  role = aws_iam_role.ecs_instance.name
}

resource "aws_security_group" "ecs_instance" {
  name        = "${local.name_prefix}-ecs-sg"
  description = "ECS EC2 instance"

  ingress {
    from_port   = 8080
    to_port     = 8081
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["172.16.0.0/12"]
  }

  ingress {
    from_port   = 5672
    to_port     = 5672
    protocol    = "tcp"
    cidr_blocks = ["172.16.0.0/12"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.common_tags
}

resource "aws_instance" "ecs" {
  ami                    = "ami-0ce09e2429ff33e52"
  instance_type          = "t2.micro"
  iam_instance_profile   = aws_iam_instance_profile.ecs.name
  vpc_security_group_ids = [aws_security_group.ecs_instance.id]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    echo ECS_CLUSTER=${aws_ecs_cluster.fcg.name} >> /etc/ecs/ecs.config

    # Format EBS on first use, then mount for Postgres data
    if ! blkid /dev/xvdf > /dev/null 2>&1; then
      mkfs -t ext4 /dev/xvdf
    fi
    mkdir -p /data/postgres
    mount /dev/xvdf /data/postgres
    mkdir -p /data/postgres/pgdata
    chown 999:999 /data/postgres/pgdata
    echo '/dev/xvdf /data/postgres ext4 defaults,nofail 0 2' >> /etc/fstab
  EOF
  )

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-ecs-instance" })
}

resource "aws_ebs_volume" "postgres_data" {
  availability_zone = aws_instance.ecs.availability_zone
  size              = 10
  type              = "gp3"
  tags              = merge(local.common_tags, { Name = "${local.name_prefix}-postgres-data" })
}

resource "aws_volume_attachment" "postgres_data" {
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.postgres_data.id
  instance_id = aws_instance.ecs.id
}

resource "aws_eip" "ecs" {
  instance = aws_instance.ecs.id
  domain   = "vpc"
  tags     = local.common_tags
}

locals {
  jenkins_userdata = <<-EOF
    #!/bin/bash
    set -e
    exec > /var/log/userdata.log 2>&1

    apt-get update -y
    apt-get upgrade -y

    apt-get install -y fontconfig openjdk-17-jre
    wget -O /usr/share/keyrings/jenkins-keyring.asc \
      https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key
    echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
      https://pkg.jenkins.io/debian-stable binary/" \
      > /etc/apt/sources.list.d/jenkins.list
    apt-get update -y
    apt-get install -y jenkins
    systemctl enable jenkins
    systemctl start jenkins

    apt-get install -y ca-certificates curl gnupg lsb-release
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) \
      signed-by=/etc/apt/keyrings/docker.asc] \
      https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" \
      > /etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io
    systemctl enable docker
    systemctl start docker
    usermod -aG docker jenkins
    usermod -aG docker ubuntu

    apt-get install -y unzip
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
      -o "/tmp/awscliv2.zip"
    unzip /tmp/awscliv2.zip -d /tmp
    /tmp/aws/install

    apt-get install -y git htop curl wget jq

    systemctl restart jenkins
  EOF

  app_userdata = <<-EOF
    #!/bin/bash
    set -e
    exec > /var/log/userdata.log 2>&1

    apt-get update -y
    apt-get upgrade -y

    apt-get install -y ca-certificates curl gnupg lsb-release
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo "deb [arch=$(dpkg --print-architecture) \
      signed-by=/etc/apt/keyrings/docker.asc] \
      https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" \
      > /etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io
    systemctl enable docker
    systemctl start docker
    usermod -aG docker ubuntu

    apt-get install -y unzip
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
      -o "/tmp/awscliv2.zip"
    unzip /tmp/awscliv2.zip -d /tmp
    /tmp/aws/install

    apt-get install -y nginx
    systemctl enable nginx
    systemctl start nginx

    cat > /etc/nginx/sites-available/app << 'NGINX'
    server {
        listen 80;
        server_name _;

        location / {
            proxy_pass         http://localhost:3000;
            proxy_http_version 1.1;
            proxy_set_header   Upgrade $http_upgrade;
            proxy_set_header   Connection 'upgrade';
            proxy_set_header   Host $host;
            proxy_set_header   X-Real-IP $remote_addr;
            proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_cache_bypass $http_upgrade;
        }

        location /check {
            proxy_pass http://localhost:3000/check;
        }
    }
    NGINX

    ln -sf /etc/nginx/sites-available/app /etc/nginx/sites-enabled/app
    rm -f /etc/nginx/sites-enabled/default
    nginx -t && systemctl reload nginx

    mkdir -p /home/ubuntu/project
    chown ubuntu:ubuntu /home/ubuntu/project

    cat > /home/ubuntu/deploy.sh << 'DEPLOY'
    #!/bin/bash
    set -e
    ECR_REGISTRY=$1
    IMAGE_TAG=$2
    AWS_REGION=$${3:-eu-north-1}

    if [ -z "$ECR_REGISTRY" ] || [ -z "$IMAGE_TAG" ]; then
      echo "Usage: ./deploy.sh <ecr-registry> <image-tag>"
      exit 1
    fi

    echo "--- Logging into ECR ---"
    aws ecr get-login-password --region $AWS_REGION | \
      docker login --username AWS --password-stdin $ECR_REGISTRY

    echo "--- Pulling image: $ECR_REGISTRY/my-app:$IMAGE_TAG ---"
    docker pull $ECR_REGISTRY/my-app:$IMAGE_TAG

    echo "--- Stopping old container ---"
    docker stop my-app 2>/dev/null || true
    docker rm   my-app 2>/dev/null || true

    echo "--- Starting new container ---"
    docker run -d \
      --name my-app \
      --restart unless-stopped \
      -p 3000:3000 \
      -e NODE_ENV=production \
      $ECR_REGISTRY/my-app:$IMAGE_TAG

    echo "--- Waiting for app to start ---"
    sleep 3

    echo "--- Health check ---"
    curl -f http://localhost:3000/check || {
      echo "Health check failed"
      docker logs my-app
      exit 1
    }

    echo "--- Reloading Nginx ---"
    sudo systemctl reload nginx

    echo "--- Deploy complete: $IMAGE_TAG ---"
    DEPLOY

    chmod +x /home/ubuntu/deploy.sh
    chown ubuntu:ubuntu /home/ubuntu/deploy.sh

    wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb \
      -O /tmp/amazon-cloudwatch-agent.deb
    dpkg -i /tmp/amazon-cloudwatch-agent.deb

    cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CW'
    {
      "logs": {
        "logs_collected": {
          "files": {
            "collect_list": [
              {
                "file_path": "/var/log/nginx/access.log",
                "log_group_name": "/app/nginx/access",
                "log_stream_name": "{instance_id}"
              },
              {
                "file_path": "/var/log/nginx/error.log",
                "log_group_name": "/app/nginx/error",
                "log_stream_name": "{instance_id}"
              }
            ]
          }
        }
      },
      "metrics": {
        "metrics_collected": {
          "cpu": {
            "measurement": ["cpu_usage_idle", "cpu_usage_user"],
            "metrics_collection_interval": 60
          },
          "mem": {
            "measurement": ["mem_used_percent"],
            "metrics_collection_interval": 60
          }
        }
      }
    }
    CW

    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
      -a fetch-config -m ec2 -s \
      -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

    apt-get install -y htop curl wget jq
  EOF
}

resource "aws_instance" "jenkins" {
  ami                    = var.ami_id
  instance_type          = var.jenkins_instance_type
  subnet_id              = aws_subnet.public_a.id
  vpc_security_group_ids = [aws_security_group.jenkins.id]
  key_name               = var.key_pair_name
  iam_instance_profile   = aws_iam_instance_profile.jenkins.name
  user_data              = local.jenkins_userdata

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = {
    Name = "${var.app_name}-jenkins"
  }
}

resource "aws_instance" "app" {
  ami                    = var.ami_id
  instance_type          = var.app_instance_type
  subnet_id              = aws_subnet.public_a.id
  vpc_security_group_ids = [aws_security_group.app.id]
  key_name               = var.key_pair_name
  iam_instance_profile   = aws_iam_instance_profile.app.name
  user_data              = local.app_userdata

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }

  tags = {
    Name = "${var.app_name}-app"
  }
}
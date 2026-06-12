locals {
  jenkins_userdata = <<-EOF
#!/bin/bash
set -e
exec > /var/log/userdata.log 2>&1

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get upgrade -y

sudo apt install -y fontconfig openjdk-21-jre

# Create keyrings directory (safe for fresh Ubuntu)
sudo mkdir -p /etc/apt/keyrings

# Add Jenkins GPG key (new official key)
sudo wget -O /etc/apt/keyrings/jenkins-keyring.asc \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key

# Add Jenkins repository
echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] \
https://pkg.jenkins.io/debian-stable binary/" | sudo tee \
/etc/apt/sources.list.d/jenkins.list > /dev/null

# Update package list
sudo apt update -y

# Install Jenkins
sudo apt install -y jenkins

# Enable and start Jenkins
sudo systemctl enable jenkins
sudo systemctl start jenkins
# ── Docker ────────────────────────────────────────────────────────────────────
apt-get install -y ca-certificates curl gnupg lsb-release
install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

ARCH=$(dpkg --print-architecture)
CODENAME=$(lsb_release -cs)
echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu $CODENAME stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io
systemctl enable docker
systemctl start docker
usermod -aG docker jenkins
usermod -aG docker ubuntu

# ── AWS CLI ───────────────────────────────────────────────────────────────────
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

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release unzip nginx

# ── Docker ────────────────────────────────────────────────────────────────────
install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

ARCH=$(dpkg --print-architecture)
CODENAME=$(lsb_release -cs)
echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu $CODENAME stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io
systemctl enable docker
systemctl start docker
usermod -aG docker ubuntu

# ── AWS CLI ───────────────────────────────────────────────────────────────────
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
  -o "/tmp/awscliv2.zip"
unzip /tmp/awscliv2.zip -d /tmp
/tmp/aws/install

# ── Nginx ─────────────────────────────────────────────────────────────────────
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

# ── deploy.sh ─────────────────────────────────────────────────────────────────
mkdir -p /home/ubuntu/project
chown ubuntu:ubuntu /home/ubuntu/project

cat > /home/ubuntu/deploy.sh << 'DEPLOY'
#!/bin/bash
set -e
ECR_REGISTRY=$1
IMAGE_TAG=$2
AWS_REGION=$${3:-eu-north-1}

if [ "$IMAGE_TAG" = "latest" ] || [ -z "$IMAGE_TAG" ]; then
  echo "Fetching current deployment tag from SSM..."
  IMAGE_TAG=$(aws ssm get-parameter \
    --name "/myapp/deploy/image-tag" \
    --region "$AWS_REGION" \
    --query "Parameter.Value" \
    --output text 2>/dev/null || echo "latest")
fi

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
sleep 5

echo "--- Health check ---"
curl -sf http://localhost:3000/check || {
  echo "Health check failed"
  docker logs my-app
  exit 1
}

echo "--- Reloading Nginx ---"
systemctl reload nginx

echo "--- Deploy complete: $IMAGE_TAG ---"
DEPLOY

chmod +x /home/ubuntu/deploy.sh
chown ubuntu:ubuntu /home/ubuntu/deploy.sh

# ── CloudWatch Agent ──────────────────────────────────────────────────────────
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

# ── Initial deploy ────────────────────────────────────────────────────────────
/home/ubuntu/deploy.sh \
  016605188495.dkr.ecr.eu-north-1.amazonaws.com \
  latest \
  eu-north-1 || echo "WARNING: Initial deploy failed — check /var/log/userdata.log"
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

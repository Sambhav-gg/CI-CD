# 🚀 Enterprise CI/CD Infrastructure on AWS with AI-Powered Failure Analysis

> A production-grade, highly resilient CI/CD pipeline and AWS cloud infrastructure built entirely from scratch. Every commit to GitHub automatically triggers an automated test, containerization, and rolling deployment to an auto-scaling cluster with CloudWatch telemetry, Lambda uptime monitoring, and **Groq Llama-3.3 AI-driven pipeline failure analysis** reporting directly to Slack.

![Status](https://img.shields.io/badge/status-live-brightgreen) ![AWS](https://img.shields.io/badge/cloud-AWS-FF9900?logo=amazonaws) ![Docker](https://img.shields.io/badge/container-Docker-2496ED?logo=docker) ![Terraform](https://img.shields.io/badge/iac-Terraform-7B42BC?logo=terraform) ![Jenkins](https://img.shields.io/badge/ci/cd-Jenkins-D24939?logo=jenkins) ![Groq AI](https://img.shields.io/badge/ai-Groq%20Llama%203.3-orange) ![Node.js](https://img.shields.io/badge/runtime-Node.js-339933?logo=nodedotjs)

---

## 📌 What This Project Is

This repository demonstrates a complete, secure, and production-grade AWS infrastructure and deployment pipeline provisioned entirely as code. Unlike simple single-instance deployments, this architecture implements enterprise-level patterns:

- **Infrastructure as Code**: The entire AWS stack is defined and versioned via **Terraform**.
- **Containerized Workloads**: Multi-stage **Docker** builds guarantee slim, secure runtime images running as non-root users.
- **GitOps Rolling Deploys**: Deployments utilize **AWS SSM Parameter Store** and **AWS Auto Scaling Group (ASG) Instance Refreshes** to achieve zero-downtime rolling updates.
- **AI-Powered Diagnostics**: Pipeline failures trigger a custom DevOps AI agent (powered by **Groq Llama 3.3**) to diagnose build logs, detect root causes, and post fixes to **Slack**.
- **Active Telemetry**: A **CloudWatch Agent** streams Nginx access/error logs and hardware metrics from instances.
- **Continuous Health Checks**: Serverless **AWS Lambda** pingers monitor availability and trigger **SNS Email Alerts** in the event of downtime.

---

## 🏗️ Architecture Design

```
                                  AWS Cloud (eu-north-1 VPC)
   ┌────────────────────────────────────────────────────────────────────────────────────────┐
   │                                                                                        │
   │  ┌────────────────┐           (1) Write Tag       ┌─────────────────────────────────┐  │
   │  │  Jenkins EC2   │──────────────────────────────►│    SSM Parameter Store          │  │
   │  │ c7i-flex.large │                               │     /myapp/deploy/image-tag     │  │
   │  │   Port 8080    │───────────┐                   └────────────────┬────────────────┘  │
   │  └───────┬────────┘           │ (2) Trigger                        │ (Pulls target  │  │
   │          │                    │     Instance Refresh               │  image tag)    │  │
   │      (Builds &                ▼                                    ▼                │  │
   │      Pushes Tag)     ┌────────────────┐           ┌─────────────────────────────────┐  │
   │          │           │   Target Group │           │  Auto Scaling Group (ASG)       │  │
   │          ▼           └────────▲───────┘           │  - Scale: 1 Min / 3 Max         │  │
   │  ┌────────────────┐           │                   │  - Instance Type: t3.micro      │  │
   │  │    AWS ECR     │◄──────────┼─(Pulls image)─────│  - Services: Docker + Nginx     │  │
   │  └────────────────┘           │                   └────────────────┬────────────────┘  │
   │                               │ (Routes Port 80)                   │                   │  │
   │  ┌────────────────────────────────────────────┐                    │                   │  │
   │  │       Application Load Balancer (ALB)      │◄───────────────────┘                   │  │
   │  └────────────────────▲───────────────────────┘                                        │  │
   │                       │ (Inbound Port 80)                                              │  │
   └───────────────────────┼────────────────────────────────────────────────────────────────┘
                           │
                      HTTP Traffic
                           │
                      ┌────┴────┐
                      │  Users  │
                      └─────────┘
```

### Serverless Monitoring & Alerting Flow
```
 ┌──────────────────────┐      rate(5 mins)      ┌───────────────────────────┐
 │  EventBridge Trigger │───────────────────────►│  Uptime Pinger (Lambda)   │
 └──────────────────────┘                        └─────────────┬─────────────┘
                                                               │ (GET /check)
                                                               ▼
 ┌──────────────────────┐    Publish on Error    ┌───────────────────────────┐
 │    SNS Alerts        │◄───────────────────────│  Application Load Balancer│
 │ (Downtime Emails)    │                        │          (ALB)            │
 └──────────────────────┘                        └───────────────────────────┘
```

---

## 🔄 The CI/CD Pipeline

```
Commit Pushed to main
        │
        ▼
 ┌─────────────┐
 │  Checkout   │  Clones the GitHub repository and checks out the commit.
 └──────┬──────┘
        │
        ▼
 ┌─────────────┐
 │Build & Test │  Runs clean dependency install (`npm ci`) and runs smoke test on Express /check.
 └──────┬──────┘
        │
        ▼
 ┌─────────────┐
 │Docker Build │  Builds multi-stage Docker image, tagging it with ECR URI and Commit SHA.
 └──────┬──────┘
        │
        ▼
 ┌─────────────┐
 │  ECR Push   │  Authenticates with AWS and pushes tags (`latest` & `short-SHA`) to ECR.
 └──────┬──────┘
        │
        ▼
 ┌─────────────┐
 │ ASG Refresh │  Updates SSM tag parameter and triggers ASG rolling instance refresh.
 └──────┬──────┘
        │
        ▼
 ┌─────────────┐
 │Verify Deploy│  Polls the ALB public DNS endpoint at `/check` to confirm startup.
 └──────┬──────┘
        │
        ├───────────────────────────────┐
        ▼ (Success)                     ▼ (Failure)
 ┌─────────────┐                 ┌───────────────┐
 │ Slack Alert │                 │  Cancel ASG   │  Cancels rolling refresh to avoid staging bad builds.
 └─────────────┘                 └──────┬────────┘
                                        │
                                        ▼
                                 ┌───────────────┐
                                 │ Groq AI Logs  │  Sends logs to Llama-3.3 on Groq to find root cause.
                                 │  Diagnostics  │  
                                 └──────┬────────┘
                                        │
                                        ▼
                                 ┌───────────────┐
                                 │ Slack Failure │  Sends error report + AI-recommended fix to Slack.
                                 │  Notification │
                                 └───────────────┘
```

---

## 🛠️ Infrastructure & Tech Stack

### Cloud & Orchestration
| Layer | Technology | Implementation Detail |
| :--- | :--- | :--- |
| **Compute (CI/CD)** | AWS EC2 (`c7i-flex.large`) | Houses the Jenkins runner, Docker engine, and local workspace. |
| **Compute (App)** | AWS ASG (`t3.micro`) | Auto-scaling instances hosting Docker daemon + Nginx reverse proxy. |
| **Load Balancing** | AWS ALB | Dispatches external traffic across available instances in multiple AZs. |
| **Container Registry** | AWS ECR | Secure image repository with automatic 5-image lifecycle pruning. |
| **Configuration Store**| AWS SSM | Stores dynamic runtime environment flags and target docker tags. |
| **Telemetry** | CloudWatch Agent | Streams local nginx and hardware diagnostics back to CloudWatch logs. |
| **Provisioning** | Terraform | Code-driven VPC, IAM roles, security credentials, and instances. |

### Monitoring & Uptime
* **AWS Lambda**: Nodejs 18 runtime scheduled via **EventBridge** (triggered every 5 minutes).
* **AWS SNS**: Publishes email alerts immediately if the Lambda pinger receives a non-200 response or error.

### Core Application
* **Runtime**: Node.js 18 + Express.
* **Server Front**: Nginx reverse proxy (listening on 80, proxying back to container on 3000) configuration includes rate limiting placeholders, security headers (nosniff, frame protection), and gzip compression.

---

## 📁 Repository Blueprint

```
.
├── app.js                        # Express app, status API, and system metrics endpoints
├── package.json                  # Dependencies (Express) and startup commands
├── Dockerfile                    # Clean multi-stage production build structure
├── Jenkinsfile                   # Multi-stage Jenkins pipeline config with Groq AI integration
├── nginx/
│   └── app.conf                  # Nginx reverse proxy config template
├── lambda/
│   └── uptime-monitor.js         # Serverless health check logic
└── terraform/
    ├── main.tf                   # Terraform providers and cloud scope
    ├── variables.tf              # Input variables (IP configs, instance types, keys)
    ├── outputs.tf                # ALB DNS, ECR repo URL, Jenkins IP, and SNS topic ARN
    ├── vpc.tf                    # Networking: VPC, subnets (A/B), routing tables, and IGW
    ├── security-groups.tf        # Least privilege rules (Ingress restricted to specific IPs)
    ├── iam.tf / iam_ssm.tf       # EC2 profiles, Lambda roles, and SSM parameter access policies
    ├── ecr.tf                    # Container registry and image retention specs
    ├── ec2.tf                    # EC2 setups, storage bounds, and user-data scripts
    ├── alb.tf / asg.tf           # Load balancing, launch templates, and scaling policies
    ├── ssm.tf                    # SSM parameters for tag management
    ├── sns.tf / lambda.tf        # Lambda triggers, event rules, and SNS publishers
    └── cloudwatch.tf             # Alert log groups and metric monitors
```

---

## 🔐 Security Model & Traffic Rules

1. **Strict Ingress**:
   - **ALB**: Open to HTTP Port 80 from the general internet (`0.0.0.0/0`).
   - **Jenkins**: Open on Ports 22 and 8080 to **your IP only** (`var.your_ip`).
   - **App Instances**: Restrict Port 80 to inbound from the **ALB security group only**, and Port 22 SSH ingress to the **Jenkins security group only**.
2. **Execution Context**:
   - Docker container implements multi-stage builds and runs as a custom non-root user (`appuser`).
3. **Role Segregation (IAM)**:
   - Jenkins has permissions to upload to ECR and configure ASG / write SSM.
   - App instances have permissions to pull from ECR and read tags from SSM.
   - Lambda is limited to executing basic runs and writing to SNS topics.

---

## 🤖 Deep Dive: AI-Driven Failure Analysis

If any step in the Jenkins pipeline fails (such as an npm install failure, syntax error, or failing smoke test), the `post { failure { ... } }` hook triggers the diagnostic agent:

1. **Log Extraction**: It retrieves the last 80 lines of the current Jenkins build console output.
2. **Context Enrichment**: It constructs a structured JSON request utilizing `jq` to prevent quoting errors.
3. **LLM Diagnostics**: The payload is sent to Groq APIs utilizing the `llama-3.3-70b-versatile` model.
4. **Diagnostic Output**: The AI identifies:
   - **Root Cause**: The exact line/dependency causing the issue.
   - **Confidence**: Diagnostic certainty score.
   - **Fix**: Code or dependency modifications.
   - **Commands**: Terminal commands required to apply the fix.
5. **Slack Delivery**: It posts a custom Slack block showing the exact details and instructions.

---

## 🚀 Deployment Guide

### Prerequisites
* AWS account with CLI configured (`aws configure`).
* Terraform installed locally.
* Git + Node.js installed locally.

### 1. Clone & Prepare
```bash
git clone https://github.com/your-username/CI-CD.git
cd CI-CD
```

### 2. Configure Variables
Navigate to the `terraform/` directory, copy the example variables file, and update it with your settings:
```bash
cd terraform
# Create your tfvars configuration
cat > terraform.tfvars <<EOF
alert_email   = "your-alert-email@gmail.com"
key_pair_name = "your-aws-ssh-key-name"
your_ip       = "198.51.100.45/32"  # Update with your public IPv4 CIDR
EOF
```

### 3. Provision Infrastructure
Initialize and apply the Terraform plan to deploy AWS infrastructure:
```bash
terraform init
terraform plan
terraform apply -auto-approve
```
This process takes about 5 minutes. Take note of the printed output variables:
* `jenkins_public_ip`
* `alb_dns`
* `ecr_repository_url`
* `sns_topic_arn`

> [!IMPORTANT]
> **SNS Confirmation Required**: Check your inbox for the email configured in `alert_email` and click the "Confirm Subscription" link to enable downtime email notifications.

### 4. Setup Jenkins Server
1. Navigate to `http://<jenkins_public_ip>:8080` in your web browser.
2. Retrieve the initial admin password:
   ```bash
   ssh -i /path/to/key.pem ubuntu@<jenkins_public_ip> "sudo cat /var/lib/jenkins/secrets/initialAdminPassword"
   ```
3. Install default plugins + recommended extensions:
   * **Git**
   * **SSH Agent**
   * **Pipeline**
   * **Docker Pipeline**
4. Configure Credentials in the Jenkins Dashboard:
   * `ec2-ssh-key`: Create an **SSH Username with private key** credential type. Set username to `ubuntu` and paste your private key (`.pem`) contents.
   * `slack-webhook-url`: Create a **Secret text** credential type and paste your Slack incoming webhook URL.
   * `llm-api-key`: Create a **Secret text** credential type and paste your Groq API key.

### 5. Hook GitHub Repository
Configure webhook in GitHub:
* Go to repository **Settings** ──► **Webhooks** ──► **Add webhook**.
* Set **Payload URL** to `http://<jenkins_public_ip>:8080/github-webhook/`.
* Set **Content type** to `application/json`.
* Select **Just the push event** and save.

### 6. Run Your First Pipeline
Pushes to your repository will trigger builds automatically. You can also trigger a manual build inside the Jenkins dashboard.

---

## 🔁 Rolling Updates & Rollback

### Zero-Downtime Deployment
Deployments do not overwrite code directly. Instead, when a build succeeds:
1. Jenkins updates the target ECR image tag in SSM (`/myapp/deploy/image-tag`).
2. Jenkins requests an **Instance Refresh** on the Auto Scaling Group.
3. The Auto Scaling Group launches new EC2 instances (running the userdata script that checks out the SSM tag, logs into ECR, pulls the container, and starts Nginx proxy).
4. Old instances are terminated once new instances pass the Application Load Balancer health checks.

### Rolling Back Builds
If a post-deploy health check fails, the Jenkinsfile immediately issues a cancellation:
```bash
aws autoscaling cancel-instance-refresh --auto-scaling-group-name my-app-asg --region eu-north-1
```
To roll back manually to any previous commit:
1. Locate the previous successful build inside Jenkins.
2. Re-run that build pipeline. The image tag corresponding to that Git commit SHA will be updated in SSM, and the ASG Instance Refresh will roll back the instances to that version.

---

## 📊 Express Application Endpoints
The backend Express app serves the following endpoints:

| Endpoint | Method | Response |
| :--- | :--- | :--- |
| `/` | GET | Returns a real-time status dashboard UI. |
| `/check` | GET | Returns `{"status":"ok", "timestamp":"..."}` for internal smoke tests and ALB health checks. |
| `/api/status` | GET | Returns services statuses, system usage metrics (uptime, memory, CPUs), and region details. |

---

## 👨‍💻 Infrastructure Author

**Sambhav Garg**  
B.Tech CSE — Bennett University  
[GitHub](https://github.com/Sambhav-gg) · [LinkedIn](https://linkedin.com/in/sambhav-garg-255bb120b)

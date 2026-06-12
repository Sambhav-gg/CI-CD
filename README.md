# 🚀 Production CI/CD Pipeline on AWS — with AI Failure Diagnostics

> **Every `git push` automatically builds, tests, containerizes, and deploys your app to a self-healing AWS cluster — with zero downtime. If something breaks, an AI agent diagnoses the failure and posts the fix to Slack.**

[![Status](https://img.shields.io/badge/status-live-brightgreen)](#)
[![AWS](https://img.shields.io/badge/AWS-EC2%20·%20ALB%20·%20ASG%20·%20ECR%20·%20Lambda-FF9900?logo=amazonaws)](#-infrastructure--tech-stack)
[![Terraform](https://img.shields.io/badge/IaC-Terraform-7B42BC?logo=terraform)](#-infrastructure--tech-stack)
[![Docker](https://img.shields.io/badge/Container-Docker-2496ED?logo=docker)](#-infrastructure--tech-stack)
[![Jenkins](https://img.shields.io/badge/CI%2FCD-Jenkins-D24939?logo=jenkins)](#-the-cicd-pipeline)
[![Groq AI](https://img.shields.io/badge/AI-Groq%20Llama%203.3-orange)](#-ai-driven-failure-analysis)
[![Node.js](https://img.shields.io/badge/Runtime-Node.js%2018-339933?logo=nodedotjs)](#)

---

## Why This Project Exists

Most CI/CD tutorials stop at "push to EC2." This project goes further — it solves the problems you actually face in production:

| Problem | How This Project Solves It |
| :--- | :--- |
| Deployments cause downtime | ASG Instance Refresh replaces instances one-by-one behind an ALB |
| "It broke but I don't know why" | Groq Llama 3.3 reads the build logs and posts root cause + fix to Slack |
| Infrastructure drifts from reality | Every AWS resource is Terraform-managed and version-controlled |
| No visibility into app health | Lambda pings the app every 5 min; SNS emails you if it's down |
| Containers run as root | Multi-stage Docker build runs as `appuser` with a built-in healthcheck |
| Logs vanish when instances cycle | CloudWatch Agent streams Nginx + system metrics before termination |

---

## Architecture

```
                                    AWS Cloud (eu-north-1)
  ┌──────────────────────────────────────────────────────────────────────────────┐
  │                                                                              │
  │   GitHub Push                                                                │
  │       │                                                                      │
  │       ▼                                                                      │
  │   ┌──────────┐    Build & Push     ┌─────────┐                               │
  │   │ Jenkins  │ ──────────────────► │   ECR   │  (Docker images)              │
  │   │ EC2      │                     └────┬────┘                               │
  │   │ c7i-flex │──┐                       │                                    │
  │   └──────────┘  │                       │ docker pull                        │
  │                 │ Write tag              ▼                                    │
  │                 ▼                  ┌───────────────┐                          │
  │          ┌───────────┐            │  Auto Scaling  │  1 min / 3 max          │
  │          │    SSM    │ ◄─ read ── │    Group       │  (t3.micro)             │
  │          │ /image-tag│            │  Docker+Nginx  │                          │
  │          └───────────┘            └───────┬───────┘                          │
  │                                           │                                  │
  │   ┌─────────────┐     EventBridge   ┌─────▼─────┐                           │
  │   │   Lambda    │ ─── GET /check ──►│    ALB    │◄──── HTTP ──── Users      │
  │   │  (5 min)    │                   └───────────┘                            │
  │   └──────┬──────┘                                                            │
  │          │ on failure                                                         │
  │          ▼                                                                   │
  │   ┌─────────────┐                                                            │
  │   │  SNS Email  │  Downtime alert                                            │
  │   └─────────────┘                                                            │
  └──────────────────────────────────────────────────────────────────────────────┘
```

---

## The CI/CD Pipeline

Six stages run automatically on every push to `main`:

```
 ① Checkout  ──►  ② Build & Test  ──►  ③ Docker Build  ──►  ④ ECR Push  ──►  ⑤ Deploy  ──►  ⑥ Verify
                     npm ci +              Multi-stage         SHA + latest      SSM update     Poll ALB
                     smoke test            non-root build      tags pushed       + ASG refresh   /check
```

**On success** → Slack notification with build details and app URL.

**On failure** →
1. Cancel the ASG Instance Refresh (stop bad code from spreading)
2. Extract last 80 lines of build logs
3. Send logs to **Groq Llama 3.3** for root cause analysis
4. Post the AI diagnosis + recommended fix to **Slack**

> [!NOTE]
> The AI payload is constructed via `jq` to prevent shell quoting issues with log content — a real-world problem most tutorials skip.

---

## AI-Driven Failure Analysis

When a pipeline stage fails, the `post { failure { } }` block triggers an automated DevOps AI agent:

```
 Jenkins Logs (last 80 lines)
        │
        ▼
 jq constructs safe JSON payload
        │
        ▼
 Groq API  (llama-3.3-70b-versatile, temp=0.1)
        │
        ▼
 Structured diagnosis:
   • Root Cause — exact line or dependency that broke
   • Confidence — how certain the model is
   • Fix — code or config change to resolve it
   • Commands — terminal commands to apply the fix
        │
        ▼
 Slack message with full details
```

The low temperature (0.1) ensures deterministic, actionable output rather than creative suggestions.

---

## Infrastructure & Tech Stack

| Layer | Service | Details |
| :--- | :--- | :--- |
| **CI/CD Server** | EC2 `c7i-flex.large` | Jenkins + Docker engine + AWS CLI |
| **App Compute** | ASG `t3.micro` × 1–3 | Docker container + Nginx reverse proxy per instance |
| **Load Balancing** | Application LB | Routes port 80 across AZs, health checks on `/check` |
| **Container Registry** | ECR | 5-image lifecycle policy, SHA-tagged immutable builds |
| **Config Store** | SSM Parameter Store | `/myapp/deploy/image-tag` — the deployment source of truth |
| **Monitoring** | Lambda + EventBridge | Pings ALB every 5 min, alerts via SNS on failure |
| **Observability** | CloudWatch Agent | Streams Nginx access/error logs + CPU/memory metrics |
| **IaC** | Terraform | VPC, subnets, IGW, SGs, IAM roles, ALB, ASG, ECR, Lambda, SNS, CloudWatch |

---

## Security Model

| Boundary | Rule |
| :--- | :--- |
| **ALB** | Port 80 open to `0.0.0.0/0` (public traffic) |
| **Jenkins** | Ports 22 + 8080 restricted to `var.your_ip` only |
| **App instances** | Port 80 from ALB SG only; SSH from Jenkins SG only |
| **Docker** | Non-root `appuser` via multi-stage build |
| **IAM — Jenkins** | ECR push, SSM write, ASG refresh |
| **IAM — App** | ECR pull, SSM read |
| **IAM — Lambda** | Invoke self, SNS publish |

---

## Repository Structure

```
.
├── app.js                     # Express API — status dashboard, /check health, /api/status metrics
├── package.json               # Node.js 18 + Express 4.18
├── Dockerfile                 # Multi-stage Alpine build, non-root user, built-in healthcheck
├── Jenkinsfile                # 6-stage pipeline + AI failure analysis + Slack notifications
├── public/
│   └── index.html             # Real-time status dashboard UI
├── nginx/
│   └── app.conf               # Reverse proxy config — gzip, security headers, keepalive
├── lambda/
│   └── uptime-monitor.js      # EventBridge-triggered health checker → SNS alerts
├── live/
│   └── index.html             # Production dashboard snapshot
└── terraform/
    ├── main.tf                # AWS provider (eu-north-1)
    ├── variables.tf           # Input vars: region, IPs, instance types, AMI
    ├── outputs.tf             # Jenkins IP, ALB DNS, ECR URL, SNS ARN
    ├── vpc.tf                 # VPC, 2 public subnets (AZ-a, AZ-b), IGW, route tables
    ├── security-groups.tf     # Least-privilege ingress per resource
    ├── iam.tf                 # Jenkins + App EC2 instance profiles
    ├── iam_ssm.tf             # SSM read/write policies
    ├── ec2.tf                 # Jenkins instance + app userdata (deploy.sh + CloudWatch Agent)
    ├── ecr.tf                 # Repository + 5-image lifecycle rule
    ├── asg.tf                 # Launch template, ASG (1–3), scaling policies
    ├── alb.tf                 # ALB, target group, listener
    ├── ssm.tf                 # /myapp/deploy/image-tag parameter
    ├── lambda.tf              # Lambda function + EventBridge schedule (5 min)
    ├── sns.tf                 # Downtime email alert topic
    └── cloudwatch.tf          # Log groups (nginx, lambda) + CPU scaling alarms
```

---

## Deployment Guide

### Prerequisites

- AWS account with CLI configured (`aws configure`)
- Terraform ≥ 1.0 installed
- An EC2 key pair created in `eu-north-1`
- A Slack incoming webhook URL *(for notifications)*
- A Groq API key *(for AI failure analysis)*

### 1 — Clone

```bash
git clone https://github.com/Sambhav-gg/CI-CD.git
cd CI-CD
```

### 2 — Configure Terraform Variables

```bash
cd terraform

cat > terraform.tfvars <<EOF
alert_email   = "you@example.com"
key_pair_name = "your-ec2-keypair"
your_ip       = "203.0.113.42/32"   # Your public IP (whatismyip.com)
EOF
```

### 3 — Provision AWS Infrastructure

```bash
terraform init
terraform plan        # Review what will be created
terraform apply -auto-approve
```

Takes ~5 minutes. Note the outputs:

| Output | Used In |
| :--- | :--- |
| `jenkins_public_ip` | Browser + SSH |
| `alb_dns` | Jenkinsfile `ALB_DNS` env var |
| `ecr_repository_url` | Jenkinsfile `ECR_REGISTRY` env var |
| `sns_topic_arn` | Lambda environment |

> [!IMPORTANT]
> **SNS Confirmation**: Check your inbox and click "Confirm Subscription" to enable downtime email alerts.

### 4 — Set Up Jenkins

1. Open `http://<jenkins_public_ip>:8080`
2. Get the initial password:
   ```bash
   ssh -i key.pem ubuntu@<jenkins_public_ip> \
     "sudo cat /var/lib/jenkins/secrets/initialAdminPassword"
   ```
3. Install plugins: **Git**, **SSH Agent**, **Pipeline**, **Docker Pipeline**
4. Add credentials:

   | ID | Type | Value |
   | :--- | :--- | :--- |
   | `ec2-ssh-key` | SSH Username + Private Key | Username: `ubuntu`, paste `.pem` contents |
   | `slack-webhook-url` | Secret text | Slack incoming webhook URL |
   | `llm-api-key` | Secret text | Groq API key |

5. Create a **Pipeline** job pointing at your repository.

### 5 — Connect GitHub Webhook

**Repository Settings → Webhooks → Add webhook**

| Field | Value |
| :--- | :--- |
| Payload URL | `http://<jenkins_public_ip>:8080/github-webhook/` |
| Content type | `application/json` |
| Events | Just the push event |

### 6 — Push and Watch

```bash
git add . && git commit -m "initial deploy" && git push
```

Jenkins will automatically build, test, containerize, deploy, and verify.

---

## Zero-Downtime Deploys & Rollback

### How Deployments Work

1. Jenkins writes the new image tag (commit SHA) to **SSM** (`/myapp/deploy/image-tag`)
2. Jenkins triggers an **ASG Instance Refresh** (`MinHealthyPercentage: 50%`, `InstanceWarmup: 120s`)
3. ASG launches new instances → userdata pulls the tag from SSM → logs into ECR → starts container
4. ALB health checks pass → old instances terminate

**No code is overwritten in place.** Every deploy is a fresh instance with a known-good image.

### Rollback

**Automatic**: If the `Verify` stage fails, Jenkins cancels the Instance Refresh immediately.

**Manual**: Re-run a previous successful Jenkins build. It re-writes the old commit SHA to SSM and triggers a fresh Instance Refresh.

---

## API Endpoints

| Endpoint | Description |
| :--- | :--- |
| `GET /` | Real-time status dashboard UI |
| `GET /check` | Health check — `{"status":"ok","timestamp":"..."}` — used by ALB + Lambda |
| `GET /api/status` | Service statuses, system metrics (uptime, memory, CPU), and deployment metadata |

---

## Key Engineering Decisions

| Decision | Rationale |
| :--- | :--- |
| **SSM for deployment tags** (not env vars or AMI baking) | Decouples "what to deploy" from "how to deploy" — enables instant rollback by changing one parameter |
| **Instance Refresh** (not CodeDeploy) | No extra agent required; native ASG feature; simpler IAM |
| **`jq` for AI payloads** (not string interpolation) | Build logs contain quotes, newlines, and special characters that break shell escaping |
| **Commit SHA tags** (not `latest` only) | Every image is immutable and traceable; `latest` is also pushed for convenience |
| **7-day CloudWatch log retention** | Keeps costs near-zero while providing enough history for debugging |
| **ELB health checks** (not EC2) | Validates the app actually responds, not just that the instance is running |
| **CloudWatch CPU alarms for scaling** | Scale out at >70% for 2 min, scale in at <30% for 5 min — asymmetric to prevent flapping |

---

## Author

**Sambhav Garg**
B.Tech CSE — Bennett University

[GitHub](https://github.com/Sambhav-gg) · [LinkedIn](https://linkedin.com/in/sambhav-garg-255bb120b)

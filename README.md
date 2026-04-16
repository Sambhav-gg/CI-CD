# 🚀 Production CI/CD Infrastructure on AWS

> A complete production-grade CI/CD pipeline and AWS infrastructure built from scratch.  
> Every push to GitHub automatically builds, tests, containerizes, and deploys the app — with auto-scaling, uptime monitoring, and alerting.

![Status](https://img.shields.io/badge/status-live-brightgreen) ![AWS](https://img.shields.io/badge/cloud-AWS-FF9900?logo=amazonaws) ![Docker](https://img.shields.io/badge/container-Docker-2496ED?logo=docker) ![Terraform](https://img.shields.io/badge/iac-Terraform-7B42BC?logo=terraform) ![Jenkins](https://img.shields.io/badge/ci/cd-Jenkins-D24939?logo=jenkins) ![Node.js](https://img.shields.io/badge/runtime-Node.js-339933?logo=nodedotjs)


## 📌 What This Project Is

Most portfolio projects show a deployed link. This one shows the **infrastructure behind it**.

Every real production app runs on a system like this. This repository is a complete implementation — built, configured, and deployed from scratch:

- Code lives on **GitHub**
- Every push triggers **Jenkins** to build, test, and deploy automatically
- App runs inside a **Docker container** on EC2 behind **Nginx** as a reverse proxy
- **Application Load Balancer** distributes traffic across instances
- **Auto Scaling Group** adds/removes instances based on CPU load
- **Lambda** pings the app every 5 minutes and sends **SNS email alerts** on failure
- Everything is logged and monitored in **CloudWatch**
- The **entire AWS infrastructure** is provisioned as code using **Terraform**

---

## 🏗️ Architecture

```
                          ┌─────────────────────────────────────────────────────┐
                          │                    AWS VPC (eu-north-1)             │
                          │                                                     │
  You ──► GitHub          │   ┌──────────────┐         ┌──────────────────┐   │
            │             │   │  Jenkins EC2  │         │   App EC2 (ASG)  │   │
            │ webhook     │   │  t3.micro     │──SSH───►│   t3.micro       │   │
            ▼             │   │  port 8080    │         │   Docker + Nginx │   │
       Jenkins CI/CD ─────┼───┤               │         │   port 80 → 3000 │   │
            │             │   │  Builds image │         └────────┬─────────┘   │
            │             │   │  Pushes ECR   │                  │             │
            │             │   └──────────────┘                  │             │
            │             │                                      │             │
            │             │   ┌──────────────┐                  │             │
            └─────────────┼──►│     ECR      │──pull────────────┘             │
                          │   │ Docker images│                                 │
                          │   └──────────────┘                                 │
                          │                                                     │
  Internet ──────────────►│   ┌──────────────────────────────────────────┐    │
                          │   │  Application Load Balancer               │    │
                          │   │  my-app-alb-975584628.eu-north-1         │    │
                          │   └──────────────┬───────────────────────────┘    │
                          │                  │ port 80                         │
                          │                  ▼                                 │
                          │   ┌──────────────────────────────────────────┐    │
                          │   │  Auto Scaling Group (min 1 / max 3)      │    │
                          │   │  EC2 instances with Docker + Nginx       │    │
                          │   └──────────────────────────────────────────┘    │
                          │                                                     │
                          └─────────────────────────────────────────────────────┘

  ┌──────────────┐     every 5 mins    ┌─────────────────────────────────────┐
  │   Lambda     │────ping /check─────►│  ALB DNS                            │
  │  Node 18     │                     └─────────────────────────────────────┘
  └──────┬───────┘
         │ on failure
         ▼
  ┌──────────────┐
  │  SNS Topic   │──► sambhavgarg24@gmail.com
  └──────────────┘

  ┌──────────────┐
  │  CloudWatch  │  ← Nginx logs, Lambda logs, CPU metrics
  │  Alarms      │  ← CPU > 70% → scale out | CPU < 30% → scale in
  └──────────────┘
```

---

## 🔄 CI/CD Pipeline

```
Push to main
     │
     ▼
┌─────────────┐
│  Checkout   │  Clone repo, log commit SHA + branch
└──────┬──────┘
       │
       ▼
┌─────────────┐
│    Build    │  npm ci (clean install, respects lockfile)
└──────┬──────┘
       │
       ▼
┌─────────────┐        ┌────────────────────┐
│    Test     │──FAIL──►  Slack alert        │
└──────┬──────┘        │  + Rollback        │
       │ PASS          └────────────────────┘
       ▼
┌──────────────────┐
│  Docker Build    │  Multi-stage build (builder → production)
│  Tag: commit SHA │  node:18-alpine, non-root user
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│   ECR Push       │  016605188495.dkr.ecr.eu-north-1.amazonaws.com/my-app
│   Tag: SHA       │  Lifecycle: keep last 5 images
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│   SSH Deploy     │  Jenkins → App EC2 (10.0.1.93)
│   deploy.sh      │  docker pull → stop old → start new
└────────┬─────────┘
         │
         ▼
┌──────────────────┐        ┌────────────────────┐
│    Verify        │──FAIL──►  Rollback to prev  │
│  ALB /check      │        │  SHA + Slack alert │
└────────┬─────────┘        └────────────────────┘
         │ PASS
         ▼
┌──────────────────┐
│  Slack Success   │  Commit SHA · Branch · Live URL · Duration
└──────────────────┘
```

---

## 🛠️ Tech Stack

| Layer | Technology | Purpose |
|---|---|---|
| **Source Control** | GitHub | Code hosting, webhook triggers |
| **CI/CD** | Jenkins | Pipeline orchestration |
| **Containerization** | Docker (multi-stage) | Build + run app |
| **Registry** | AWS ECR | Store Docker images |
| **Compute** | AWS EC2 (x2) | Jenkins server + App server |
| **Reverse Proxy** | Nginx | port 80 → container port 3000 |
| **Load Balancing** | AWS ALB | Traffic distribution, health checks |
| **Auto Scaling** | AWS ASG | Scale on CPU metrics |
| **Monitoring** | AWS CloudWatch | Logs + CPU alarms |
| **Uptime Monitor** | AWS Lambda + EventBridge | Ping /check every 5 mins |
| **Alerting** | AWS SNS | Email on downtime |
| **IaC** | Terraform | Provision all AWS resources |
| **Runtime** | Node.js 18 + Express | Application |

---

## 📁 Project Structure

```
my-app/
├── app.js                        # Express server + /check + /api/status
├── package.json
├── public/
│   └── index.html                # Live status dashboard UI
│
├── Dockerfile                    # Multi-stage build
├── .dockerignore
├── Jenkinsfile                   # Full CI/CD pipeline
│
├── nginx/
│   └── app.conf                  # Reverse proxy config
│
├── lambda/
│   └── uptime-monitor.js         # Health check function
│
└── terraform/
    ├── main.tf                   # Provider config
    ├── variables.tf              # Input variables
    ├── outputs.tf                # ALB DNS, ECR URI, IPs
    ├── terraform.tfvars          # Your values (gitignored)
    ├── vpc.tf                    # VPC, subnets, IGW, routes
    ├── security-groups.tf        # ALB, Jenkins, App SGs
    ├── iam.tf                    # Roles for EC2 + Lambda
    ├── ecr.tf                    # ECR repo + lifecycle policy
    ├── ec2.tf                    # Both EC2s + userdata
    ├── alb.tf                    # ALB + target group + listener
    ├── asg.tf                    # ASG + launch template + policies
    ├── sns.tf                    # SNS topic + email subscription
    ├── lambda.tf                 # Lambda + EventBridge trigger
    └── cloudwatch.tf             # Alarms + log groups
```

---

## ☁️ AWS Infrastructure

All resources provisioned via Terraform in `eu-north-1`.

### EC2 Instances

| Instance | Type | Purpose | Ports |
|---|---|---|---|
| Jenkins EC2 | t3.micro | CI/CD server | 22 (your IP), 8080 (your IP) |
| App EC2 | t3.micro | Application server | 22 (Jenkins only), 80 (ALB only) |

### Security Groups

| Group | Inbound | Purpose |
|---|---|---|
| `app-alb-sg` | 80 from 0.0.0.0/0 | Internet → ALB |
| `app-jenkins-sg` | 22, 8080 from your IP | You → Jenkins |
| `app-app-sg` | 80 from ALB SG, 22 from Jenkins SG | ALB/Jenkins → App |

### Auto Scaling

| Metric | Threshold | Action |
|---|---|---|
| CPU Utilization | > 70% for 2 mins | Scale out (+1 instance) |
| CPU Utilization | < 30% for 5 mins | Scale in (-1 instance) |
| Min capacity | 1 | Always at least 1 instance |
| Max capacity | 3 | Never more than 3 instances |

### CloudWatch Log Groups

| Log Group | Source | Retention |
|---|---|---|
| `/app/nginx/access` | Nginx access logs | 7 days |
| `/app/nginx/error` | Nginx error logs | 7 days |
| `/aws/lambda/my-app-uptime-monitor` | Lambda invocations | 7 days |

---

## 🐳 Docker

Multi-stage build keeps the final image lean:

```dockerfile
# Stage 1 — install dependencies
FROM node:18-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

# Stage 2 — production image
FROM node:18-alpine AS production
WORKDIR /app
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
COPY --from=builder /app/node_modules ./node_modules
COPY app.js .
COPY public ./public
RUN chown -R appuser:appgroup /app
USER appuser
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -qO- http://localhost:3000/check || exit 1
CMD ["node", "app.js"]
```

**Images are tagged with the Git commit SHA** — every deploy is traceable and rollback is instant (re-run the previous SHA).

---

## 🚀 Deploy From Scratch

### Prerequisites
- AWS account
- Terraform installed
- AWS CLI configured (`aws configure`)
- Git + Node.js installed

### 1. Clone the repo
```bash
git clone https://github.com/yourusername/my-app.git
cd my-app
```

### 2. Configure Terraform
```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars with your values:
# alert_email   = "your@email.com"
# key_pair_name = "your-key-pair"
# your_ip       = "x.x.x.x/32"
```

### 3. Provision all AWS infrastructure
```bash
terraform init
terraform plan
terraform apply
```

Takes ~5 minutes. Outputs:
```
alb_dns            = "my-app-alb-xxx.eu-north-1.elb.amazonaws.com"
ecr_repository_url = "xxxx.dkr.ecr.eu-north-1.amazonaws.com/my-app"
jenkins_public_ip  = "xx.xx.xx.xx"
app_private_ip     = "10.0.1.xx"
sns_topic_arn      = "arn:aws:sns:eu-north-1:xxxx:my-app-downtime-alerts"
```

### 4. Confirm SNS email subscription
Check your inbox and click **Confirm subscription** in the AWS email.

### 5. Set up Jenkins
```
Visit: http://<jenkins_public_ip>:8080
Get initial password: sudo cat /var/lib/jenkins/secrets/initialAdminPassword

Install plugins:
  - Git
  - SSH Agent
  - Docker Pipeline
  - Pipeline

Add credentials:
  - ec2-ssh-key   → SSH private key (your .pem file)
  - slack-webhook → Slack incoming webhook URL
```

### 6. Add GitHub webhook
```
GitHub repo → Settings → Webhooks → Add webhook
Payload URL: http://<jenkins_public_ip>:8080/github-webhook/
Content type: application/json
Trigger: Just the push event
```

### 7. Push code — pipeline runs automatically
```bash
git add .
git commit -m "initial deploy"
git push origin main
```

### 8. Tear down everything
```bash
terraform destroy
```

---

## 🔐 Security

- Jenkins UI and SSH accessible from **your IP only**
- App EC2 SSH accessible from **Jenkins EC2 only** — not the internet
- App container runs as **non-root user**
- ECR images scanned on push
- Secrets managed via **Jenkins credentials** — never hardcoded
- IAM roles follow **least privilege** — Jenkins can push ECR, App can only pull

---

## 📊 App Endpoints

| Endpoint | Method | Response |
|---|---|---|
| `/` | GET | Status dashboard UI |
| `/check` | GET | `{ "status": "ok", "timestamp": "..." }` |
| `/api/status` | GET | Services, system metrics, deployment info |

---

## 🔁 How Rollback Works

Every Docker image is tagged with the **Git commit SHA**:
```
016605188495.dkr.ecr.eu-north-1.amazonaws.com/my-app:a3f9c12
```

To roll back to any previous version:
```bash
# SSH into App EC2
docker stop my-app
docker rm my-app
docker run -d --name my-app -p 3000:3000 \
  016605188495.dkr.ecr.eu-north-1.amazonaws.com/my-app:<previous-sha>
```

The Jenkinsfile also automatically rolls back to the previous image if the post-deploy health check fails.

---

## 📬 Alerting

| Alert | Trigger | Channel |
|---|---|---|
| Deploy failed | Jenkins pipeline failure | Slack #deployments |
| Deploy success | Jenkins pipeline success | Slack #deployments |
| App down | Lambda /check fails | Email via SNS |

Lambda checks the app every **5 minutes** via EventBridge. If `/check` returns anything other than HTTP 200, an email is sent immediately to `sambhavgarg24@gmail.com`.

---

## 🧠 Why This Is Better Than a Basic Pipeline

| Basic approach | This project |
|---|---|
| `git pull` on prod server | Pull pre-built Docker image from ECR |
| `npm install` on prod | Dependencies baked into image at build time |
| Hardcoded server IP | ASG-managed instances, ECR-based deploys |
| `echo` on failure | Slack alert + automatic rollback |
| No rollback | Re-run any previous commit SHA instantly |
| No external monitoring | Lambda uptime monitor + SNS alerts |
| Manual infra setup | One `terraform apply` = entire stack |
| No auto scaling | ASG scales 1→3 instances on CPU load |

---

## 👨‍💻 Author

**Sambhav Garg**  
B.Tech CSE — Bennett University  
[GitHub](https://github.com/yourusername) · [LinkedIn](https://linkedin.com/in/yourusername)

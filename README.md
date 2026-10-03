# 🍽️ AWS 3-Tier Web Application Infrastructure (Terraform)

A simple, production-ready, and maintainable AWS 3-tier infrastructure deployment for an outsource client using Terraform.

This repository provisions an edge-cached **CloudFront CDN + S3** static frontend, an internet-facing **Application Load Balancer (ALB)**, an **EC2 Auto Scaling Group (ASG)** running containerized backend services pulled from a private **AWS ECR** repository across private subnets, and an isolated **Multi-AZ RDS PostgreSQL** database tier, backed by remote state management using **Amazon S3** with **native state locking** (`use_lockfile = true`, eliminating the need for DynamoDB).

---

## 🏗️ 1. Architecture Overview

```mermaid
flowchart TD
    subgraph Internet["Public Internet"]
        Users["Client Users / Web Traffic"]
    end

    subgraph AWS["AWS Cloud (VPC: 10.0.0.0/16 across 2 Availability Zones)"]
        IGW["Internet Gateway (IGW)"]

        subgraph Edge["Edge & Presentation Tier"]
            CF["AWS CloudFront CDN (Global Edge)"]
            S3_Frontend["Private S3 Bucket (Frontend SPA Assets - OAC)"]
        end

        subgraph Tier1["Tier 1: Ingress / Public Subnets"]
            subgraph AZ1_Pub["AZ-a (10.0.1.0/24)"]
                ALB_A["ALB Node A"]
                NAT_A["NAT Gateway A"]
            end
            subgraph AZ2_Pub["AZ-b (10.0.2.0/24)"]
                ALB_B["ALB Node B"]
                NAT_B["NAT Gateway B (Prod)"]
            end
        end

        subgraph Tier2["Tier 2: Application / Private Subnets"]
            subgraph AZ1_App["AZ-a (10.0.11.0/24)"]
                EC2_1["EC2 Instance (Docker Engine)"]
            end
            subgraph AZ2_App["AZ-b (10.0.12.0/24)"]
                EC2_2["EC2 Instance (Docker Engine)"]
            end
            ASG["Auto Scaling Group (Min: 2, Max: 4)"]
        end

        subgraph Tier3["Tier 3: Database / Isolated Subnets"]
            subgraph AZ1_DB["AZ-a (10.0.21.0/24)"]
                RDS_Primary[("RDS PostgreSQL (Primary)")]
            end
            subgraph AZ2_DB["AZ-b (10.0.22.0/24)"]
                RDS_Standby[("RDS Standby (Synchronous Replica)")]
            end
        end

        subgraph Supporting["Supporting AWS Services"]
            ECR["AWS ECR (Private Container Registry)"]
            SSM["AWS SSM Session Manager (No SSH Port 22)"]
            S3_Backend["S3 Remote State Bucket (Native S3 State Locking)"]
            SM["AWS Secrets Manager (DB Credentials)"]
        end
    end

    Users -->|HTTPS 443| CF
    CF -->|Static Assets /* via OAC| S3_Frontend
    CF -->|API Traffic /api/* & /static/*| ALB_A & ALB_B
    Users -.->|Direct HTTP/HTTPS Option| IGW
    IGW --> ALB_A & ALB_B
    ALB_A & ALB_B -->|Port 8000 Target Group| EC2_1 & EC2_2
    EC2_1 & EC2_2 -->|Egress via NAT| ECR
    EC2_1 & EC2_2 -->|Egress via NAT| SSM
    EC2_1 & EC2_2 -->|Port 5432 (Chained SG)| RDS_Primary
    RDS_Primary -.->|Multi-AZ Sync| RDS_Standby
```

### Network Topology & Traffic Routing

| Subnet Tier | CIDR Blocks (Example) | Route Target | Components | Public Access |
|-------------|-----------------------|--------------|------------|---------------|
| **Public Subnets** | `10.0.1.0/24`, `10.0.2.0/24` | Internet Gateway (`igw-*`) | ALB, NAT Gateway(s) | Yes (Direct Internet) |
| **Private App Subnets** | `10.0.11.0/24`, `10.0.12.0/24` | NAT Gateway (`nat-*`) | EC2 Auto Scaling Group (Docker) | Egress only (No Public IP) |
| **Private DB Subnets** | `10.0.21.0/24`, `10.0.22.0/24` | Local VPC Only (No IGW / No NAT) | Multi-AZ RDS PostgreSQL | None (Completely Isolated) |

---

## 📂 2. Actual Project Directory Structure

Unlike complex over-engineered multi-folder setups, this project is organized directly inside `terraform/` with cohesive single-responsibility files:

```text
food-order-3tier-aws/
├── backend/                             # FastAPI backend application & Dockerfile
├── frontend/                            # React + Vite frontend SPA application
├── scripts/                             # Host deployment & rollback helper scripts
├── terraform/                           # Terraform Infrastructure Root
│   ├── main.tf                          # Provider config, S3 backend (use_lockfile), default tags
│   ├── variables.tf                     # Input variables with validation and sensible defaults
│   ├── outputs.tf                       # Exports endpoints, URLs, ARNs, and IDs
│   ├── terraform.tfvars.example         # Example configuration parameters
│   ├── vpc.tf                           # VPC, Subnets across 2 AZs, IGW, NAT Gateway, Route Tables
│   ├── security_groups.tf               # Chained security groups (Internet -> ALB -> App -> RDS)
│   ├── alb.tf                           # Application Load Balancer, Target Group & Health Check, Listener
│   ├── asg.tf                           # Launch Template (IMDSv2, SSM), Auto Scaling Group, Cloud-init
│   ├── ecr.tf                           # AWS ECR container registry, vulnerability scanning & lifecycle
│   ├── rds.tf                           # Multi-AZ RDS PostgreSQL, DB Subnet Group, Secrets Manager
│   └── frontend.tf                      # S3 static website bucket (OAC) + CloudFront CDN distribution
└── README.md                            # Comprehensive runbook and architecture documentation
```

---

## 🔍 3. Purpose & Breakdown of Each File

### 1. Provider & Remote State (`terraform/main.tf`)
- **Terraform Version Requirement**: Enforces `required_version = ">= 1.10.0"` to support **native S3 state locking**.
- **Remote State Backend**: Configures the `s3` backend with `use_lockfile = true` and `encrypt = true`. Terraform uses S3 conditional writes (`PutObject` with conditional checks) to create `.tflock` files, completely eliminating the cost and complexity of a separate DynamoDB table.
- **Provider & Default Tags**: Enforces standard organizational tags (`Project`, `Environment`, `ManagedBy`, `Tier`) across all AWS resources.

### 2. Networking Tier (`terraform/vpc.tf`)
- **`aws_vpc`**: Provisions a dedicated VPC (`10.0.0.0/16`) with DNS support and DNS hostnames enabled.
- **Subnets across 2 Availability Zones**:
  - `aws_subnet.public` (x2): Host the ALB and NAT Gateway.
  - `aws_subnet.private_app` (x2): Host EC2 Auto Scaling instances without public IPs.
  - `aws_subnet.private_db` (x2): Host Multi-AZ RDS PostgreSQL instances without internet routes.
- **Gateways & Routing**:
  - `aws_internet_gateway`: Inbound/outbound internet for public subnets.
  - `aws_nat_gateway` + `aws_eip`: Secure outbound egress for private EC2 instances (pulling ECR images, SSM connectivity, package updates).
  - Isolated database route tables with **no** route to the internet.

### 3. Security Groups (`terraform/security_groups.tf`)
Enforces strict least-privilege **Security Group Chaining**:
- **ALB Security Group**: Allows ingress on port `80` (HTTP) from `0.0.0.0/0`.
- **EC2 App Security Group**: Allows ingress on port `8000` **only** from the ALB Security Group using `security_groups = [aws_security_group.alb.id]`. No direct public access. Egress allows `0.0.0.0/0` for outbound NAT connectivity.
- **RDS DB Security Group**: Allows ingress on port `5432` (PostgreSQL) **only** from the EC2 App Security Group using `security_groups = [aws_security_group.app.id]`. Completely unreachable from the internet or ALB.

### 4. Container Registry (`terraform/ecr.tf`)
- **`aws_ecr_repository`**: Dedicated private Docker registry for storing backend API application images.
  - Image vulnerability scan-on-push enabled (`scan_on_push = true`).
  - Server-side AES-256 encryption enabled.
  - `force_delete = true` allows clean teardown during testing.
- **`aws_ecr_lifecycle_policy`**:
  - Automatically expires untagged images older than 14 days.
  - Retains only the last 30 tagged production images to optimize storage costs.

### 5. Load Balancer (`terraform/alb.tf`)
- **`aws_lb`**: Internet-facing Application Load Balancer deployed across the 2 public subnets.
- **`aws_lb_target_group`**: Directs traffic to EC2 instances on port `8000`. Configured with HTTP health checks (`/api/v1`), healthy threshold (3), interval (30s), and timeout (5s).
- **`aws_lb_listener`**: Listens on port `80` and forwards traffic to the target group.

### 6. Compute & Auto Scaling (`terraform/asg.tf`)
- **IAM Instance Profile**:
  - `AmazonSSMManagedInstanceCore`: AWS Systems Manager Session Manager access (secure shell without open SSH port 22 or key pairs).
  - `AmazonEC2ContainerRegistryReadOnly`: Allows EC2 instances to pull Docker images directly from ECR.
- **Launch Template**:
  - Amazon Linux 2023 AMI.
  - Enforces **IMDSv2** (`http_tokens = "required"`, `http_put_response_hop_limit = 1`) for cloud security compliance.
  - Cloud-init user data installs Docker Engine and AWS CLI.
  - Graceful Startup Sequence: Attempts to pull `$ECR_URL:$IMAGE_TAG`. If the image is not yet pushed to ECR (e.g. during first-time infrastructure provisioning), it automatically starts a lightweight placeholder container (`nginxdemos/hello:latest`) so ALB health checks pass and instances remain healthy.
- **Auto Scaling Group**:
  - Deploys across the 2 private application subnets.
  - Integrated with ALB target group (`health_check_type = "ELB"`).
  - `instance_refresh`: Rolling zero-downtime recycling when launch template or image updates occur.

### 7. Database Tier (`terraform/rds.tf`)
- **`aws_db_subnet_group`**: Groups private DB subnets across 2 AZs.
- **`random_password`**: Generates a high-entropy 20-character database password automatically.
- **`aws_secretsmanager_secret` & version**: Securely stores the generated DB password, username, host, and port in AWS Secrets Manager.
- **`aws_db_instance`**:
  - Engine: PostgreSQL (15.7).
  - `multi_az = true`: High availability with synchronous standby replica in second AZ.
  - Storage encryption enabled via AWS KMS.
  - `publicly_accessible = false`: Completely isolated inside private DB subnets.
  - `deletion_protection = false` by default for easy lab deployment (enable in production).

### 8. Frontend Static Hosting & CDN (`terraform/frontend.tf`)
- **`aws_s3_bucket`**: Private S3 bucket hosting React SPA static assets. Public access is 100% blocked.
- **Origin Access Control (OAC)**: Enforces SigV4 authentication so the bucket is accessible **only** through CloudFront.
- **`aws_cloudfront_distribution`**:
  - Global edge caching for static assets.
  - Custom error responses (`403` / `404` mapped to `/index.html` with HTTP 200) to support client-side React Router navigation.
  - Unified routing: Routes `/api/*` and `/static/*` directly to the ALB origin, eliminating CORS issues and browser mixed-content warnings.

### 9. Variables & Outputs (`terraform/variables.tf`, `outputs.tf`)
- Fully parameterized with sensible defaults for quick deployment.
- Exports all essential URLs, ARNs, DNS names, and credentials needed for CI/CD and verification.

---

## 🚀 4. Step-by-Step Deployment Runbook

Follow this guide to deploy the entire stack from scratch.

### Prerequisites

Ensure you have the following installed and configured on your machine:
- **AWS CLI v2** configured with administrator credentials (`aws configure`)
- **Terraform >= 1.10.0** (`terraform version`)
- **Docker Engine** running locally (`docker version`)
- **Node.js >= 18** and **npm** (`node -v`)

Verify your AWS identity:
```bash
aws sts get-caller-identity
```

---

### Step 1: Bootstrap the S3 Remote State Bucket (One-Time Setup)

Terraform 1.10+ uses native S3 state locking via S3 conditional writes. **No DynamoDB table is needed.**

Choose your AWS region (e.g., `ap-southeast-1`) and a globally unique bucket name:

```bash
STATE_BUCKET="food-order-tfstate-$(aws sts get-caller-identity --query Account --output text)-ap-southeast-1"
AWS_REGION="ap-southeast-1"

# 1. Create S3 bucket (ap-southeast-1 example)
aws s3api create-bucket \
  --bucket "$STATE_BUCKET" \
  --region "$AWS_REGION" \
  --create-bucket-configuration LocationConstraint="$AWS_REGION"

# 2. Enable Bucket Versioning (essential for state history and native state locking)
aws s3api put-bucket-versioning \
  --bucket "$STATE_BUCKET" \
  --versioning-configuration Status=Enabled

# 3. Enable Default SSE-S3 Encryption (AES256)
aws s3api put-bucket-encryption \
  --bucket "$STATE_BUCKET" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# 4. Block all public access
aws s3api put-public-access-block \
  --bucket "$STATE_BUCKET" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo "State bucket created: $STATE_BUCKET"
```

---

### Step 2: Configure Terraform Backend & Variables

1. Open `terraform/main.tf` and update the `bucket` attribute in the `backend "s3"` block to match your bucket name:

```hcl
terraform {
  required_version = ">= 1.10.0"

  backend "s3" {
    bucket       = "food-order-tfstate-<YOUR_ACCOUNT_ID>-ap-southeast-1"
    key          = "networking/terraform.tfstate"
    region       = "ap-southeast-1"
    encrypt      = true
    use_lockfile = true # Native S3 state locking
  }
}
```

2. Create your `terraform.tfvars` from the example template:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Review `terraform.tfvars`. The defaults are pre-configured to work out of the box with `ecr_repository_url = ""` (which automatically links the newly provisioned ECR registry).

---

### Step 3: Provision AWS Infrastructure via Terraform

From inside the `terraform/` directory:

```bash
# 1. Initialize Terraform with S3 remote state and native locking
terraform init

# 2. Validate configuration
terraform validate

# 3. Review planned resources
terraform plan -out=tfplan

# 4. Apply infrastructure
terraform apply tfplan
```

> [!NOTE]
> RDS PostgreSQL provisioning takes approximately 5–10 minutes. 
> When complete, Terraform outputs all key endpoints, including `alb_dns_name`, `ecr_repository_url`, `frontend_bucket_name`, and `cloudfront_domain_name`.
> The EC2 instances boot and start a placeholder hello container so ALB health checks pass while waiting for the application container image.

---

### Step 4: Build & Push Backend Application Container to ECR

Once Terraform creates the ECR repository, build and push your backend Docker image:

```bash
# Export outputs for convenient CLI use
ECR_URL=$(terraform output -raw ecr_repository_url)
AWS_REGION=$(terraform output -raw aws_region)
ASG_NAME=$(terraform output -raw asg_name)

echo "ECR Repository: $ECR_URL"

# 1. Authenticate Docker to AWS ECR
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_URL"

# 2. Build and tag the backend container image
cd ../backend
docker build -t "$ECR_URL:latest" .

# 3. Push image to ECR
docker push "$ECR_URL:latest"

# 4. Trigger ASG Instance Refresh to deploy the new container to EC2 instances
aws autoscaling start-instance-refresh \
  --region "$AWS_REGION" \
  --auto-scaling-group-name "$ASG_NAME" \
  --preferences '{"MinHealthyPercentage": 50, "InstanceWarmup": 180}'

echo "Backend image deployed. Instance refresh in progress..."
```

---

### Step 5: Build & Deploy Frontend SPA to S3 + CloudFront

Deploy the React frontend static build to the S3 bucket with CloudFront CDN distribution:

```bash
# Navigate to frontend directory
cd ../frontend

# 1. Install dependencies and build static assets
npm install
npm run build

# 2. Return to terraform directory to query bucket & CloudFront ID
cd ../terraform
FRONTEND_BUCKET=$(terraform output -raw frontend_bucket_name)
CLOUDFRONT_ID=$(terraform output -raw cloudfront_distribution_id)

# 3. Sync static files to the private S3 bucket
aws s3 sync ../frontend/dist/ "s3://$FRONTEND_BUCKET" --delete

# 4. Invalidate CloudFront cache so changes take effect globally
aws cloudfront create-invalidation \
  --distribution-id "$CLOUDFRONT_ID" \
  --paths "/*"

echo "Frontend deployed successfully!"
```

---

### Step 6: Verification & Operations

1. **Access Frontend via CloudFront CDN**:
   ```bash
   terraform output frontend_url
   # Example: https://d1234567890abc.cloudfront.net
   ```
   Open the URL in your browser. The React application loads from CloudFront and automatically queries `/api/v1` via CloudFront's reverse proxy behavior to the ALB.

2. **Verify ALB Health Check Directly**:
   ```bash
   ALB_URL=$(terraform output -raw alb_dns_name)
   curl -I "http://$ALB_URL/api/v1"
   ```

3. **Retrieve Database Credentials Securely**:
   DB credentials are never printed in plain text:
   ```bash
   SECRET_ARN=$(terraform output -raw rds_secret_arn)
   aws secretsmanager get-secret-value --secret-id "$SECRET_ARN" --query SecretString --output text | jq .
   ```

4. **Connect to EC2 Instances without SSH Key (AWS Systems Manager)**:
   Because port 22 is disabled, connect to instances via SSM Session Manager:
   ```bash
   # Get Instance ID of a running app instance
   INSTANCE_ID=$(aws ec2 describe-instances --region ap-southeast-1 \
     --filters "Name=tag:aws:autoscaling:groupName,Values=$ASG_NAME" "Name=instance-state-name,Values=running" \
     --query "Reservations[0].Instances[0].InstanceId" --output text)

   # Start an interactive shell session
   aws ssm start-session --target "$INSTANCE_ID" --region ap-southeast-1
   ```

   Once inside the instance, inspect running Docker containers:
   ```bash
   sudo docker ps
   sudo docker logs food_api
   ```

---

### Step 7: Teardown / Resource Destruction

To avoid ongoing AWS charges, destroy the resources when finished:

```bash
cd terraform

# 1. Empty the frontend S3 bucket (S3 cannot be deleted while containing files)
FRONTEND_BUCKET=$(terraform output -raw frontend_bucket_name)
aws s3 rm "s3://$FRONTEND_BUCKET" --recursive

# 2. Run Terraform destroy
terraform destroy -auto-approve
```

---

## 🛡️ 5. Senior Cloud Engineer Best Practices & Guardrails

1. **Security Group Chaining**:
   Never use open CIDR blocks (`0.0.0.0/0`) between tiers. Ingress rules strictly reference `source_security_group_id`:
   - ALB SG allows traffic from the internet (`0.0.0.0/0`).
   - App EC2 SG allows traffic **only** from the ALB SG.
   - RDS DB SG allows traffic **only** from the App EC2 SG.
2. **Zero SSH / Bastionless Management**:
   Never create AWS key pairs or open port 22 in security groups. Using `AmazonSSMManagedInstanceCore` allows full CLI and console access through AWS Systems Manager, logged to CloudTrail.
3. **IMDSv2 Enforcement**:
   Launch Templates configure `http_tokens = "required"` and `http_put_response_hop_limit = 1` to prevent SSRF vulnerabilities from accessing EC2 instance metadata.
4. **Native S3 State Locking (No DynamoDB Required)**:
   - Starting with **Terraform 1.10+**, the `s3` backend natively supports distributed state locking via S3 conditional writes.
   - Simply configure `use_lockfile = true` in the `backend "s3"` block.
   - Terraform automatically writes and checks a `<state-key>.tflock` file directly in the S3 bucket using HTTP conditional requests (`If-None-Match`).
   - **Key Advantages**:
     - **Cost Optimization**: Eliminates the provisioned read/write capacity or per-request costs of DynamoDB.
     - **Reduced Complexity**: Simplifies bootstrap infrastructure from two services (S3 + DynamoDB) down to just an S3 bucket.
     - **Streamlined IAM Permissions**: Automation roles and CI/CD pipelines only need S3 permissions (`s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`, `s3:ListBucket`) on the state bucket, without requiring any `dynamodb:*` actions.
     - **Deprecation Alignment**: `dynamodb_table` is deprecated starting in Terraform 1.11+.
5. **Accidental Destruction Protection**:
   Protect state and production database resources from accidental deletion with lifecycle rules:
   ```hcl
   lifecycle {
     prevent_destroy = true
   }
   ```
6. **Secrets Handling**:
   Never commit `.tfvars` files containing plaintext passwords to version control. Passwords are generated via Terraform `random_password`, stored in AWS Secrets Manager, and read by the application at startup.

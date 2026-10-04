# 🍽️ AWS 3-Tier Web Application Infrastructure

A simple, production-ready, and maintainable AWS 3-tier infrastructure deployment for an outsource client using Terraform.

This repository provisions an edge-cached **CloudFront CDN + S3** static frontend, an internet-facing **Application Load Balancer (ALB)**, an **EC2 Auto Scaling Group (ASG)** running containerized backend services pulled from a private **Amazon ECR** repository across private subnets, and an isolated **Multi-AZ RDS PostgreSQL** database tier.

Terraform remote state is stored in **Amazon S3** with **native S3 state locking** using `use_lockfile = true`, eliminating the need for a DynamoDB lock table.

---

## 🏗️ 1. Architecture Overview

```mermaid
flowchart TD

    Users["Users"]

    subgraph AWS["AWS Cloud"]

        CF["CloudFront CDN"]

        S3["Private S3 Bucket<br/>React SPA Assets<br/>OAC Enabled"]

        subgraph VPC["VPC: 10.0.0.0/16"]

            IGW["Internet Gateway"]

            subgraph Public["Public Subnets"]

                ALB["Internet-facing<br/>Application Load Balancer"]

                NAT1["NAT Gateway<br/>AZ-a"]

                NAT2["NAT Gateway<br/>AZ-b"]

            end

            subgraph PrivateApp["Private Application Subnets"]

                EC2_1["EC2 Instance<br/>Docker Engine<br/>AZ-a"]

                EC2_2["EC2 Instance<br/>Docker Engine<br/>AZ-b"]

                ASG["Auto Scaling Group<br/>Min: 2 / Max: 4"]

            end

            subgraph PrivateDB["Private Database Subnets"]

                RDS["RDS PostgreSQL<br/>Multi-AZ"]

            end

        end

        ECR["Amazon ECR<br/>Private Container Registry"]

        SSM["AWS Systems Manager<br/>Session Manager"]

        Secrets["AWS Secrets Manager<br/>DB Credentials"]

        TFState["Amazon S3<br/>Terraform Remote State<br/>Native S3 Locking"]

    end

    Users -->|HTTPS 443| CF

    CF -->|Static Assets| S3

    CF -->|/api/*| ALB

    IGW --> ALB

    ALB -->|HTTP 8000| EC2_1

    ALB -->|HTTP 8000| EC2_2

    ASG -.->|Manages| EC2_1

    ASG -.->|Manages| EC2_2

    EC2_1 -->|Outbound Internet| NAT1

    EC2_2 -->|Outbound Internet| NAT2

    NAT1 --> IGW

    NAT2 --> IGW

    EC2_1 -->|Pull Docker Image| ECR

    EC2_2 -->|Pull Docker Image| ECR

    EC2_1 -->|SSM Session| SSM

    EC2_2 -->|SSM Session| SSM

    EC2_1 -->|PostgreSQL 5432| RDS

    EC2_2 -->|PostgreSQL 5432| RDS

    EC2_1 -->|Read DB Credentials| Secrets

    EC2_2 -->|Read DB Credentials| Secrets
```

### Architecture Flow

The application traffic follows this flow:

```text
                         ┌──────────────┐
                         │    Users     │
                         └──────┬───────┘
                                │ HTTPS
                                ▼
                       ┌─────────────────┐
                       │   CloudFront    │
                       │      CDN        │
                       └───────┬─────────┘
                               │
                    ┌──────────┴──────────┐
                    │                     │
              Static Assets            /api/*
                    │                     │
                    ▼                     ▼
             ┌───────────┐          ┌───────────┐
             │ S3 Bucket │          │    ALB    │
             │   React   │          └─────┬─────┘
             └───────────┘                │
                                          │ :8000
                                   ┌──────┴──────┐
                                   │     ASG     │
                                   └──────┬──────┘
                                          │
                              ┌───────────┴───────────┐
                              │                       │
                              ▼                       ▼
                         ┌─────────┐             ┌─────────┐
                         │   EC2   │             │   EC2   │
                         │ Docker  │             │ Docker  │
                         └────┬────┘             └────┬────┘
                              │                       │
                              └──────────┬────────────┘
                                         │
                                         │ :5432
                                         ▼
                                  ┌──────────────┐
                                  │ RDS PostgreSQL│
                                  │   Multi-AZ    │
                                  └──────────────┘
```

### Supporting Services

```text
EC2
 ├── Pulls backend images from Amazon ECR
 ├── Uses AWS Systems Manager Session Manager
 └── Reads database credentials from AWS Secrets Manager

Terraform
 └── Stores remote state in Amazon S3
      └── Uses native S3 state locking (.tflock)
```

---

## 🌐 Network Topology & Traffic Routing

| Subnet Tier             | CIDR Blocks                    | Route Target     | Components             | Public Access            |
| ----------------------- | ------------------------------ | ---------------- | ---------------------- | ------------------------ |
| **Public Subnets**      | `10.0.1.0/24`, `10.0.2.0/24`   | Internet Gateway | ALB, NAT Gateways      | Internet-facing          |
| **Private App Subnets** | `10.0.11.0/24`, `10.0.12.0/24` | NAT Gateway      | EC2 Auto Scaling Group | No inbound public access |
| **Private DB Subnets**  | `10.0.21.0/24`, `10.0.22.0/24` | Local VPC only   | RDS PostgreSQL         | No internet access       |

### Traffic Rules

| Source     | Destination      |       Port | Purpose                                |
| ---------- | ---------------- | ---------: | -------------------------------------- |
| Internet   | CloudFront       |      `443` | HTTPS frontend access                  |
| CloudFront | S3               |      HTTPS | React static assets via OAC            |
| CloudFront | ALB              | HTTP/HTTPS | `/api/*` API traffic                   |
| ALB        | EC2              |     `8000` | Backend API                            |
| EC2        | RDS              |     `5432` | PostgreSQL                             |
| EC2        | ECR              |      `443` | Pull Docker images                     |
| EC2        | AWS SSM          |      `443` | Session Manager                        |
| EC2        | Internet via NAT |      `443` | Package updates and AWS service access |

---

## 🔐 Security Group Flow

The infrastructure uses security-group chaining between application tiers:

```text
Internet
   │
   │ HTTPS
   ▼
┌────────────────────┐
│    ALB Security    │
│       Group        │
└─────────┬──────────┘
          │
          │ TCP 8000
          ▼
┌────────────────────┐
│    App EC2         │
│    Security Group  │
└─────────┬──────────┘
          │
          │ TCP 5432
          ▼
┌────────────────────┐
│    RDS Security    │
│       Group        │
└────────────────────┘
```

The rules are:

* ALB accepts public web traffic.
* EC2 accepts port `8000` **only from the ALB security group**.
* RDS accepts port `5432` **only from the EC2 application security group**.
* RDS has no public access.
* SSH port `22` is not exposed.
* EC2 management is performed through AWS Systems Manager Session Manager.

---

## 📂 2. Project Directory Structure

Terraform is maintained in a **separate infrastructure repository** from the application source code.

### Application Repository

```text
food-order-3tier-aws/
├── backend/                    # FastAPI backend application
├── frontend/                   # React + Vite frontend SPA
├── scripts/                    # Deployment and helper scripts
├── docker-compose.yml
├── docker-compose.override.yml
├── Makefile
└── README.md
```

### Infrastructure Repository

```text
food-order-3tier-infra/
├── main.tf                     # Provider, backend, default tags
├── variables.tf                # Input variables and validation
├── outputs.tf                  # Infrastructure outputs
├── terraform.tfvars.example    # Example configuration
├── vpc.tf                      # VPC, subnets, routes, IGW, NAT
├── security_groups.tf          # ALB, App and RDS security groups
├── alb.tf                      # Application Load Balancer
├── asg.tf                      # Launch Template and Auto Scaling Group
├── ecr.tf                      # Amazon ECR repository
├── rds.tf                      # RDS PostgreSQL and Secrets Manager
├── frontend.tf                 # S3 frontend bucket and CloudFront
├── ssm.tf                      # Systems Manager configuration
├── .terraform.lock.hcl         # Terraform provider lock file
├── .gitignore
└── README.md
```

---

🔄 Repository Separation

The application and infrastructure are intentionally separated:

GitHub
│
├── food-order-3tier-aws
│   │
│   ├── Backend
│   ├── Frontend
│   ├── Docker
│   └── Application CI/CD
│
└── food-order-3tier-infra
    │
    ├── Terraform
    ├── AWS Infrastructure
    └── Infrastructure CI/CD

This separation means:

Application changes do not require Terraform changes.
Infrastructure changes do not require rebuilding the application.
Application CI/CD handles Docker/ECR/ASG deployment.
Infrastructure CI/CD handles Terraform.
Terraform state remains in the S3 backend.
Infrastructure source code is version-controlled independently.
🚀 3. Infrastructure Deployment Flow
Developer
    │
    ▼
food-order-3tier-infra
    │
    ▼
Terraform
    │
    ├── terraform fmt
    ├── terraform validate
    ├── terraform plan
    └── terraform apply
            │
            ▼
       AWS Infrastructure

Application deployment is handled separately:

Developer
    │
    ▼
food-order-3tier-aws
    │
    ├───────────────┐
    │               │
    ▼               ▼
Backend           Frontend
    │               │
    ▼               ▼
Docker/ECR       Vite Build
    │               │
    ▼               ▼
ASG Refresh      S3 Upload
                    │
                    ▼
               CloudFront
🗄️ Terraform Remote State

Terraform state is stored remotely in Amazon S3:

S3 Bucket:
food-order-tfstate-<ACCOUNT_ID>-ap-southeast-1

State Key:
networking/terraform.tfstate

Lock:
networking/terraform.tfstate.tflock

The backend uses native S3 state locking:

terraform {
  required_version = ">= 1.10.0"

  backend "s3" {
    bucket       = "food-order-tfstate-<ACCOUNT_ID>-ap-southeast-1"
    key          = "networking/terraform.tfstate"
    region       = "ap-southeast-1"
    encrypt      = true
    use_lockfile = true
  }
}

No DynamoDB table is required for state locking.

⚠️ Important

The Terraform state must not be committed to Git.

The following files/directories should remain ignored:

.terraform/
*.tfstate
*.tfstate.*
*.tfplan
terraform.tfvars
*.auto.tfvars

The following files should be committed:

*.tf
terraform.tfvars.example
.terraform.lock.hcl
.gitignore
README.md

``

# ==============================================================================
# VPC, Subnets, Gateways, and Route Tables (3-Tier Networking)
# ==============================================================================
# Architecture Standard:
# - Strict isolation between Public, Application, and Database tiers.
# - High availability achieved by provisioning across 2 distinct Availability Zones.
# - NAT Gateway deployed in Public Subnet A to enable outbound egress for EC2 instances
#   (Docker image pulls from ECR, AWS Systems Manager connectivity, OS updates)
#   without exposing EC2 instances to inbound internet traffic.
# - Database subnets are completely isolated with no default route to IGW or NAT.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Virtual Private Cloud (VPC)
# ------------------------------------------------------------------------------
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-${var.environment}-vpc"
  }
}

# ------------------------------------------------------------------------------
# 2. Internet Gateway (IGW)
# ------------------------------------------------------------------------------
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-${var.environment}-igw"
  }
}

# ------------------------------------------------------------------------------
# 3. Subnets Tier 1: Public Subnets (ALB & NAT Gateway)
# ------------------------------------------------------------------------------
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-${var.environment}-public-${var.availability_zones[count.index]}"
    Tier = "Public"
  }
}

# ------------------------------------------------------------------------------
# 4. Subnets Tier 2: Private Application Subnets (EC2 Auto Scaling Group)
# ------------------------------------------------------------------------------
resource "aws_subnet" "private_app" {
  count                   = 2
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.private_app_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-${var.environment}-private-app-${var.availability_zones[count.index]}"
    Tier = "Private-App"
  }
}

# ------------------------------------------------------------------------------
# 5. Subnets Tier 3: Private Database Subnets (Multi-AZ RDS)
# ------------------------------------------------------------------------------
resource "aws_subnet" "private_db" {
  count                   = 2
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.private_db_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-${var.environment}-private-db-${var.availability_zones[count.index]}"
    Tier = "Private-DB"
  }
}

# ------------------------------------------------------------------------------
# 6. Elastic IP & NAT Gateway
# ------------------------------------------------------------------------------
# Deployed in Public Subnet 0 (ap-southeast-1a) to provide egress for private app subnets.
resource "aws_eip" "nat" {
  domain = "vpc"

  depends_on = [aws_internet_gateway.this]

  tags = {
    Name = "${var.project_name}-${var.environment}-nat-eip"
  }
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  depends_on = [aws_internet_gateway.this]

  tags = {
    Name = "${var.project_name}-${var.environment}-nat-gw"
  }
}

# ------------------------------------------------------------------------------
# 7. Route Tables & Default Routes
# ------------------------------------------------------------------------------

# Public Route Table: Routes 0.0.0.0/0 to the Internet Gateway
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-public-rt"
    Tier = "Public"
  }
}

# Private App Route Table: Routes 0.0.0.0/0 to the NAT Gateway
resource "aws_route_table" "private_app" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-private-app-rt"
    Tier = "Private-App"
  }
}

# Private DB Route Table: Completely isolated with local VPC routing only
resource "aws_route_table" "private_db" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-${var.environment}-private-db-rt"
    Tier = "Private-DB"
  }
}

# ------------------------------------------------------------------------------
# 8. Route Table Associations
# ------------------------------------------------------------------------------

# Associate Public Subnets with Public Route Table
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Associate Private App Subnets with Private App Route Table
resource "aws_route_table_association" "private_app" {
  count          = 2
  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private_app.id
}

# Associate Private DB Subnets with Private DB Route Table
resource "aws_route_table_association" "private_db" {
  count          = 2
  subnet_id      = aws_subnet.private_db[count.index].id
  route_table_id = aws_route_table.private_db.id
}

# ------------------------------------------------------------------------------
# 9. RDS DB Subnet Group
# ------------------------------------------------------------------------------
# Required by AWS RDS for Multi-AZ deployments spanning at least 2 Availability Zones.
resource "aws_db_subnet_group" "this" {
  name        = "${var.project_name}-${var.environment}-db-subnet-group"
  description = "Isolated database subnet group for ${var.project_name} (${var.environment})"
  subnet_ids  = aws_subnet.private_db[*].id

  tags = {
    Name = "${var.project_name}-${var.environment}-db-subnet-group"
    Tier = "Private-DB"
  }
}

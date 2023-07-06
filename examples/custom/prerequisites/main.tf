# Create a random string to make tags more unique.
resource "random_string" "default" {
  length  = 6
  numeric = false
  special = false
  upper   = false
}

# Make an S3 bucket to store scripts.
resource "aws_s3_bucket" "default" {
  bucket = "custom-scripts-${random_string.default.result}"
  tags = {
    Name  = "custom-scripts-${random_string.default.result}"
    owner = "Robert de Bock"
  }
}

# Limit access to the S3 bucket.
resource "aws_s3_bucket_public_access_block" "default" {
  bucket                  = aws_s3_bucket.default.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Add the custom script for the Vault hosts to the bucket.
resource "aws_s3_object" "vault" {
  bucket = aws_s3_bucket.default.id
  etag   = filemd5("./scripts/my_script_vault.sh")
  key    = "my_script_vault.sh"
  source = "${path.module}/scripts/my_script_vault.sh"
}

# Add the custom script for the bastion host to the bucket.
resource "aws_s3_object" "bastion" {
  bucket = aws_s3_bucket.default.id
  etag   = filemd5("./scripts/my_script_bastion.sh")
  key    = "my_script_bastion.sh"
  source = "${path.module}/scripts/my_script_bastion.sh"
}

# Create a VCP.
resource "aws_vpc" "default" {
  cidr_block = "10.70.0.0/16"
  tags = {
    Name    = "custom"
    owner   = "robertdebock"
    purpose = "ci-testing"
  }
}

# Create an internet gateway.
resource "aws_internet_gateway" "default" {
  vpc_id = aws_vpc.default.id
  tags = {
    Name    = "custom"
    owner   = "robertdebock"
    purpose = "ci-testing"
  }
}

# Create a routing table for the internet gateway.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.default.id
  tags = {
    Name = "custom-public"
  }
}

# Add an internet route to the internet gateway.
resource "aws_route" "public" {
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.default.id
  route_table_id         = aws_route_table.public.id
}

# Create a routing table for the nat gateway.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.default.id
  tags = {
    Name = "custom-private"
  }
}

# Reserve external IP addresses. (It's for the NAT gateways.)
resource "aws_eip" "default" {
  vpc = true
}

# Create the same amount of subnets as the amount of instances when we create the vpc.
resource "aws_subnet" "private" {
  count             = length(data.aws_availability_zones.default.names)
  availability_zone = data.aws_availability_zones.default.names[count.index]
  cidr_block        = cidrsubnet(aws_vpc.default.cidr_block, 8, count.index + 64)
  vpc_id            = aws_vpc.default.id
  tags = {
    Name    = "custom-private"
    owner   = "robertdebock"
    purpose = "ci-testing"
  }
}

# Make NAT gateways, for the Vault instances to reach the internet.
resource "aws_nat_gateway" "default" {
  allocation_id = aws_eip.default.id
  subnet_id     = aws_subnet.public[0].id
  tags = {
    Name    = "custom"
    owner   = "robertdebock"
    purpose = "ci-testing"
  }
  depends_on = [aws_internet_gateway.default]
}

# Add an internet route to the nat gateway.
resource "aws_route" "private" {
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.default.id
  route_table_id         = aws_route_table.private.id
}

# Find availability_zones in this region.
data "aws_availability_zones" "default" {
  state = "available"
}

# Create the same amount of subnets as the amount of instances when we create the vpc.
resource "aws_subnet" "public" {
  count             = length(data.aws_availability_zones.default.names)
  availability_zone = data.aws_availability_zones.default.names[count.index]
  cidr_block        = cidrsubnet(aws_vpc.default.cidr_block, 8, count.index)
  vpc_id            = aws_vpc.default.id
  tags = {
    Name    = "custom-public"
    owner   = "robertdebock"
    purpose = "ci-testing"
  }
}

# Associate the subnet to the routing table.
resource "aws_route_table_association" "public" {
  count          = length(data.aws_availability_zones.default.names)
  route_table_id = aws_route_table.public.id
  subnet_id      = aws_subnet.public[count.index].id
}

# Associate the subnet to the routing table.
resource "aws_route_table_association" "private" {
  count          = length(data.aws_availability_zones.default.names)
  route_table_id = aws_route_table.private.id
  subnet_id      = aws_subnet.private[count.index].id
}

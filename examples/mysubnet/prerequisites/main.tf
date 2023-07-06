# Create a VCP.
resource "aws_vpc" "default" {
  cidr_block = "192.168.0.0/16"
  tags = {
    Name    = "mysubnet"
    owner   = "robertdebock"
    purpose = "ci-testing"
  }
}

# Create an internet gateway.
resource "aws_internet_gateway" "default" {
  vpc_id = aws_vpc.default.id
  tags = {
    name    = "mysubnet"
    owner   = "robertdebock"
    purpose = "ci-testing"
  }
}

# Create a routing table for the internet gateway.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.default.id
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
    Name    = "mysubnet-private"
    owner   = "robertdebock"
    purpose = "ci-testing"
  }
}

# Make NAT gateways, for the Vault instances to reach the internet.
resource "aws_nat_gateway" "default" {
  allocation_id = aws_eip.default.id
  subnet_id     = aws_subnet.public[0].id
  tags = {
    Name    = "mysubnet"
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
    Name    = "mysubnet-public"
    owner   = "robertdebock"
    purpose = "ci-testing"
  }
}

# Create extra subnets to mock an environment with multiple subnets.
resource "aws_subnet" "extra" {
  count             = length(data.aws_availability_zones.default.names)
  availability_zone = data.aws_availability_zones.default.names[count.index]
  cidr_block        = "192.168.${count.index + 192}.0/24"
  vpc_id            = aws_vpc.default.id
  tags = {
    Name    = "mysubnet-extra"
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

# Create a security group that will be given access to Vault later.
resource "aws_security_group" "default" {
  description = "Allow Vault accesss"
  name        = "My extra security group"
  vpc_id      = aws_vpc.default.id
}

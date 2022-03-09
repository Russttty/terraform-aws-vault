locals {

  # Resolve the ip_addr, either set using `api_addr` or the created resource.
  api_addr = coalesce(var.api_addr, "https://${aws_lb.api.dns_name}:8200")

  # Combine the variable `tags` with specific prefixes.
  tags             = merge({ Name = "${var.name}-${random_string.default.result}" }, var.tags)
  bastion_tags     = merge({ Name = "bastion-${var.name}-${random_string.default.result}" }, var.tags)
  private_tags     = merge({ Name = "private-${var.name}-${random_string.default.result}" }, var.tags)
  public_tags      = merge({ Name = "public-${var.name}-${random_string.default.result}" }, var.tags)
  api_tags         = merge({ Name = "api-${var.name}-${random_string.default.result}" }, var.tags)
  replication_tags = merge({ Name = "replication-${var.name}-${random_string.default.result}" }, var.tags)

  target_group_arns = compact([aws_lb_target_group.api.arn, try(aws_lb_target_group.replication[0].arn, null)])
  # A map from `size` to `instance_type`.
  _instance_type = {
    custom      = var.instance_type
    development = "t4g.nano"
    minimum     = "m5.large"
    small       = "m5.xlarge"
    large       = "m5.2xlarge"
    maximum     = "m5.4xlarge"
  }
  instance_type = local._instance_type[var.size]

  # A map from `size` to `volume_type`.
  _volume_type = {
    custom      = var.volume_type
    development = "gp2"
    minimum     = "io1"
    small       = "io1"
    large       = "io1"
    maximum     = "io1"
  }
  volume_type = local._volume_type[var.size]

  # A map from `size` to `volume_size`.
  _volume_size = {
    custom      = var.volume_size
    development = 8
    minimum     = 100
    small       = 100
    large       = 200
    maximum     = 200
  }
  volume_size = local._volume_size[var.size]

  # A map from `size` to `volume_iops`.
  _volume_iops = {
    custom      = var.volume_iops
    development = 0
    minimum     = 3000
    small       = 3000
    large       = 10000
    maximum     = 10000
  }
  volume_iops = local._volume_iops[var.size]

  # Resolve the key, either set using `key_name` or place using `key_filename`.
  key_name = try(aws_key_pair.default[0].id, var.key_name)

  # Form the cidr_block based on a variable.
  cidr_block = "${var.vpc_cidr_block_start}.0.0/16"

  # Select the vpc_id, either created or set as a variable.
  vpc_id = try(aws_vpc.default[0].id, var.vpc_id)

  # Select the private_subnet_ids, either set as a variable or created.
  private_subnet_ids = coalescelist(var.private_subnet_ids, aws_subnet.private[*].id)

  # Select the public_subnet_ids, either created or set as a variable.
  public_subnet_ids = coalescelist(var.public_subnet_ids, aws_subnet.public[*].id)

  # Select the gateway_id, either the created resource or the found resource.
  gateway_id = try(aws_internet_gateway.default[0].id, data.aws_internet_gateway.default[0].id)

  # Compose the package name based on the `vault_type`.
  _vault_package = {
    enterprise = "vault-enterprise-${var.vault_version}+ent-1"
    opensource = "vault-${var.vault_version}"
  }
  vault_package = local._vault_package[var.vault_type]

  # The instance_type can be of the type "x86_64" or "arm64". This mapping sets the correct pattern to find an ami.
  _ami_pattern = {
    a1      = "amzn2-ami-hvm-*-x86_64-ebs"
    c1      = "amzn2-ami-hvm-*-x86_64-ebs"
    c3      = "amzn2-ami-hvm-*-x86_64-ebs"
    c4      = "amzn2-ami-hvm-*-x86_64-ebs"
    c5      = "amzn2-ami-hvm-*-x86_64-ebs"
    c5a     = "amzn2-ami-hvm-*-x86_64-ebs"
    c5ad    = "amzn2-ami-hvm-*-x86_64-ebs"
    c5d     = "amzn2-ami-hvm-*-x86_64-ebs"
    c5n     = "amzn2-ami-hvm-*-x86_64-ebs"
    c6a     = "amzn2-ami-hvm-*-x86_64-ebs"
    c6g     = "amzn2-ami-hvm-*-arm64-gp2"
    c6gd    = "amzn2-ami-hvm-*-arm64-gp2"
    c6gn    = "amzn2-ami-hvm-*-arm64-gp2"
    c6i     = "amzn2-ami-hvm-*-x86_64-ebs"
    cc2     = "amzn2-ami-hvm-*-x86_64-ebs"
    cr1     = "amzn2-ami-hvm-*-x86_64-ebs"
    d2      = "amzn2-ami-hvm-*-x86_64-ebs"
    d3      = "amzn2-ami-hvm-*-x86_64-ebs"
    d3en    = "amzn2-ami-hvm-*-x86_64-ebs"
    dl1     = "amzn2-ami-hvm-*-x86_64-ebs"
    f1      = "amzn2-ami-hvm-*-x86_64-ebs"
    g2      = "amzn2-ami-hvm-*-x86_64-ebs"
    g3      = "amzn2-ami-hvm-*-x86_64-ebs"
    g3s     = "amzn2-ami-hvm-*-x86_64-ebs"
    g4ad    = "amzn2-ami-hvm-*-x86_64-ebs"
    g4dn    = "amzn2-ami-hvm-*-x86_64-ebs"
    g5      = "amzn2-ami-hvm-*-x86_64-ebs"
    g5g     = "amzn2-ami-hvm-*-arm64-gp2"
    h1      = "amzn2-ami-hvm-*-x86_64-ebs"
    hs1     = "amzn2-ami-hvm-*-x86_64-ebs"
    i2      = "amzn2-ami-hvm-*-x86_64-ebs"
    i3      = "amzn2-ami-hvm-*-x86_64-ebs"
    i3en    = "amzn2-ami-hvm-*-x86_64-ebs"
    im4gn   = "amzn2-ami-hvm-*-arm64-gp2"
    inf1    = "amzn2-ami-hvm-*-x86_64-ebs"
    is4gen  = "amzn2-ami-hvm-*-arm64-gp2"
    m1      = "amzn2-ami-hvm-*-x86_64-ebs"
    m2      = "amzn2-ami-hvm-*-x86_64-ebs"
    m3      = "amzn2-ami-hvm-*-x86_64-ebs"
    m4      = "amzn2-ami-hvm-*-x86_64-ebs"
    m5      = "amzn2-ami-hvm-*-x86_64-ebs"
    m5a     = "amzn2-ami-hvm-*-x86_64-ebs"
    m5ad    = "amzn2-ami-hvm-*-x86_64-ebs"
    m5d     = "amzn2-ami-hvm-*-x86_64-ebs"
    m5dn    = "amzn2-ami-hvm-*-x86_64-ebs"
    m5n     = "amzn2-ami-hvm-*-x86_64-ebs"
    m5zn    = "amzn2-ami-hvm-*-x86_64-ebs"
    m6a     = "amzn2-ami-hvm-*-x86_64-ebs"
    m6g     = "amzn2-ami-hvm-*-arm64-gp2"
    m6gd    = "amzn2-ami-hvm-*-arm64-gp2"
    m6i     = "amzn2-ami-hvm-*-x86_64-ebs"
    p2      = "amzn2-ami-hvm-*-x86_64-ebs"
    p3      = "amzn2-ami-hvm-*-x86_64-ebs"
    p3dn    = "amzn2-ami-hvm-*-x86_64-ebs"
    p4d     = "amzn2-ami-hvm-*-x86_64-ebs"
    r3      = "amzn2-ami-hvm-*-x86_64-ebs"
    r4      = "amzn2-ami-hvm-*-x86_64-ebs"
    r5      = "amzn2-ami-hvm-*-x86_64-ebs"
    r5a     = "amzn2-ami-hvm-*-x86_64-ebs"
    r5ad    = "amzn2-ami-hvm-*-x86_64-ebs"
    r5b     = "amzn2-ami-hvm-*-x86_64-ebs"
    r5d     = "amzn2-ami-hvm-*-x86_64-ebs"
    r5dn    = "amzn2-ami-hvm-*-x86_64-ebs"
    r5n     = "amzn2-ami-hvm-*-x86_64-ebs"
    r6g     = "amzn2-ami-hvm-*-arm64-gp2"
    r6gd    = "amzn2-ami-hvm-*-arm64-gp2"
    r6i     = "amzn2-ami-hvm-*-x86_64-ebs"
    t1      = "amzn2-ami-hvm-*-x86_64-ebs"
    t2      = "amzn2-ami-hvm-*-x86_64-ebs"
    t3      = "amzn2-ami-hvm-*-x86_64-ebs"
    t3a     = "amzn2-ami-hvm-*-x86_64-ebs"
    t4g     = "amzn2-ami-hvm-*-arm64-gp2"
    u-12tb1 = "amzn2-ami-hvm-*-x86_64-ebs"
    u-18tb1 = "amzn2-ami-hvm-*-x86_64-ebs"
    u-24tb1 = "amzn2-ami-hvm-*-x86_64-ebs"
    u-3tb1  = "amzn2-ami-hvm-*-x86_64-ebs"
    u-6tb1  = "amzn2-ami-hvm-*-x86_64-ebs"
    u-9tb1  = "amzn2-ami-hvm-*-x86_64-ebs"
    vt1     = "amzn2-ami-hvm-*-x86_64-ebs"
    x1      = "amzn2-ami-hvm-*-x86_64-ebs"
    x1e     = "amzn2-ami-hvm-*-x86_64-ebs"
    x2gd    = "amzn2-ami-hvm-*-arm64-gp2"
    x2iezn  = "amzn2-ami-hvm-*-x86_64-ebs"
    z1d     = "amzn2-ami-hvm-*-x86_64-ebs"
  }
  ami_pattern = local._ami_pattern[split(".", local.instance_type)[0]]
}

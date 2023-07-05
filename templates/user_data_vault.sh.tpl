#!/bin/bash

# Always update packages installed.
yum update -y

# Make a directory for Raft, certificates and init information.
mkdir -p "${vault_data_path}"
mkfs.ext4 /dev/sda1
mount /dev/sda1 "${vault_data_path}"
chmod 750 "${vault_data_path}"

# Make a directory for audit logs.
if [ "${audit_device}" = "true" ] ; then
  mkdir -p "${audit_device_path}"
  mkfs.ext4 /dev/sdb
  mount /dev/sdb "${audit_device_path}"
  chmod 750 "${audit_device_path}"
fi

TOKEN=$(curl -X PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 600")
my_hostname=$(curl -H "X-aws-ec2-metadata-token: $${TOKEN}" http://169.254.169.254/latest/meta-data/hostname)
my_ipaddress=$(curl -H "X-aws-ec2-metadata-token: $${TOKEN}" http://169.254.169.254/latest/meta-data/local-ipv4)
my_instance_id=$(curl -H "X-aws-ec2-metadata-token: $${TOKEN}" http://169.254.169.254/latest/meta-data/instance-id)

# Run a custom, user-provided script.
if [ "${vault_custom_script_s3_url}" != "" ] ; then
  aws s3 cp "${vault_custom_script_s3_url}" /custom.sh
  sh /custom.sh
fi

# Install, configure and initialize the AWS Cloudwatch agent
if [ "${cloudwatch_monitoring}" = "true" ] ; then
  aws s3 cp "s3://vault-scripts-${random_string}/cloudwatch.sh" /cloudwatch.sh
  sh /cloudwatch.sh -n "${vault_name}" -N "$${my_hostname}" -i "$${my_instance_id}" -r "${random_string}" -p "${vault_data_path}" -s "${vault_cloudwatch_namespace}"
fi

# Add the HashiCorp RPM repository.
yum install -y yum-utils
yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo

# Install a specific version of Vault.
yum install -y "${vault_package}"

# Change ownership for the `vault_data_path``.
chown vault:vault "${vault_data_path}"

# Create and configure the Vault data folder when it is different from the default path created by the rpm.
if [ "${vault_data_path}" != "/opt/vault" ] ; then
  mkdir ${vault_data_path}/data
  chown vault:vault ${vault_data_path}/data
  chmod 755 ${vault_data_path}/data
fi

# Optionally change ownership for `audit_device_path`.
if [ -d "${audit_device_path}" ] ; then
  chown vault:vault "${audit_device_path}"
fi

# Allow auto-completion for the ec2-user.
runuser -l ec2-user -c "vault -autocomplete-install"

# Allow IPC lock capability to Vault.
setcap cap_ipc_lock=+ep "$(readlink -f "$(which vault)")"

# Disable core dumps.
echo '* hard core 0' >> /etc/security/limits.d/vault.conf
echo '* soft core 0' >> /etc/security/limits.d/vault.conf
ulimit -c 0

# Place CA key and certificate.
test -d "${vault_data_path}/tls" || mkdir "${vault_data_path}/tls"
chmod 0755 "${vault_data_path}/tls"
chown vault:vault "${vault_data_path}/tls"
echo "${vault_ca_key}" > "${vault_data_path}/tls/vault_ca.pem"
echo "${vault_ca_cert}" > "${vault_data_path}/tls/vault_ca.crt"
chmod 0600 "${vault_data_path}/tls/vault_ca.pem"
chown root:root "${vault_data_path}/tls/vault_ca.pem"
chmod 0644 "${vault_data_path}/tls/vault_ca.crt"
chown root:root "${vault_data_path}/tls/vault_ca.crt"

# Place request.cfg.
cat << EOF > "${vault_data_path}/tls/request.cfg"
[req]
distinguished_name = dn
req_extensions     = ext
prompt             = no

[dn]
organizationName       = Snake
organizationalUnitName = SnakeUnit
commonName             = vault-internal.cluster.local

[ext]
basicConstraints = CA:FALSE
keyUsage         = nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName   = @alt_names

[alt_names]
IP.1 = $${my_ipaddress}
DNS.1 = $${my_hostname}
EOF

# Create a private key and certificate signing request for this instance.
openssl req -config "${vault_data_path}/tls/request.cfg" -new -newkey rsa:2048 -nodes -keyout "${vault_data_path}/tls/vault.pem" -extensions ext -out "${vault_data_path}/tls/vault.csr"
chmod 0640 "${vault_data_path}/tls/vault.pem"
chown root:vault "${vault_data_path}/tls/vault.pem"

# Sign the certificate signing request using the distributed CA.
openssl x509 -extfile "${vault_data_path}/tls/request.cfg" -extensions ext -req -in "${vault_data_path}/tls/vault.csr" -CA "${vault_data_path}/tls/vault_ca.crt" -CAkey "${vault_data_path}/tls/vault_ca.pem" -CAcreateserial -out "${vault_data_path}/tls/vault.crt" -days 7300
chmod 0644 "${vault_data_path}/tls/vault.crt"
chown root:root "${vault_data_path}/tls/vault.crt"

# Concatenate CA and server certificate.
cat "${vault_data_path}/tls/vault_ca.crt" >> "${vault_data_path}/tls/vault.crt"

# Store Amazon CA, required to bootstrap through loadbalancer.
curl https://www.amazontrust.com/repository/AmazonRootCA1.pem --output "${vault_data_path}/tls/amazon_ca.crt"

# Append the Amazon CA to Vault's CA.
cat "${vault_data_path}/tls/amazon_ca.crt" >> "${vault_data_path}/tls/vault_ca.crt"

# A single "$": passed from Terraform.
# A double "$$": determined in the runtime of this script.

# Place the Vault configuration.
cat << EOF > /etc/vault.d/vault.hcl
cluster_name      = "${vault_name}"
disable_mlock     = true
ui                = ${vault_enable_ui}
api_addr          = "${api_addr}"
cluster_addr      = "https://$${my_ipaddress}:8201"
log_level         = "${log_level}"
max_lease_ttl     = "${max_lease_ttl}"
default_lease_ttl = "${default_lease_ttl}"

storage "raft" {
  path                      = "${vault_data_path}/data"
  node_id                   = "$${my_instance_id}"
%{ if vault_type == "vault_enterprise" ~}
  autopilot_upgrade_version = "${vault_version}"
%{ endif ~}
  retry_join {
    auto_join               = "provider=aws tag_key=Name tag_value=${instance_name} addr_type=private_v4 region=${region}"
    auto_join_scheme        = "https"
    leader_ca_cert_file     = "${vault_data_path}/tls/vault_ca.crt"
    leader_client_cert_file = "${vault_data_path}/tls/vault.crt"
    leader_client_key_file  = "${vault_data_path}/tls/vault.pem"
  }
}

listener "tcp" {
  address                        = "$${my_ipaddress}:8200"
  cluster_address                = "$${my_ipaddress}:8201"
  tls_key_file                   = "${vault_data_path}/tls/vault.pem"
  tls_cert_file                  = "${vault_data_path}/tls/vault.crt"
  tls_client_ca_file             = "${vault_data_path}/tls/vault_ca.crt"
%{ if telemetry == true ~}
  telemetry {
    unauthenticated_metrics_access = ${unauthenticated_metrics_access}
  }
%{ endif ~}
  http_read_timeout              = "${vault_http_read_timeout}"
  http_write_timeout             = "${vault_http_write_timeout}"
}

seal "awskms" {
  region     = "${region}"
  kms_key_id = "${kms_key_id}"
}
EOF

if [ "${telemetry}" = true ] ; then
cat << EOF >> /etc/vault.d/vault.hcl

telemetry {
  prometheus_retention_time      = "${prometheus_retention_time}"
  disable_hostname               = ${prometheus_disable_hostname}
}
EOF
fi

# Expose the license.
if [ -n "${vault_license}" ] ; then
  echo "VAULT_LICENSE=${vault_license}" >> /etc/vault.d/vault.env
fi

# Start and enable Vault.
systemctl --now enable vault

# Setup logrotate if the audit_device is enabled.
if [[ "${audit_device}" = "true" || "${cloudwatch_monitoring}" = "true" ]] ; then
  aws s3 cp "s3://vault-scripts-${random_string}/setup_logrotate.sh" /setup_logrotate.sh
  sh /setup_logrotate.sh -a "${audit_device_path}" -s "$[${audit_device_size}*4]"
fi

# Allow users to use `vault`.
echo "export VAULT_ADDR=https://$${my_ipaddress}:8200" >> /etc/profile.d/vault.sh
echo "export VAULT_CACERT=${vault_data_path}/tls/vault_ca.crt" >> /etc/profile.d/vault.sh

# Set the history to ignore all commands that start with vault.
echo "export HISTIGNORE=\"&:vault*\"" >> /etc/profile.d/vault.sh

# Allow ec2-user access to Vault files.
usermod -G vault ec2-user

# Place an AWS EC2 health check script.
cat << EOF >> /usr/local/bin/aws_health.sh
#!/bin/bash

# Create a retry function.
function retry_curl {
  retries=\$1
  url=\$2
  attempt=0

  while [ \$attempt -lt \$retries ] ; do
    response=\$(curl --insecure --max-time 1 --silent --output /dev/null "\$url")
    if [ \$? -eq 0 ]; then
      aws --region \${region} autoscaling set-instance-health --instance-id $${my_instance_id} --health-status Healthy
      break
    else
      echo "Request to \$url failed, retrying..."
      sleep 10
      ((attempt++))
    fi
  done
  
  if [ \$attempt -eq \$retries ] ; then
    aws --region ${region} autoscaling set-instance-health --instance-id $${my_instance_id} --health-status Unhealthy
  fi
}

# Perform the health check. Retry 29 times.
response="\$(retry_curl 29 https://$${my_ipaddress}:8200/v1/sys/health)"
EOF

# Make the AWS EC2 health check script executable.
chmod 754 /usr/local/bin/aws_health.sh

# Run the AWS EC2 health check every 5 minutes, minutes after provisioning, including warmup time.
sleep "${warmup}" && crontab -l | { cat; echo "*/5 * * * * /usr/local/bin/aws_health.sh"; } | crontab -

# Place a script to discover if this instance is terminated.
cat << EOF >> /usr/local/bin/aws_deregister.sh
#!/bin/sh

# If an instance is terminated, de-register the instance from the target group.
# This means no traffic is sent to the node that is being terminated.
# After this deregistration, it's safe to destroy the instance.

if (curl --silent http://169.254.169.254/latest/meta-data/autoscaling/target-lifecycle-state | grep Terminated) ; then
%{ for target_group_arn in target_group_arns }
  deregister-targets --target-group-arn "${target_group_arn}" --targets $${my_instance_id}
%{ endfor }
fi
EOF

# Make the AWS Target Group script executable.
chmod 754 /usr/local/bin/aws_deregister.sh

crontab -l | { cat; echo "* * * * * /usr/local/bin/aws_deregister.sh"; } | crontab -

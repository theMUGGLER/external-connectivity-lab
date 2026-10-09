###############################################################################
# main.tf — Hardened Amazon Linux 2023 EC2 (t2.micro)
# Purpose: SSH on ports 22 + 443, pubkey-only auth, IP-restricted SG
###############################################################################

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

###############################################################################
# Provider
###############################################################################

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "hardened-ec2"
      ManagedBy   = "Terraform"
      Environment = var.environment
    }
  }
}

###############################################################################
# RSA 4096 Key Pair (generated inside Terraform)
###############################################################################

resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Persist the private key locally (POSIX mode 0600 set by file_permission)
resource "local_sensitive_file" "private_key_pem" {
  content         = tls_private_key.ssh_key.private_key_pem
  filename        = "${path.module}/keys/${var.key_name}.pem"
  file_permission = "0600"
}

# Upload the public key to AWS
resource "aws_key_pair" "deployer" {
  key_name   = var.key_name
  public_key = tls_private_key.ssh_key.public_key_openssh
}

###############################################################################
# Data Sources
###############################################################################

# Latest Amazon Linux 2023 AMI (x86_64)
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# Existing default VPC (required)
data "aws_vpc" "default" {
  default = true
}

###############################################################################
# Security Group — IP-restricted inbound on 22 & 443 only
###############################################################################

resource "aws_security_group" "hardened_ssh" {
  name        = "${var.project_name}-hardened-ssh-sg"
  description = "Allow SSH (22) and SSH-over-443 only from trusted IP"
  vpc_id      = data.aws_vpc.default.id

  # ── Inbound ───────────────────────────────────────────────────────────────

  ingress {
    description = "SSH standard port from trusted IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.trusted_ip_cidr]
  }

  ingress {
    description = "SSH on port 443 from trusted IP for connectivity testing"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.trusted_ip_cidr]
  }

  # ── Outbound ──────────────────────────────────────────────────────────────

  egress {
    description = "Allow all outbound (package updates, etc.)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

###############################################################################
# User Data — sshd hardening applied on first boot
###############################################################################

locals {
  user_data = <<-EOF
    #!/usr/bin/env bash
    set -euo pipefail

    # ── 1. Harden /etc/ssh/sshd_config ─────────────────────────────────────
    SSHD_CONF="/etc/ssh/sshd_config"

    # Back up the original config
    cp "$SSHD_CONF" "$${SSHD_CONF}.bak.$(date +%F)"

    # Wipe any existing Port / Auth directives so we control them cleanly
    sed -i '/^#\?Port /d'                    "$SSHD_CONF"
    sed -i '/^#\?PasswordAuthentication /d'  "$SSHD_CONF"
    sed -i '/^#\?PermitRootLogin /d'         "$SSHD_CONF"
    sed -i '/^#\?ChallengeResponseAuth/d'    "$SSHD_CONF"
    sed -i '/^#\?UsePAM /d'                  "$SSHD_CONF"
    sed -i '/^#\?PubkeyAuthentication /d'    "$SSHD_CONF"
    sed -i '/^#\?AuthorizedKeysFile /d'      "$SSHD_CONF"
    sed -i '/^#\?X11Forwarding /d'           "$SSHD_CONF"
    sed -i '/^#\?MaxAuthTries /d'            "$SSHD_CONF"
    sed -i '/^#\?LoginGraceTime /d'          "$SSHD_CONF"
    sed -i '/^#\?AllowAgentForwarding /d'    "$SSHD_CONF"
    sed -i '/^#\?AllowTcpForwarding /d'      "$SSHD_CONF"
    sed -i '/^#\?PermitEmptyPasswords /d'    "$SSHD_CONF"
    sed -i '/^#\?PrintMotd /d'               "$SSHD_CONF"

    # Append hardened block
    cat >> "$SSHD_CONF" <<'SSHD'

    # ── Hardened block (managed by Terraform user-data) ──────────────────
    # Listen on standard SSH port AND 443 (for authorized outbound connectivity testing)
    Port 22
    Port 443

    # Public-key authentication only — passwords strictly disabled
    PubkeyAuthentication yes
    AuthorizedKeysFile  .ssh/authorized_keys
    PasswordAuthentication no
    PermitEmptyPasswords no
    ChallengeResponseAuthentication no

    # Disable root login
    PermitRootLogin no

    # Reduce attack surface
    X11Forwarding no
    AllowAgentForwarding no
    AllowTcpForwarding no
    MaxAuthTries 3
    LoginGraceTime 30

    # PAM is still required for session/account management on AL2023
    UsePAM yes
    SSHD

    # ── 2. Validate config before restarting ────────────────────────────────
    if sshd -t; then
      systemctl restart sshd
      echo "[user-data] sshd restarted successfully on ports 22 and 443" \
        >> /var/log/user-data.log
    else
      echo "[user-data] ERROR: sshd config validation failed — reverting" \
        >> /var/log/user-data.log
      cp "$${SSHD_CONF}.bak.$(date +%F)" "$SSHD_CONF"
      systemctl restart sshd
      exit 1
    fi

    # ── 3. Harden SSH host key permissions ──────────────────────────────────
    chmod 600 /etc/ssh/ssh_host_*_key
    chmod 644 /etc/ssh/ssh_host_*_key.pub

    # ── 4. Disable unused services ───────────────────────────────────────────
    for svc in telnet rsh rlogin; do
      systemctl disable "$svc" 2>/dev/null || true
    done

    echo "[user-data] Hardening complete." >> /var/log/user-data.log
  EOF
}

###############################################################################
# EC2 Instance
###############################################################################

resource "aws_instance" "hardened" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.hardened_ssh.id]

  # Enable IMDSv2 — reduces exposure to some metadata-access attack paths
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30 # GiB
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name = "${var.project_name}-root-volume"
    }
  }

  user_data                   = local.user_data
  user_data_replace_on_change = true # forces replacement if script changes

  tags = {
    Name = "${var.project_name}-hardened-ec2"
  }

  # Ensure key pair exists before the instance is created
  depends_on = [aws_key_pair.deployer]
}

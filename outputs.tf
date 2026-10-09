###############################################################################
# outputs.tf
###############################################################################

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.hardened.id
}

output "public_ip" {
  description = "Public IPv4 address of the instance"
  value       = aws_instance.hardened.public_ip
}

output "public_dns" {
  description = "Public DNS hostname of the instance"
  value       = aws_instance.hardened.public_dns
}

output "ami_id" {
  description = "AMI resolved and used for the instance"
  value       = data.aws_ami.amazon_linux_2023.id
}

output "security_group_id" {
  description = "Security Group ID attached to the instance"
  value       = aws_security_group.hardened_ssh.id
}

output "key_pair_name" {
  description = "Name of the AWS Key Pair"
  value       = aws_key_pair.deployer.key_name
}

output "private_key_path" {
  description = "Local path where the RSA 4096 private key was saved"
  value       = local_sensitive_file.private_key_pem.filename
  sensitive   = true
}
output "instance_public_dns" {
  description = "FQDN"
  value       = aws_instance.hardened.public_dns
}

output "ssh_command_port_22" {
  description = "Ready-to-use SSH command (port 22)"
  value       = "ssh -i keys/${var.key_name}.pem -p 22 ec2-user@${aws_instance.hardened.public_ip}"
}

output "ssh_command_port_443" {
  description = "Ready-to-use SSH command (port 443)"
  value       = "ssh -i keys/${var.key_name}.pem -p 443 ec2-user@${aws_instance.hardened.public_ip}"
}

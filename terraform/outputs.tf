output "public_ips" {
  value = aws_instance.node[*].public_ip
}

output "ssh_commands" {
  value = [for n in aws_instance.node : "ssh -i ~/.ssh/fleet-key ubuntu@${n.public_ip}"]
}

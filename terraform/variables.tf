variable "region" {
  description = "AWS region (Stockholm is the cheapest EU option)"
  type        = string
  default     = "eu-north-1"
}

variable "instance_type" {
  description = "Server size"
  type        = string
  default     = "t4g.micro"
}

variable "server_count" {
  description = "How many servers to run (keep at 1 to save money)"
  type        = number
  default     = 1
}

variable "allowed_ssh_cidr" {
  description = "The one IP address allowed to SSH in, like 1.2.3.4/32"
  type        = string
}

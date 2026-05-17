variable "project_name" { type = string }
variable "environment" { type = string }
variable "vpc_cidr" { type = string }
variable "availability_zones" { type = list(string) }
variable "public_subnet_cidrs" { type = list(string) }
variable "private_subnet_cidrs" { type = list(string) }

variable "single_nat_gateway" {
  description = "Use one NAT gateway for all private subnets (lower cost, less HA)"
  type        = bool
  default     = false
}

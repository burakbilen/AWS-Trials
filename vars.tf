variable "AWS_REGION" {
  default = "eu-central-1"
}

variable "AVA_ZONE" {
  default = "eu-central-1a"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "Public Subnet CIDRs"
  default     = ["10.3.1.0/24", "10.3.2.0/24", "10.3.3.0/24"]
}

variable "availability_zones" {
  type        = list(string)
  description = "Availability zones"
  default     = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
}

variable "my_ip" {
  default = "85.153.225.114/32"
}

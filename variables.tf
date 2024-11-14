# Global Variables
variable "location" {
  description = "Azure region"
  default     = "westeurope"
}

variable "prefix" {
  type        = string
  default     = "ICL-XX"
  description = "Prefix to be used in resource names"
}

# Network related Variables
variable "vnet_address_space" {
  description = "Address space for the Virtual Network"
  default     = ["10.0.0.0/16"]
}

variable "public_subnet_prefix" {
  description = "Address prefix for the public subnet"
  default     = ["10.0.1.0/24"]
}

variable "private_subnet_prefix" {
  description = "Address prefix for the private subnet"
  default     = ["10.0.2.0/24"]
}

variable "vnet_name" {
  description = "Name for the Virtual Network"
  default     = "VNET"
}

# VM related Variables
variable "linux_instance_count" {
  description = "Number of Linux instances to create"
  default     = 1
}

variable "windows_instance_count" {
  description = "Number of Windows instances to create"
  default     = 1
}

variable "vm_size" {
  description = "Size of the Virtual Machines"
  default     = "Standard_B2s"
}

variable "admin_username" {
  description = "Administrator username for VMs"
  default     = "azureuser"
}

variable "admin_password" {
  description = "Administrator password for Windows VMs"
  default     = "P@ssw0rd1234!"
  sensitive   = true
}

# Configure Azure provider
provider "azurerm" {
  features {}
}

# Create Resource Group
resource "azurerm_resource_group" "main" {
  name     = "${var.prefix}-RG"
  location = var.location
}

# Create Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = "${var.prefix}-${var.vnet_name}"
  address_space       = var.vnet_address_space
  location           = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

# Create Public Subnet
resource "azurerm_subnet" "public" {
  name                 = "public-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = var.public_subnet_prefix
}

# Create Private Subnet
resource "azurerm_subnet" "private" {
  name                 = "private-subnet"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = var.private_subnet_prefix
}

# Create Public IP for Jump Host
resource "azurerm_public_ip" "jumphost" {
  name                = "${var.prefix}-jumphost-pip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Create NAT Gateway
resource "azurerm_nat_gateway" "main" {
  name                = "${var.prefix}-natgw"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = "Standard"
}

# Create Public IP for NAT Gateway
resource "azurerm_public_ip" "natgw" {
  name                = "${var.prefix}-natgw-pip"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Associate NAT Gateway with Public IP
resource "azurerm_nat_gateway_public_ip_association" "main" {
  nat_gateway_id       = azurerm_nat_gateway.main.id
  public_ip_address_id = azurerm_public_ip.natgw.id
}

# Associate NAT Gateway with Private Subnet
resource "azurerm_subnet_nat_gateway_association" "main" {
  subnet_id      = azurerm_subnet.private.id
  nat_gateway_id = azurerm_nat_gateway.main.id
}

# Create Network Security Group for Jump Host
resource "azurerm_network_security_group" "jumphost" {
  name                = "${var.prefix}-jumphost-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "SSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "22"
    source_address_prefix     = "*"
    destination_address_prefix = "*"
  }
}

# Create Network Security Group for Workloads
resource "azurerm_network_security_group" "workload" {
  name                = "${var.prefix}-workload-nsg"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "AllowAll"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range         = "*"
    destination_port_range    = "*"
    source_address_prefix     = "*"
    destination_address_prefix = "*"
  }
}

# Generate SSH key for Linux VMs
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Save private key to file
resource "local_file" "private_key" {
  content  = tls_private_key.ssh.private_key_pem
  filename = "${path.module}/${var.prefix}-private-key.pem"
}

# Create Jump Host NIC
resource "azurerm_network_interface" "jumphost" {
  name                = "${var.prefix}-jumphost-nic"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.public.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.jumphost.id
  }
}

# Create Jump Host VM
resource "azurerm_linux_virtual_machine" "jumphost" {
  name                = "${var.prefix}-jumphost"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = var.vm_size
  admin_username      = var.admin_username
  network_interface_ids = [
    azurerm_network_interface.jumphost.id,
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.ssh.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}

# Create Linux Workload NICs
resource "azurerm_network_interface" "linux" {
  count               = var.linux_instance_count
  name                = "${var.prefix}-linux-nic-${count.index + 1}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.private.id
    private_ip_address_allocation = "Dynamic"
  }
}

# Create Linux Workload VMs
resource "azurerm_linux_virtual_machine" "linux" {
  count               = var.linux_instance_count
  name                = "${var.prefix}-linux-${count.index + 1}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = var.vm_size
  admin_username      = var.admin_username
  network_interface_ids = [
    azurerm_network_interface.linux[count.index].id,
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = tls_private_key.ssh.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}

# Create Windows Workload NICs
resource "azurerm_network_interface" "windows" {
  count               = var.windows_instance_count
  name                = "${var.prefix}-windows-nic-${count.index + 1}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.private.id
    private_ip_address_allocation = "Dynamic"
  }
}

# Create Windows Workload VMs
resource "azurerm_windows_virtual_machine" "windows" {
  count               = var.windows_instance_count
  name                = "${var.prefix}-windows-${count.index + 1}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = var.vm_size
  admin_username      = var.admin_username
  admin_password      = var.admin_password
  network_interface_ids = [
    azurerm_network_interface.windows[count.index].id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-Datacenter"
    version   = "latest"
  }
}

# Create Ansible inventory file
resource "local_file" "ansible_inventory" {
  content = <<-EOT
[jumphost]
${azurerm_public_ip.jumphost.ip_address} ansible_ssh_private_key_file="${path.module}/${var.prefix}-private-key.pem"

[linux_workload]
%{ for index, vm in azurerm_linux_virtual_machine.linux ~}
linux-${index + 1} ansible_host=${azurerm_network_interface.linux[index].private_ip_address}
%{ endfor ~}

[windows]
%{ for index, vm in azurerm_windows_virtual_machine.windows ~}
windows-${index + 1} ansible_host=${azurerm_network_interface.windows[index].private_ip_address}
%{ endfor ~}

[windows:vars]
ansible_connection=winrm
ansible_winrm_server_cert_validation=ignore
ansible_winrm_transport=basic
ansible_user=${var.admin_username}
ansible_password=${var.admin_password}

[linux_workload:vars]
ansible_ssh_common_args='-o ProxyCommand="ssh -W %h:%p -q -i ${path.module}/${var.prefix}-private-key.pem ${var.admin_username}@${azurerm_public_ip.jumphost.ip_address}"'
ansible_host_key_checking=False
ansible_user=${var.admin_username}
ansible_ssh_private_key_file="${path.module}/${var.prefix}-private-key.pem"
EOT
  filename = "${path.module}/inventory"

  depends_on = [
    local_file.private_key,
    azurerm_linux_virtual_machine.jumphost,
    azurerm_linux_virtual_machine.linux,
    azurerm_windows_virtual_machine.windows
  ]
}

# Outputs
output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "jumphost_public_ip" {
  value = azurerm_public_ip.jumphost.ip_address
}

output "linux_private_ips" {
  value = azurerm_network_interface.linux[*].private_ip_address
}

output "windows_private_ips" {
  value = azurerm_network_interface.windows[*].private_ip_address
}

# Write outputs to files
resource "local_file" "network-data" {
  content = <<-EOT
    Resource Group: ${azurerm_resource_group.main.name}
    VNet Name: ${azurerm_virtual_network.main.name}
    Public Subnet ID: ${azurerm_subnet.public.id}
    Private Subnet ID: ${azurerm_subnet.private.id}
    NAT Gateway: ${azurerm_nat_gateway.main.id}
  EOT
  filename = "${path.module}/network_data.txt"
}

resource "local_file" "vm-data" {
  content = <<-EOT
    Jumphost Public IP: ${azurerm_public_ip.jumphost.ip_address}
    Linux VMs Private IPs: ${jsonencode(azurerm_network_interface.linux[*].private_ip_address)}
    Windows VMs Private IPs: ${jsonencode(azurerm_network_interface.windows[*].private_ip_address)}
  EOT
  filename = "${path.module}/vm_data.txt"
}

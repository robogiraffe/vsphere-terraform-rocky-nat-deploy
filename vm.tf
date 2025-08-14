resource "vsphere_folder" "project_folder" {
  path          = var.project_folder_name
  type          = "vm"
  datacenter_id = data.vsphere_datacenter.datacenter.id
}

resource "vsphere_virtual_machine" "rocky" {
  name             = var.vm_name
  resource_pool_id = data.vsphere_host.host.resource_pool_id
  datastore_id     = data.vsphere_datastore.datastore.id
  folder           = var.project_folder_name
  firmware         = "efi"
  
  num_cpus = var.vm_cpus
  memory   = var.vm_memory
  guest_id = data.vsphere_virtual_machine.template.guest_id
  
  network_interface {
    network_id   = data.vsphere_network.network.id
    adapter_type = data.vsphere_virtual_machine.template.network_interface_types[0]
  }
  network_interface {
    network_id   = data.vsphere_network.localnetwork.id
    adapter_type = data.vsphere_virtual_machine.template.network_interface_types[0]
  }
  
  disk {
    label            = "Hard Disk 1"
    size             = var.vm_disk_size
    thin_provisioned = data.vsphere_virtual_machine.template.disks.0.thin_provisioned
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.template.id

    customize {
      linux_options {
        host_name = var.vm_name
        domain    = "local"
      }
      
      network_interface {
        ipv4_address = var.vm_ip_address != "" ? var.vm_ip_address : null
        ipv4_netmask = var.vm_ip_address != "" ? var.vm_netmask : null
      }
      network_interface {
        ipv4_address = var.vm_ip_address2 != "" ? var.vm_ip_address2 : null
        ipv4_netmask = var.vm_ip_address2 != "" ? var.vm_netmask2 : null
      }
      
      ipv4_gateway    = var.vm_ip_address != "" ? var.vm_gateway : null
      dns_server_list = var.vm_ip_address != "" ? var.vm_dns_servers : null
    }
  }
  
  provisioner "remote-exec" {
  inline = [
    #Expand disk to 100%
    "sudo dnf -y update && sudo dnf install -y cloud-utils-growpart lvm2",
    "sudo growpart /dev/sda 3",
    "sudo lvextend -r -l +100%FREE /dev/mapper/rl-root",
    "echo 'Disk resize and filesystem extend complete.'",
    # 1. IP forwarding
    "echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf",
    "sudo sysctl -p",
    # 2. 
    "WAN_IF=$(ip -o -4 route show to default | awk '{print $5}')",
    "LAN_IF=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | grep -v $WAN_IF | head -n1)",
    "echo \"WAN interface: $WAN_IF\"",
    "echo \"LAN interface: $LAN_IF\"",
    # 3. NAT
    "sudo iptables -t nat -A POSTROUTING -o $WAN_IF -j MASQUERADE",
    "sudo iptables -A FORWARD -i $WAN_IF -o $LAN_IF -m state --state RELATED,ESTABLISHED -j ACCEPT",
    "sudo iptables -A FORWARD -i $LAN_IF -o $WAN_IF -j ACCEPT",
    # 4. 
    "if command -v apt-get &> /dev/null; then",
    "  echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections",
    "  echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections",
    "  sudo DEBIAN_FRONTEND=noninteractive apt-get update -y",
    "  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent",
    "  sudo netfilter-persistent save",
    "  sudo systemctl enable netfilter-persistent",
    "elif command -v dnf &> /dev/null; then",
    "  sudo dnf makecache",
    "  sudo dnf install -y iptables-services",
    "  sudo sh -c 'iptables-save > /etc/sysconfig/iptables'",
    "  sudo systemctl enable iptables",
    "  sudo systemctl restart iptables",
    "fi",
    "echo '=== NAT і IP forwarding success! ==='"
  ]
    
    connection {
      type        = "ssh"
      user        = var.vm_user_default
      password    = var.vm_password_default
      host        = self.default_ip_address
      timeout     = "5m"
    }
  }    
}


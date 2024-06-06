provider "digitalocean" {
  token = var.do_token
}

resource "digitalocean_droplet" "app_server" {
  image  = "ubuntu-20-04-x64"
  name   = "app-server"
  region = "nyc3"
  size   = "s-1vcpu-1gb"
  ssh_keys = [
    var.ssh_key_id
  ]

  connection {
    type        = "ssh"
    user        = "root"
    private_key = file(var.ssh_private_key_path)
    timeout     = "2m"
  }

  provisioner "remote-exec" {
    inline = [
      "apt-get update",
      "apt-get install -y python3 python3-pip"
    ]
  }

  provisioner "local-exec" {
    command = <<EOF
    ansible-playbook -i '${self.ipv4_address},' --private-key ${var.ssh_private_key_path} setup_droplet.yml
    EOF
  }
}

output "app_server_ip" {
  value = digitalocean_droplet.app_server.ipv4_address
}

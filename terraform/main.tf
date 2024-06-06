terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

provider "digitalocean" {
  token = var.do_token
}

# Create or reference the existing web server
data "digitalocean_droplet" "existing_droplets" {
  filter {
    key    = "name"
    values = ["app-server"]
  }
}

resource "digitalocean_droplet" "app_server" {
  count = length(data.digitalocean_droplet.existing_droplets.droplets) == 0 ? 1 : 0
  name   = "app-server"
  region = "nyc3"
  size   = "s-1vcpu-1gb"
  image  = "ubuntu-20-04-x64"
  ssh_keys = [var.ssh_key_id]

  connection {
    type        = "ssh"
    user        = "root"
    private_key = file(var.private_key_path)
    timeout     = "2m"
  }

  provisioner "remote-exec" {
    inline = [
      "apt-get update",
      "apt-get -y upgrade",
    ]
  }
}

output "app_server_ip" {
  value = data.digitalocean_droplet.existing_droplets.droplets[0].ipv4_address
}

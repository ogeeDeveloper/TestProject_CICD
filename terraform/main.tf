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

resource "digitalocean_droplet" "app_server" {
  image    = "ubuntu-20-04-x64"
  name     = "app-server"
  region   = "nyc3"
  size     = "s-1vcpu-1gb"
  ssh_keys = [var.ssh_key_id]
}

output "app_server_ip" {
  value = digitalocean_droplet.app_server.ipv4_address
}

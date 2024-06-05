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

locals {
  droplet_exists = length(data.digitalocean_droplet.existing_droplet) > 0
}

data "digitalocean_droplet" "existing_droplet" {
  name = "app-server"
  count = 0
}

resource "digitalocean_droplet" "app_server" {
  count = local.droplet_exists ? 0 : 1
  image = "ubuntu-20-04-x64"
  name = "app-server"
  region = "nyc3"
  size = "s-1vcpu-1gb"
  monitoring = true
  ssh_keys = [var.ssh_key_id]
}

output "app_server_ip" {
  value = local.droplet_exists ? data.digitalocean_droplet.existing_droplet[0].ipv4_address : digitalocean_droplet.app_server[0].ipv4_address
}

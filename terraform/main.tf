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

data "digitalocean_droplet" "existing_droplet" {
  name = "app-server"
}

# Local variable for debugging
locals {
  existing_droplet_ids = data.digitalocean_droplet.existing_droplet.*.id
}

# Debug output
output "existing_droplet_ids" {
  value = local.existing_droplet_ids
}

resource "digitalocean_droplet" "app_server" {
  count  = length(local.existing_droplet_ids) == 0 ? 1 : 0
  image  = "ubuntu-20-04-x64"
  name   = "app-server"
  region = "nyc3"
  size   = "s-2vcpu-2gb"
  ssh_keys = [var.ssh_key_id]
}

output "app_server_ip" {
  value = length(local.existing_droplet_ids) > 0 ? data.digitalocean_droplet.existing_droplet.ipv4_address : digitalocean_droplet.app_server[0].ipv4_address
}

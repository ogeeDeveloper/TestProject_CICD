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
  name   = "app-server"
  count  = 0
}

resource "digitalocean_droplet" "app_server" {
  count     = length(data.digitalocean_droplet.existing_droplet) == 0 ? 1 : 0
  image     = "ubuntu-20-04-x64"
  name      = "app-server"
  region    = "nyc3"
  size      = "s-1vcpu-1gb"
  monitoring = true
  ssh_keys  = [var.ssh_key_id]
}

locals {
  existing_droplet_count = length(data.digitalocean_droplet.existing_droplet)
  existing_droplet_ids   = data.digitalocean_droplet.existing_droplet.*.id
  existing_droplet_ip    = length(data.digitalocean_droplet.existing_droplet) > 0 ? data.digitalocean_droplet.existing_droplet[0].ipv4_address : ""
}

output "app_server_ip" {
  value = local.existing_droplet_count > 0 ? local.existing_droplet_ip : digitalocean_droplet.app_server[0].ipv4_address
}

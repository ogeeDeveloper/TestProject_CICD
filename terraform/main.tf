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
  count  = length(data.digitalocean_droplet.existing_droplet) == 0 ? 1 : 0
  image  = "ubuntu-20-04-x64"
  name   = "app-server"
  region = "nyc3"
  size   = "s-2vcpu-2gb"  # Adjust the size based on your needs
  ssh_keys = [var.ssh_key_id]  # Ensure your SSH key is added to DigitalOcean
}

data "digitalocean_droplet" "existing_droplet" {
  count = 0
  name = "app-server"
  depends_on = [digitalocean_droplet.app_server]
}

output "app_server_ip" {
  value = coalesce(
    data.digitalocean_droplet.existing_droplet[0].ipv4_address,
    digitalocean_droplet.app_server[0].ipv4_address
  )
}

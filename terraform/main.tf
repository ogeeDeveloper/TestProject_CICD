terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "latest" # or specify a specific version
    }
  }
}

provider "digitalocean" {
  token = var.do_token
}

data "digitalocean_droplet" "existing_droplet" {
  name = "app-server"
  depends_on = []
}

resource "digitalocean_droplet" "app_server" {
  count  = length(data.digitalocean_droplet.existing_droplet.id) == 0 ? 1 : 0
  image  = "ubuntu-20-04-x64"
  name   = "app-server"
  region = "nyc3"
  size   = "s-2vcpu-4gb"  # Adjust the size based on your needs
  ssh_keys = [var.ssh_key_id]  # Ensure your SSH key is added to DigitalOcean
}

output "app_server_ip" {
  value = coalesce(
    data.digitalocean_droplet.existing_droplet.ipv4_address,
    digitalocean_droplet.app_server[0].ipv4_address
  )
}

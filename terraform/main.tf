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

variable "do_token" {}
variable "ssh_key_id" {}

# Try to look up an existing droplet
data "digitalocean_droplet" "existing_droplet" {
  name = "app-server"
  depends_on = []
}

# If the droplet doesn't exist, create it
resource "digitalocean_droplet" "app_server" {
  count  = length(data.digitalocean_droplet.existing_droplet.*.id) == 0 ? 1 : 0
  image  = "ubuntu-20-04-x64"
  name   = "app-server"
  region = "nyc3"
  size   = "s-2vcpu-2gb"  # Adjust the size based on your needs
  ssh_keys = [var.ssh_key_id]  # Ensure your SSH key is added to DigitalOcean
}

# Output the IP address of the droplet, whether it was created or already existed
output "app_server_ip" {
  value = length(data.digitalocean_droplet.existing_droplet.*.id) > 0 ? data.digitalocean_droplet.existing_droplet[0].ipv4_address : digitalocean_droplet.app_server[0].ipv4_address
}

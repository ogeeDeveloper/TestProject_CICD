provider "digitalocean" {
  token = var.do_token
}

resource "digitalocean_droplet" "app_server" {
  image  = "ubuntu-20-04-x64"
  name   = "app-server"
  region = "nyc3"
  size   = "s-2vcpu-4gb"  # Adjust the size based on your needs
  ssh_keys = [var.ssh_key_id]  # Ensure your SSH key is added to DigitalOcean
}

output "app_server_ip" {
  value = digitalocean_droplet.app_server.ipv4_address
}

provider "digitalocean" {
  token = var.do_token
}

resource "digitalocean_droplet" "app_server" {
  image  = "ubuntu-20-04-x64"
  name   = "app-server"
  region = "nyc3"
  size   = "s-1vcpu-1gb"
  ssh_keys = [var.ssh_key_id]
  private_networking = true

  connection {
    type        = "ssh"
    user        = "root"
    private_key = file(var.ssh_private_key_path)
  }

  provisioner "remote-exec" {
    inline = [
      "apt-get update -y",
      "apt-get install -y openjdk-11-jdk"
    ]
  }
}

output "app_server_ip" {
  value = digitalocean_droplet.app_server.ipv4_address
}

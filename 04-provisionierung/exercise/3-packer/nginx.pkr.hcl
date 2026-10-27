packer {
  required_plugins {
    docker = {
      source  = "github.com/hashicorp/docker"
      version = "~> 1"
    }
  }
}

source "docker" "nginx" {
  image       = "nginx:1.29-alpine"
  commit      = true
  run_command = ["-d", "-t", "-i", "{{.Image}}", "/bin/sh"]
  changes = [
    "EXPOSE 80",
    "CMD [\"nginx\", \"-g\", \"daemon off;\"]"
  ]
}

build {
  sources = ["source.docker.nginx"]
  provisioner "file" {
    source      = "index.html"
    destination = "/usr/share/nginx/html/index.html"
  }
  post-processor "docker-tag" {
    repository = "packer-nginx"
    tags       = ["1.0"]
  }
}

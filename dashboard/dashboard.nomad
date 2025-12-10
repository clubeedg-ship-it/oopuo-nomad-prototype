job "oopuo-dashboard" {
  datacenters = ["oopuo-edge"]
  type = "service"

  group "dashboard" {
    count = 1

    network {
      port "http" {
        static = 8080
      }
    }

    task "web" {
      driver = "docker"

      config {
        image = "python:3.11-slim"
        ports = ["http"]
        
        volumes = [
          "/opt/oopuo/dashboard:/app"
        ]
        
        command = "python3"
        args = ["-m", "http.server", "8080", "--directory", "/app"]
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }
  }
}

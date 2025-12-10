job "ollama" {
  datacenters = ["oopuo-edge"]
  type = "service"

  group "ollama" {
    count = 1

    network {
      port "http" {
        static = 11434
      }
    }

    task "server" {
      driver = "docker"

      config {
        image = "ollama/ollama:latest"
        ports = ["http"]
      }

      resources {
        cpu    = 2000
        memory = 4096
      }
    }
  }
}

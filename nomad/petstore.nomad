job "petstore" {
  datacenters = ["dc1"]
  type = "service"

  update {
    max_parallel = 1
    min_healthy_time = "10s"
    healthy_deadline = "3m"
    auto_revert = false
    canary = 0
  }

  migrate {
    max_parallel = 1
    health_check = "checks"
    min_healthy_time = "10s"
    healthy_deadline = "5m"
  }

  group "petstore" {
    count = 1

    restart {
      attempts = 2
      interval = "30m"
      delay = "15s"
      mode = "fail"
    }

    ephemeral_disk {
      size = 300
    }

    task "petstore" {
      driver = "docker"

      config {
        image = "soloio/petstore-example:latest"
        port_map {
          http = 8080
        }
      }

      resources {
        cpu = 500
        memory = 256
        network {
          mbits = 10
          port "http" {}
        }
      }

      service {
        name = "petstore"
        port = "http"
      }
    }
  }
}
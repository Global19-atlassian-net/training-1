job "gloo" {
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

  group "gloo" {
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

    task "gloo" {
      driver = "docker"

      config {
        image = "quay.io/solo-io/gloo:0.17.6"
        work_dir = "/"
        args = [
          "--dir=/data/",
        ]
        volumes = [
          "/vagrant/data:/data/",
        ]
        port_map {
          xds = 9977
        }
      }

      resources {
        cpu = 500
        memory = 256
        network {
          mbits = 10
          port "xds" {}
        }
      }

      service {
        name = "gloo"
        tags = ["gloo"]
        port = "xds"
        check {
          name = "alive"
          type = "tcp"
          interval = "10s"
          timeout = "2s"
        }
      }
    }

    task "gateway" {
      driver = "docker"

      config {
        image = "quay.io/solo-io/gateway:0.17.6"
        work_dir = "/"
        args = [
          "--dir=/data/",
        ]
        volumes = [
          "/vagrant/data:/data/",
        ]
      }

      resources {
        cpu = 500
        memory = 256
        network {
          mbits = 10
        }
      }
    }

    task "gateway-proxy" {
      driver = "docker"
      config {
        image = "quay.io/solo-io/gloo-envoy-wrapper:0.17.6"
        port_map {
          http = 8080
          https = 8443
          admin = 19000
        }
        entrypoint = ["envoy"]
        args = [
          "-c",
          "${NOMAD_TASK_DIR}/envoy.yaml",
          "--disable-hot-restart",
          "-l debug",
        ]
      }

      template {
        data = <<EOF
node:
  cluster: gateway
  id: gateway~{{ env "NOMAD_ALLOC_ID" }}
  metadata:
    # this line must match !
    role: "gloo-system~gateway-proxy"

static_resources:
  clusters:
  - name: xds_cluster
    connect_timeout: 5.000s
    load_assignment:
      cluster_name: xds_cluster
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: {{ env "NOMAD_IP_gloo_xds" }}
                port_value: {{ env "NOMAD_PORT_gloo_xds" }}
    http2_protocol_options: {}
    type: STATIC

dynamic_resources:
  ads_config:
    api_type: GRPC
    grpc_services:
    - envoy_grpc: {cluster_name: xds_cluster}
  cds_config:
    ads: {}
  lds_config:
    ads: {}

admin:
  access_log_path: /dev/null
  address:
    socket_address:
      address: 0.0.0.0
      port_value: 19000
EOF

        destination = "${NOMAD_TASK_DIR}/envoy.yaml"
      }

      resources {
        cpu = 500
        memory = 256
        network {
          mbits = 10
          port "http" {
            static = 28080
          }
          port "https" {
            static = 28443
          }
          port "admin" {
            static = 29000
          }
        }
      }

      service {
        name = "gateway-proxy"
        tags = [
          "gloo",
          "http",
        ]
        port = "http"
        check {
          name = "alive"
          type = "tcp"
          interval = "10s"
          timeout = "2s"
        }
      }

      service {
        name = "gateway-proxy"
        tags = [
          "gloo",
          "https",
        ]
        port = "https"
        check {
          name = "alive"
          type = "tcp"
          interval = "10s"
          timeout = "2s"
        }
      }

      service {
        name = "gateway-proxy"
        tags = [
          "gloo",
          "admin",
        ]
        port = "admin"
        check {
          name = "alive"
          type = "tcp"
          interval = "10s"
          timeout = "2s"
        }
      }
    }
  }
}

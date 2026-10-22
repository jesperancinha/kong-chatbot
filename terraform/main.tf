locals {
  konnect_cluster_cert_path = abspath(var.konnect_cluster_cert_path)
  konnect_cluster_key_path  = abspath(var.konnect_cluster_key_path)
}

resource "docker_network" "chatbot" {
  name = "kong-chatbot"
}

resource "docker_volume" "vector_data" {
  name = "kong-chatbot-vector-data"
}

resource "docker_image" "kong" {
  name         = var.kong_gateway_image
  keep_locally = true
}

resource "docker_image" "redis" {
  name         = var.redis_image
  keep_locally = true
}

resource "docker_image" "chatbot" {
  name = var.chatbot_image

  build {
    context = abspath("${path.module}/..")
    tag     = [var.chatbot_image]
  }

  triggers = {
    source = sha1(join("", [
      for file in fileset("${path.module}/..", "src/**") : filesha1("${path.module}/../${file}")
    ]))
    dockerfile = filesha1("${path.module}/../Dockerfile")
    pom        = filesha1("${path.module}/../pom.xml")
  }
}

resource "docker_container" "vector_db" {
  name    = "kong-chatbot-vector-db"
  image   = docker_image.redis.image_id
  restart = "unless-stopped"

  command = [
    "redis-stack-server",
    "--requirepass",
    var.redis_password,
  ]

  volumes {
    volume_name    = docker_volume.vector_data.name
    container_path = "/data"
  }

  networks_advanced {
    name    = docker_network.chatbot.name
    aliases = ["vector-db"]
  }
}

resource "docker_container" "kong" {
  name    = "kong-chatbot-gateway"
  image   = docker_image.kong.image_id
  restart = "unless-stopped"

  env = [
    "KONG_ROLE=data_plane",
    "KONG_DATABASE=off",
    "KONG_VITALS=off",
    "KONG_PROXY_LISTEN=0.0.0.0:8000",
    "KONG_ADMIN_LISTEN=off",
    "KONG_STATUS_LISTEN=0.0.0.0:8100",
    "KONG_CLUSTER_MTLS=pki",
    "KONG_CLUSTER_CONTROL_PLANE=${var.kong_cluster_control_plane}",
    "KONG_CLUSTER_SERVER_NAME=${var.kong_cluster_server_name}",
    "KONG_CLUSTER_TELEMETRY_ENDPOINT=${var.kong_cluster_telemetry_endpoint}",
    "KONG_CLUSTER_TELEMETRY_SERVER_NAME=${var.kong_cluster_telemetry_server_name}",
    "KONG_CLUSTER_CERT=/run/secrets/konnect-cluster.crt",
    "KONG_CLUSTER_CERT_KEY=/run/secrets/konnect-cluster.key",
  ]

  volumes {
    host_path      = local.konnect_cluster_cert_path
    container_path = "/run/secrets/konnect-cluster.crt"
    read_only      = true
  }

  volumes {
    host_path      = local.konnect_cluster_key_path
    container_path = "/run/secrets/konnect-cluster.key"
    read_only      = true
  }

  ports {
    internal = 8000
    external = var.kong_proxy_port
    ip       = "127.0.0.1"
  }

  networks_advanced {
    name    = docker_network.chatbot.name
    aliases = ["kong"]
  }
}

resource "docker_container" "chatbot" {
  name    = "kong-chatbot-api"
  image   = docker_image.chatbot.image_id
  restart = "unless-stopped"

  env = [
    "PORT=8080",
    "KONG_URL=http://kong-chatbot-gateway:8000",
    "KONG_RAG_ROUTE=${var.kong_rag_route}",
    "KONG_SUPPORT_ROUTE=${var.kong_support_route}",
    "KONG_MODEL=${var.kong_model}",
  ]

  ports {
    internal = 8080
    external = var.chatbot_port
    ip       = "127.0.0.1"
  }

  networks_advanced {
    name = docker_network.chatbot.name
  }

  depends_on = [
    docker_container.kong,
    docker_container.vector_db,
  ]
}

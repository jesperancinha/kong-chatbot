locals {
  konnect_cluster_cert_path = abspath(var.konnect_cluster_cert_path)
  konnect_cluster_key_path  = abspath(var.konnect_cluster_key_path)
}

resource "docker_network" "chatbot" {
  name = "kong-chatbot"
}

resource "docker_volume" "vector_data" {
  # Retain indexed documents when switching to local mode.
  name = "kong-chatbot-vector-data"
}

resource "docker_image" "kong" {
  name         = var.mode == "local" ? var.kong_local_image : var.kong_gateway_image
  keep_locally = true
}

resource "docker_image" "redis" {
  count        = var.mode == "konnect" ? 1 : 0
  name         = var.redis_image
  keep_locally = true
}

resource "docker_image" "chatbot" {
  name = var.chatbot_image

  build {
    context    = abspath("${path.module}/..")
    dockerfile = abspath("${path.module}/../Dockerfile")
    tag        = [var.chatbot_image]
    builder    = var.docker_builder
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
  count   = var.mode == "konnect" ? 1 : 0
  name    = "kong-chatbot-vector-db"
  image   = docker_image.redis[0].image_id
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
  name         = "kong-chatbot-gateway"
  image        = docker_image.kong.image_id
  restart      = "unless-stopped"
  wait         = true
  wait_timeout = 180

  healthcheck {
    test     = ["CMD", "kong", "health"]
    interval = "5s"
    timeout  = "5s"
    retries  = 30
  }

  env = concat([
    "KONG_DATABASE=off",
    "KONG_PROXY_LISTEN=0.0.0.0:8000",
    "KONG_ADMIN_LISTEN=off",
    "KONG_STATUS_LISTEN=0.0.0.0:8100",
    ], var.mode == "local" ? [
    "KONG_DECLARATIVE_CONFIG=/etc/kong/local.yaml",
    ] : [
    "KONG_ROLE=data_plane",
    "KONG_KONNECT_MODE=on",
    "KONG_VITALS=off",
    "KONG_LUA_SSL_TRUSTED_CERTIFICATE=system",
    "KONG_CLUSTER_MTLS=pki",
    "KONG_CLUSTER_CONTROL_PLANE=${var.kong_cluster_control_plane}",
    "KONG_CLUSTER_SERVER_NAME=${var.kong_cluster_server_name}",
    "KONG_CLUSTER_TELEMETRY_ENDPOINT=${var.kong_cluster_telemetry_endpoint}",
    "KONG_CLUSTER_TELEMETRY_SERVER_NAME=${var.kong_cluster_telemetry_server_name}",
    "KONG_CLUSTER_CERT=/run/secrets/konnect-cluster.crt",
    "KONG_CLUSTER_CERT_KEY=/run/secrets/konnect-cluster.key",
  ])

  labels {
    label = "chatbot.gateway-config"
    value = var.mode == "local" ? filesha1("${path.module}/../kong/local.yaml") : "konnect"
  }

  dynamic "volumes" {
    for_each = var.mode == "local" ? {
      "/etc/kong/local.yaml" = abspath("${path.module}/../kong/local.yaml")
      } : {
      "/run/secrets/konnect-cluster.crt" = local.konnect_cluster_cert_path
      "/run/secrets/konnect-cluster.key" = local.konnect_cluster_key_path
    }
    content {
      host_path      = volumes.value
      container_path = volumes.key
      read_only      = true
    }
  }

  lifecycle {
    precondition {
      condition = var.mode == "local" || (
        fileexists(local.konnect_cluster_cert_path) &&
        fileexists(local.konnect_cluster_key_path) &&
        var.kong_cluster_control_plane != "" &&
        var.kong_cluster_server_name != "" &&
        var.kong_cluster_telemetry_endpoint != "" &&
        var.kong_cluster_telemetry_server_name != "" &&
        var.redis_password != "unused-in-local-mode"
      )
      error_message = "Konnect mode requires valid cluster certificates, endpoints and an explicit Redis password. Run make konnect-bootstrap first."
    }
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
    "KONG_MODEL=${var.mode == "local" ? var.local_chat_model : var.kong_model}",
    "KONG_READ_TIMEOUT=${var.mode == "local" ? "180s" : "30s"}",
    "RAG_MODE=${var.mode == "local" ? "local" : "gateway"}",
    "RAG_DOCUMENTS_PATH=/app/knowledge",
    "RAG_EMBEDDING_MODEL=${var.local_embedding_model}",
    "KONG_EMBEDDINGS_ROUTE=/embeddings/api/embed",
    "KNOWLEDGE_REVISION=${sha1(join("", [for file in sort(tolist(fileset("${path.module}/../knowledge", "**"))) : filesha1("${path.module}/../knowledge/${file}")]))}",
  ]

  volumes {
    host_path      = abspath("${path.module}/../knowledge")
    container_path = "/app/knowledge"
    read_only      = true
  }

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
    terraform_data.models,
  ]
}

resource "docker_image" "ollama" {
  count        = var.mode == "local" ? 1 : 0
  name         = var.ollama_image
  keep_locally = true
}

resource "docker_volume" "ollama_data" {
  # Kept in both modes so switching modes does not delete downloaded models.
  name = "kong-chatbot-ollama-data"
}

resource "docker_container" "ollama" {
  count   = var.mode == "local" ? 1 : 0
  name    = "kong-chatbot-ollama"
  image   = docker_image.ollama[0].image_id
  restart = "unless-stopped"
  volumes {
    volume_name    = docker_volume.ollama_data.name
    container_path = "/root/.ollama"
  }
  networks_advanced {
    name    = docker_network.chatbot.name
    aliases = ["ollama"]
  }
}

resource "terraform_data" "models" {
  count = var.mode == "local" ? 1 : 0
  triggers_replace = [
    docker_container.ollama[0].id,
    var.local_chat_model,
    var.local_embedding_model,
  ]
  provisioner "local-exec" {
    command = "sh ../scripts/pull-models.sh"
    environment = {
      OLLAMA_CONTAINER = docker_container.ollama[0].name
      CHAT_MODEL       = var.local_chat_model
      EMBEDDING_MODEL  = var.local_embedding_model
    }
  }
}

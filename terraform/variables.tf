variable "kong_gateway_image" {
  description = "Kong Gateway data-plane image compatible with the Konnect control plane."
  type        = string
  default     = "kong/kong-gateway:3.16.0.1"
}

variable "redis_image" {
  description = "Redis Stack image with RediSearch support for vector search."
  type        = string
  default     = "redis/redis-stack-server:7.4.0-v3"
}

variable "chatbot_image" {
  description = "Name and tag to use for the locally built chatbot image."
  type        = string
  default     = "kong-chatbot:terraform"
}

variable "docker_builder" {
  description = "Buildx builder name. Make detects the active builder; direct Terraform users may override this."
  type        = string
  default     = "default"
}

variable "kong_cluster_control_plane" {
  description = "Konnect control-plane hostname and port, for example cp.example.konghq.com:443."
  type        = string
  default     = ""
}

variable "kong_cluster_server_name" {
  description = "TLS server name for the Konnect control-plane connection."
  type        = string
  default     = ""
}

variable "kong_cluster_telemetry_endpoint" {
  description = "Konnect telemetry endpoint hostname and port, for example telemetry.example.konghq.com:443."
  type        = string
  default     = ""
}

variable "kong_cluster_telemetry_server_name" {
  description = "TLS server name for the Konnect telemetry connection."
  type        = string
  default     = ""
}

variable "konnect_cluster_cert_path" {
  description = "Path to the Konnect data-plane cluster certificate on the Docker host."
  type        = string
  default     = "../secrets/konnect-cluster.crt"
  nullable    = false

}

variable "konnect_cluster_key_path" {
  description = "Path to the Konnect data-plane cluster private key on the Docker host."
  type        = string
  default     = "../secrets/konnect-cluster.key"
  nullable    = false

}

variable "redis_password" {
  description = "Password used by Redis and configured in the Konnect RAG Injector Redis connection."
  type        = string
  sensitive   = true
  default     = "unused-in-local-mode"
  nullable    = false

  validation {
    condition     = length(var.redis_password) >= 16
    error_message = "redis_password must contain at least 16 characters."
  }
}

variable "kong_proxy_port" {
  description = "Host port for the Kong proxy, bound to loopback."
  type        = number
  default     = 8000
}

variable "chatbot_port" {
  description = "Host port for the chatbot API, bound to loopback."
  type        = number
  default     = 8080
}

variable "kong_rag_route" {
  description = "Kong route path used by the chatbot RAG endpoint."
  type        = string
  default     = "/rag/v1/chat/completions"
}

variable "kong_support_route" {
  description = "Kong route path used by the chatbot support endpoint."
  type        = string
  default     = "/support/v1/chat/completions"
}

variable "kong_model" {
  description = "Model alias configured for the Kong AI Proxy route."
  type        = string
  default     = "my-gpt"
}
variable "mode" {
  description = "local uses OSS Kong/Ollama/Spring retrieval; konnect uses managed AI plugins."
  type        = string
  default     = "local"
  validation {
    condition     = contains(["local", "konnect"], var.mode)
    error_message = "mode must be local or konnect."
  }
}

variable "kong_local_image" {
  type    = string
  default = "kong:3.9.4"
}

variable "ollama_image" {
  type    = string
  default = "ollama/ollama:0.13.5"
}

variable "local_chat_model" {
  type    = string
  default = "qwen2.5:1.5b"
}

variable "local_embedding_model" {
  type    = string
  default = "nomic-embed-text"
}

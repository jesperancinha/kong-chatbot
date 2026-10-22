variable "kong_gateway_image" {
  description = "Kong Gateway data-plane image compatible with the Konnect control plane."
  type        = string
  default     = "kong/kong-gateway:3.10.0.2"
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

variable "kong_cluster_control_plane" {
  description = "Konnect control-plane hostname and port, for example cp.example.konghq.com:443."
  type        = string
}

variable "kong_cluster_server_name" {
  description = "TLS server name for the Konnect control-plane connection."
  type        = string
}

variable "kong_cluster_telemetry_endpoint" {
  description = "Konnect telemetry endpoint hostname and port, for example telemetry.example.konghq.com:443."
  type        = string
}

variable "kong_cluster_telemetry_server_name" {
  description = "TLS server name for the Konnect telemetry connection."
  type        = string
}

variable "konnect_cluster_cert_path" {
  description = "Path to the Konnect data-plane cluster certificate on the Docker host."
  type        = string
  default     = "../secrets/konnect-cluster.crt"
  nullable    = false

  validation {
    condition     = fileexists(abspath(var.konnect_cluster_cert_path))
    error_message = "The Konnect cluster certificate must exist at konnect_cluster_cert_path."
  }
}

variable "konnect_cluster_key_path" {
  description = "Path to the Konnect data-plane cluster private key on the Docker host."
  type        = string
  default     = "../secrets/konnect-cluster.key"
  nullable    = false

  validation {
    condition     = fileexists(abspath(var.konnect_cluster_key_path))
    error_message = "The Konnect cluster private key must exist at konnect_cluster_key_path."
  }
}

variable "redis_password" {
  description = "Password used by Redis and configured in the Konnect RAG Injector Redis connection."
  type        = string
  sensitive   = true
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

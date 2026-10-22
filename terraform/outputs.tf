output "chatbot_url" {
  description = "Local chatbot API endpoint."
  value       = "http://127.0.0.1:${var.chatbot_port}"
}

output "kong_proxy_url" {
  description = "Local Kong proxy endpoint."
  value       = "http://127.0.0.1:${var.kong_proxy_port}"
}

output "redis_container_name" {
  description = "Redis Stack container name. Redis is not published on a host port."
  value       = var.mode == "konnect" ? docker_container.vector_db[0].name : null
}

output "mode" {
  value = var.mode
}

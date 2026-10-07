package org.jesperancinha.kong.chatbot.gateway

interface AiGateway {
    fun complete(route: String, model: String, messages: List<ChatMessage>): String
}

data class ChatMessage(val role: String, val content: String)

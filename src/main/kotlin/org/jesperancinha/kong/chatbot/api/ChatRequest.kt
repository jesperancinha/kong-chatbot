package org.jesperancinha.kong.chatbot.api

import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.Size

data class ChatRequest(
    @field:NotBlank
    @field:Size(max = 8000)
    val message: String
)

data class ChatResponse(val response: String)

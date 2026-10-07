package org.jesperancinha.kong.chatbot.api

import jakarta.validation.Valid
import org.jesperancinha.kong.chatbot.service.ChatService
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestBody
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/api")
class ChatController(private val chatService: ChatService) {
    @PostMapping("/chat")
    fun chat(@Valid @RequestBody request: ChatRequest): ChatResponse =
        ChatResponse(chatService.ragChat(request.message))

    @PostMapping("/rag/chat")
    fun ragChat(@Valid @RequestBody request: ChatRequest): ChatResponse =
        ChatResponse(chatService.ragChat(request.message))

    @PostMapping("/support/chat")
    fun supportChat(@Valid @RequestBody request: ChatRequest): ChatResponse =
        ChatResponse(chatService.supportChat(request.message))
}

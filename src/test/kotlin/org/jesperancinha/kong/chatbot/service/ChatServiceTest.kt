package org.jesperancinha.kong.chatbot.service

import org.jesperancinha.kong.chatbot.gateway.AiGateway
import org.jesperancinha.kong.chatbot.gateway.ChatMessage
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class ChatServiceTest {
    private val gateway = RecordingAiGateway()
    private val service = ChatService(gateway, "/rag", "/support", "test-model")

    @Test
    fun `RAG chat uses retrieval route and grounded-answer instruction`() {
        val answer = service.ragChat("deployment checks")

        assertEquals("test answer", answer)
        assertEquals("/rag", gateway.route)
        assertEquals("test-model", gateway.model)
        assertTrue(gateway.messages.first().content.contains("retrieved"))
        assertEquals(ChatMessage("user", "deployment checks"), gateway.messages.last())
    }

    @Test
    fun `support chat uses its own route and support policy`() {
        service.supportChat("change account email")

        assertEquals("/support", gateway.route)
        assertTrue(gateway.messages.first().content.contains("Never request or reveal"))
        assertTrue(gateway.messages.first().content.contains("escalate"))
        assertEquals(ChatMessage("user", "change account email"), gateway.messages.last())
    }

    private class RecordingAiGateway : AiGateway {
        lateinit var route: String
        lateinit var model: String
        lateinit var messages: List<ChatMessage>

        override fun complete(route: String, model: String, messages: List<ChatMessage>): String {
            this.route = route
            this.model = model
            this.messages = messages
            return "test answer"
        }
    }
}

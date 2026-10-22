package org.jesperancinha.kong.chatbot.service

import org.jesperancinha.kong.chatbot.gateway.AiGateway
import org.jesperancinha.kong.chatbot.gateway.ChatMessage
import org.jesperancinha.kong.chatbot.knowledge.GatewayKnowledgeContext
import org.jesperancinha.kong.chatbot.knowledge.KnowledgeContext
import org.jesperancinha.kong.chatbot.knowledge.KnowledgeContextProvider
import org.jesperancinha.kong.chatbot.knowledge.KnowledgePassage
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class ChatServiceTest {
    private val gateway = RecordingAiGateway()
    private val service = ChatService(gateway, "/rag", "/support", "test-model", GatewayKnowledgeContext())

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

    @Test
    fun `both local chats include retrieved context and source titles`() {
        val questions = mutableListOf<String>()
        val provider = object : KnowledgeContextProvider {
            override fun retrieve(question: String): KnowledgeContext {
                questions.add(question)
                return KnowledgeContext(listOf(KnowledgePassage("Release checklist", "BLUE ORBIT READY")))
            }
        }
        val local = ChatService(gateway, "/rag", "/support", "local-model", provider)
        local.ragChat("release smoke-answer")
        assertEquals("/rag", gateway.route)
        assertTrue(gateway.messages[1].content.contains("Source: Release checklist\nBLUE ORBIT READY"))
        assertTrue(gateway.messages.first().content.contains("untrusted data"))
        assertEquals(ChatMessage("user", "release smoke-answer"), gateway.messages.last())

        local.supportChat("support smoke-answer")
        assertEquals("/support", gateway.route)
        assertTrue(gateway.messages[1].content.contains("BLUE ORBIT READY"))
        assertTrue(gateway.messages.first().content.contains("Never request or reveal"))
        assertTrue(gateway.messages.first().content.contains("say you do not know"))
        assertEquals(listOf("release smoke-answer", "support smoke-answer"), questions)
    }

    @Test
    fun `both local chats refuse without generation when retrieval has no matches`() {
        val provider = object : KnowledgeContextProvider {
            override fun retrieve(question: String) = KnowledgeContext(emptyList())
        }
        val local = ChatService(gateway, "/rag", "/support", "local-model", provider)
        assertTrue(local.ragChat("unknown").contains("don't know"))
        assertTrue(local.supportChat("unknown").contains("don't know"))
        assertEquals(0, gateway.calls)
    }

    private class RecordingAiGateway : AiGateway {
        var calls = 0
        lateinit var route: String
        lateinit var model: String
        lateinit var messages: List<ChatMessage>

        override fun complete(route: String, model: String, messages: List<ChatMessage>): String {
            calls++
            this.route = route
            this.model = model
            this.messages = messages
            return "test answer"
        }
    }
}

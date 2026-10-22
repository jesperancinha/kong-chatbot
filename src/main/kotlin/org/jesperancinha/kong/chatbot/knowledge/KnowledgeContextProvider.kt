package org.jesperancinha.kong.chatbot.knowledge

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty
import org.springframework.stereotype.Component

data class KnowledgePassage(val title: String, val text: String)
data class KnowledgeContext(val passages: List<KnowledgePassage>)

interface KnowledgeContextProvider {
    // null delegates retrieval to Kong; an empty local context must not trigger generation.
    fun retrieve(question: String): KnowledgeContext?
}

@Component
@ConditionalOnProperty(name = ["rag.mode"], havingValue = "gateway", matchIfMissing = true)
class GatewayKnowledgeContext : KnowledgeContextProvider {
    override fun retrieve(question: String): KnowledgeContext? = null
}

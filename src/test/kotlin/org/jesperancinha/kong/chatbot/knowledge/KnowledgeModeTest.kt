package org.jesperancinha.kong.chatbot.knowledge

import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.springframework.boot.test.context.runner.ApplicationContextRunner
import org.springframework.context.annotation.Configuration
import org.springframework.context.annotation.Import

class KnowledgeModeTest {
    private val runner = ApplicationContextRunner().withUserConfiguration(KnowledgeConfiguration::class.java)
        .withBean(EmbeddingClient::class.java, { EmbeddingClient { listOf(1.0) } })
        .withPropertyValues(
            "rag.documents-path=knowledge",
            "rag.top-k=3",
            "rag.min-score=0.35"
        )

    @Test
    fun `default and explicit gateway modes do not access embeddings or documents`() {
        listOf(runner, runner.withPropertyValues("rag.mode=gateway")).forEach { gatewayRunner ->
            gatewayRunner.withPropertyValues("rag.documents-path=does-not-exist").run { context ->
                assertNull(context.startupFailure)
                assertTrue(context.getBean(KnowledgeContextProvider::class.java) is GatewayKnowledgeContext)
                assertNull(context.getBean(KnowledgeContextProvider::class.java).retrieve("question"))
            }
        }
    }

    @Test
    fun `local mode builds the index before the context is ready`() {
        runner.withPropertyValues("rag.mode=local").run { context ->
            assertNull(context.startupFailure)
            val provider = context.getBean(KnowledgeContextProvider::class.java)
            assertTrue(provider is LocalKnowledgeContext)
            assertTrue(provider.retrieve("smoke-answer")!!.passages.isNotEmpty())
        }
    }

    @Test
    fun `local startup fails when documents are unavailable`() {
        runner.withPropertyValues("rag.mode=local", "rag.documents-path=does-not-exist").run { context ->
            assertNotNull(context.startupFailure)
        }
    }

    @Configuration(proxyBeanMethods = false)
    @Import(GatewayKnowledgeContext::class, LocalKnowledgeContext::class)
    class KnowledgeConfiguration
}

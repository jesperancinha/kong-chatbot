package org.jesperancinha.kong.chatbot.knowledge

import org.jesperancinha.kong.chatbot.gateway.KongGatewayException
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import java.nio.file.Files
import java.nio.file.Path
import java.util.UUID

class LocalKnowledgeContextTest {
    private val directory = Files.createDirectories(Path.of("target", "knowledge-test-${UUID.randomUUID()}"))

    @AfterEach
    fun cleanup() {
        Files.walk(directory).use { paths -> paths.sorted(Comparator.reverseOrder()).forEach { Files.delete(it) } }
    }

    private fun document(name: String, text: String) {
        val path = directory.resolve(name)
        Files.createDirectories(path.parent)
        Files.writeString(path, text)
    }

    private fun retriever(
        embeddings: EmbeddingClient = EmbeddingClient { listOf(1.0, 0.0) },
        topK: Int = 3,
        minScore: Double = 0.35,
        chunkSize: Int = 1200,
        overlap: Int = 200,
        contextSize: Int = 6000
    ) = LocalKnowledgeContext(embeddings, directory.toString(), topK, minScore, chunkSize, overlap, contextSize)

    @Test
    fun `reads supported documents recursively and resolves ties in stable path order`() {
        document("z.TXT", "Last document")
        document("nested/a.md", "# First title\nFirst document")
        document("ignored.json", "Do not ingest this")
        val inputs = mutableListOf<String>()
        val local = retriever(EmbeddingClient { inputs.add(it); listOf(1.0, 0.0) }, topK = 2)
        local.initialize()
        assertEquals(listOf("# First title\nFirst document", "Last document"), inputs)
        assertEquals(listOf("First title", "z.TXT"), local.retrieve("question").passages.map { it.title })
        assertEquals(listOf("First title", "z.TXT"), local.retrieve("question").passages.map { it.title })
    }

    @Test
    fun `uses cosine similarity threshold and top k rather than raw vector magnitude`() {
        document("a.txt", "orthogonal")
        document("b.txt", "near")
        document("c.txt", "exact")
        val local = retriever(EmbeddingClient {
            when (it) {
                "orthogonal" -> listOf(0.0, 1000.0)
                "near" -> listOf(1.0, 1.0)
                else -> listOf(10.0, 0.0)
            }
        }, topK = 1, minScore = 0.8)
        local.initialize()
        assertEquals(listOf("c.txt"), local.retrieve("question").passages.map { it.title })
    }

    @Test
    fun `no supported retrieval yields empty context`() {
        document("a.txt", "document")
        val local = retriever(EmbeddingClient { if (it == "document") listOf(1.0, 0.0) else listOf(0.0, 1.0) })
        local.initialize()
        assertTrue(local.retrieve("unrelated").passages.isEmpty())
    }

    @Test
    fun `chunks overlap and context is bounded`() {
        document("a.txt", "abcdefghijklm")
        val inputs = mutableListOf<String>()
        val local = retriever(
            EmbeddingClient { inputs.add(it); listOf(1.0) },
            chunkSize = 6, overlap = 2, contextSize = 22
        )
        local.initialize()
        assertEquals(listOf("abcdef", "efghij", "ijklm"), inputs)
        val passages = local.retrieve("question").passages
        assertEquals(1, passages.size)
        assertEquals("abcde", passages.single().text)
        assertTrue(passages.sumOf { it.title.length + it.text.length + 12 } <= 22)
    }

    @Test
    fun `empty index and missing directory fail startup`() {
        document("blank.md", "   ")
        document("ignored.json", "not knowledge")
        assertTrue(assertThrows(IllegalStateException::class.java) { retriever().initialize() }.message!!.contains("empty"))
        val missing = LocalKnowledgeContext(
            EmbeddingClient { listOf(1.0) }, directory.resolve("missing").toString(), 3, 0.35, 1200, 200, 6000
        )
        assertTrue(assertThrows(IllegalStateException::class.java) { missing.initialize() }.message!!.contains("unavailable"))
    }

    @Test
    fun `invalid document vectors and unavailable embeddings fail startup explicitly`() {
        document("a.md", "document")
        listOf(emptyList(), listOf(0.0), listOf(Double.NaN), listOf(Double.POSITIVE_INFINITY)).forEach { vector ->
            val failure = assertThrows(IllegalStateException::class.java) {
                retriever(EmbeddingClient { vector }).initialize()
            }
            assertTrue(failure.message!!.contains("embeddings unavailable or invalid"))
        }
        assertThrows(IllegalStateException::class.java) {
            retriever(EmbeddingClient { throw KongGatewayException("unavailable") }).initialize()
        }
    }

    @Test
    fun `inconsistent document or query dimensions are rejected`() {
        document("a.txt", "first")
        document("b.txt", "second")
        assertThrows(IllegalStateException::class.java) {
            retriever(EmbeddingClient { if (it == "first") listOf(1.0) else listOf(1.0, 0.0) }).initialize()
        }
        val local = retriever(EmbeddingClient { if (it == "question") listOf(1.0) else listOf(1.0, 0.0) })
        local.initialize()
        assertThrows(KongGatewayException::class.java) { local.retrieve("question") }
    }

    @Test
    fun `invalid query vectors fail without producing context`() {
        document("a.txt", "document")
        listOf(emptyList(), listOf(0.0), listOf(Double.NaN)).forEach { vector ->
            val local = retriever(EmbeddingClient { if (it == "document") listOf(1.0) else vector })
            local.initialize()
            assertThrows(KongGatewayException::class.java) { local.retrieve("question") }
        }
    }

    @Test
    fun `finite very large vectors are normalized without overflow`() {
        document("a.txt", "document")
        val local = retriever(EmbeddingClient { listOf(Double.MAX_VALUE, Double.MAX_VALUE) })
        local.initialize()
        assertFalse(local.retrieve("question").passages.isEmpty())
    }

    @Test
    fun `invalid retrieval and chunk limits fail before embedding`() {
        document("a.txt", "document")
        listOf(
            retriever(topK = 0), retriever(minScore = Double.NaN),
            retriever(minScore = 1.1), retriever(chunkSize = 0),
            retriever(chunkSize = 10, overlap = 10), retriever(contextSize = 0)
        ).forEach { local -> assertThrows(IllegalArgumentException::class.java) { local.initialize() } }
    }

    @Test
    fun `index is rebuilt from documents on restart`() {
        document("a.txt", "first version")
        val first = retriever()
        first.initialize()
        document("a.txt", "updated version")
        val restarted = retriever()
        restarted.initialize()
        assertEquals("first version", first.retrieve("question").passages.single().text)
        assertEquals("updated version", restarted.retrieve("question").passages.single().text)
    }
}

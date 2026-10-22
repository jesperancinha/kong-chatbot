package org.jesperancinha.kong.chatbot.knowledge

import jakarta.annotation.PostConstruct
import org.jesperancinha.kong.chatbot.gateway.KongGatewayException
import org.springframework.beans.factory.annotation.Value
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty
import org.springframework.stereotype.Component
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.LinkOption.NOFOLLOW_LINKS
import java.nio.file.Path
import kotlin.math.abs
import kotlin.math.sqrt

@Component
@ConditionalOnProperty(name = ["rag.mode"], havingValue = "local")
class LocalKnowledgeContext(
    private val embeddings: EmbeddingClient,
    @Value("\${rag.documents-path}") private val documentsPath: String,
    @Value("\${rag.top-k}") private val topK: Int,
    @Value("\${rag.min-score}") private val minScore: Double,
    @Value("\${rag.chunk-size:1200}") private val chunkSize: Int,
    @Value("\${rag.chunk-overlap:200}") private val chunkOverlap: Int,
    @Value("\${rag.max-context-chars:6000}") private val maxContextChars: Int
) : KnowledgeContextProvider {
    private data class IndexedPassage(val passage: KnowledgePassage, val vector: List<Double>, val order: Int)
    private var index: List<IndexedPassage> = emptyList()

    @PostConstruct
    fun initialize() {
        require(topK in 1..100) { "rag.top-k must be between 1 and 100" }
        require(minScore.isFinite() && minScore in -1.0..1.0) { "rag.min-score must be between -1 and 1" }
        require(chunkSize in 1..10000 && chunkOverlap in 0 until chunkSize) {
            "rag.chunk-size must be 1..10000 and rag.chunk-overlap must be smaller than the chunk size"
        }
        require(maxContextChars in 1..100000) { "rag.max-context-chars must be between 1 and 100000" }
        val root = Path.of(documentsPath)
        check(Files.isDirectory(root)) { "Local RAG documents directory is unavailable: $documentsPath" }
        val passages = mutableListOf<KnowledgePassage>()
        Files.walk(root).use { paths ->
            paths.filter { Files.isRegularFile(it, NOFOLLOW_LINKS) }
                .filter { it.fileName.toString().substringAfterLast('.', "").lowercase() in setOf("md", "txt") }
                .sorted(compareBy { root.relativize(it).toString() })
                .forEach { path ->
                    val bytes = Files.newInputStream(path).use { it.readNBytes(MAX_DOCUMENT_BYTES + 1) }
                    check(bytes.size <= MAX_DOCUMENT_BYTES) { "Local RAG document exceeds 1 MiB: $path" }
                    val text = String(bytes, StandardCharsets.UTF_8).replace("\r\n", "\n").trim()
                    val title = text.lineSequence().firstOrNull { it.startsWith("# ") }
                        ?.removePrefix("# ")?.trim()?.take(200)
                        ?.takeIf { it.isNotBlank() }
                        ?: root.relativize(path).toString().take(200)
                    var offset = 0
                    while (offset < text.length) {
                        val end = minOf(offset + chunkSize, text.length)
                        val chunk = text.substring(offset, end).trim()
                        if (chunk.isNotBlank()) passages.add(KnowledgePassage(title, chunk))
                        check(passages.size <= MAX_CHUNKS) { "Local RAG index exceeds $MAX_CHUNKS chunks" }
                        if (end == text.length) break
                        offset = end - chunkOverlap
                    }
                }
        }
        check(passages.isNotEmpty()) { "Local RAG index is empty; provide nonempty .md or .txt documents" }
        index = try {
            var dimensions: Int? = null
            passages.mapIndexed { order, passage ->
                val vector = normalize(embeddings.embed(passage.text))
                check(dimensions == null || vector.size == dimensions) { "Embedding dimensions changed during ingestion" }
                dimensions = vector.size
                IndexedPassage(passage, vector, order)
            }
        } catch (exception: KongGatewayException) {
            throw IllegalStateException("Local RAG index initialization failed: embeddings unavailable or invalid", exception)
        } catch (exception: IllegalStateException) {
            throw IllegalStateException("Local RAG index initialization failed: embeddings unavailable or invalid", exception)
        }
    }

    override fun retrieve(question: String): KnowledgeContext {
        check(index.isNotEmpty()) { "Local RAG index is not ready" }
        val query = try {
            normalize(embeddings.embed(question)).also {
                check(it.size == index.first().vector.size) { "Query embedding dimensions differ from the index" }
            }
        } catch (exception: IllegalStateException) {
            throw KongGatewayException("Local RAG query embedding unavailable or invalid", exception)
        }
        var remaining = maxContextChars
        val passages = index.map { entry ->
            entry to entry.vector.indices.sumOf { entry.vector[it] * query[it] }.coerceIn(-1.0, 1.0)
        }.filter { (_, score) -> score >= minScore }
            .sortedWith(compareByDescending<Pair<IndexedPassage, Double>> { it.second }.thenBy { it.first.order })
            .take(topK)
            .mapNotNull { (entry, _) ->
                val headerSize = entry.passage.title.length + 12
                if (remaining <= headerSize) return@mapNotNull null
                val passage = entry.passage.copy(text = entry.passage.text.take(remaining - headerSize))
                remaining -= headerSize + passage.text.length
                passage
            }
        return KnowledgeContext(passages)
    }

    private fun normalize(vector: List<Double>): List<Double> {
        check(vector.isNotEmpty() && vector.all(Double::isFinite)) { "Embedding vector is empty or non-finite" }
        val scale = vector.maxOf { abs(it) }
        check(scale > 0.0) { "Embedding vector has zero magnitude" }
        // Scaling before computing the norm avoids overflow for otherwise valid finite vectors.
        val scaled = vector.map { it / scale }
        val norm = sqrt(scaled.sumOf { it * it })
        return scaled.map { it / norm }
    }

    private companion object {
        const val MAX_DOCUMENT_BYTES = 1024 * 1024
        const val MAX_CHUNKS = 10000
    }
}

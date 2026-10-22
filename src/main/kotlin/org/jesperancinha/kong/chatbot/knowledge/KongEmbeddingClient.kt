package org.jesperancinha.kong.chatbot.knowledge

import org.jesperancinha.kong.chatbot.gateway.KongGatewayException
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.beans.factory.annotation.Value
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty
import org.springframework.http.MediaType
import org.springframework.http.client.JdkClientHttpRequestFactory
import org.springframework.stereotype.Component
import org.springframework.web.client.RestClient
import org.springframework.web.client.RestClientException
import java.net.http.HttpClient
import java.time.Duration

fun interface EmbeddingClient {
    fun embed(input: String): List<Double>
}

@Component
@ConditionalOnProperty(name = ["rag.mode"], havingValue = "local")
class KongEmbeddingClient internal constructor(
    private val client: RestClient,
    private val route: String,
    private val model: String
) : EmbeddingClient {
    @Autowired
    constructor(
        builder: RestClient.Builder,
        @Value("\${kong.url}") kongUrl: String,
        @Value("\${kong.embeddings-route}") route: String,
        @Value("\${rag.embedding-model}") model: String,
        @Value("\${kong.connect-timeout:2s}") connectTimeout: Duration,
        @Value("\${kong.read-timeout:30s}") readTimeout: Duration
    ) : this(
        builder.baseUrl(kongUrl).requestFactory(
            JdkClientHttpRequestFactory(HttpClient.newBuilder().connectTimeout(connectTimeout).build())
                .apply { setReadTimeout(readTimeout) }
        ).build(),
        route,
        model
    )

    override fun embed(input: String): List<Double> {
        val response = try {
            client.post().uri(route)
                .contentType(MediaType.APPLICATION_JSON)
                .body(mapOf("model" to model, "input" to input))
                .retrieve().body(OllamaEmbeddingResponse::class.java)
        } catch (exception: RestClientException) {
            throw KongGatewayException("Kong embeddings request failed", exception)
        }
        return response?.embeddings?.singleOrNull()
            ?.takeIf { it.isNotEmpty() && it.all { value -> value != null && value.isFinite() } && it.any { value -> value != 0.0 } }
            ?.map { requireNotNull(it) }
            ?: throw KongGatewayException("Kong embeddings returned an invalid vector")
    }
}

private data class OllamaEmbeddingResponse(val embeddings: List<List<Double?>> = emptyList())

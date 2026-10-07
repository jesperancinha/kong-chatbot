package org.jesperancinha.kong.chatbot.gateway

import org.springframework.beans.factory.annotation.Value
import org.springframework.http.MediaType
import org.springframework.stereotype.Component
import org.springframework.web.client.RestClient
import org.springframework.web.client.RestClientException
import org.springframework.http.client.JdkClientHttpRequestFactory
import java.net.http.HttpClient
import java.time.Duration

@Component
class KongAiGatewayClient(
    @Value("\${kong.url}") kongUrl: String,
    private val restClientBuilder: RestClient.Builder,
    @Value("\${kong.connect-timeout:2s}") connectTimeout: Duration,
    @Value("\${kong.read-timeout:30s}") readTimeout: Duration
) : AiGateway {
    private val requestFactory = JdkClientHttpRequestFactory(
        HttpClient.newBuilder().connectTimeout(connectTimeout).build()
    ).apply { setReadTimeout(readTimeout) }
    private val client = restClientBuilder
        .baseUrl(kongUrl)
        .requestFactory(requestFactory)
        .build()

    override fun complete(route: String, model: String, messages: List<ChatMessage>): String {
        val completion = try {
            client.post()
                .uri(route)
                .contentType(MediaType.APPLICATION_JSON)
                .body(ChatCompletionRequest(model, messages))
                .retrieve()
                .body(ChatCompletionResponse::class.java)
        } catch (exception: RestClientException) {
            throw KongGatewayException("Kong AI Gateway request failed", exception)
        } ?: throw KongGatewayException("Kong AI Gateway returned an empty response")

        return completion.choices.firstOrNull()?.message?.content
            ?.takeIf(String::isNotBlank)
            ?: throw KongGatewayException("Kong AI Gateway returned no assistant message")
    }
}

private data class ChatCompletionRequest(
    val model: String,
    val messages: List<ChatMessage>
)

private data class ChatCompletionResponse(
    val choices: List<ChatCompletionChoice> = emptyList()
)

private data class ChatCompletionChoice(
    val message: ChatMessage
)

class KongGatewayException(message: String, cause: Throwable? = null) : RuntimeException(message, cause)

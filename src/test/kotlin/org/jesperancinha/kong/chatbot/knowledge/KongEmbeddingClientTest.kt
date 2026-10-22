package org.jesperancinha.kong.chatbot.knowledge

import org.jesperancinha.kong.chatbot.gateway.KongGatewayException
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Test
import org.springframework.http.HttpMethod
import org.springframework.http.HttpStatus
import org.springframework.http.MediaType
import org.springframework.test.web.client.MockRestServiceServer
import org.springframework.test.web.client.match.MockRestRequestMatchers.content
import org.springframework.test.web.client.match.MockRestRequestMatchers.method
import org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo
import org.springframework.test.web.client.response.MockRestResponseCreators.withStatus
import org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess
import org.springframework.web.client.RestClient

class KongEmbeddingClientTest {
    private val builder = RestClient.builder().baseUrl("http://kong.test:8000")
    private val server = MockRestServiceServer.bindTo(builder).build()
    private val client = KongEmbeddingClient(builder.build(), "/embeddings/api/embed", "nomic-embed-text")

    @Test
    fun `native Ollama request and response pass through Kong`() {
        server.expect(requestTo("http://kong.test:8000/embeddings/api/embed"))
            .andExpect(method(HttpMethod.POST))
            .andExpect(content().contentType(MediaType.APPLICATION_JSON))
            .andExpect(content().json("""{"model":"nomic-embed-text","input":"release checklist"}"""))
            .andRespond(withSuccess("""{"model":"nomic-embed-text","embeddings":[[1.0,0.5]],"total_duration":1}""", MediaType.APPLICATION_JSON))
        assertEquals(listOf(1.0, 0.5), client.embed("release checklist"))
        server.verify()
    }

    @Test
    fun `route and embedding model are configurable`() {
        val custom = KongEmbeddingClient(builder.build(), "/custom/embed", "custom-model")
        server.expect(requestTo("http://kong.test:8000/custom/embed"))
            .andExpect(content().json("""{"model":"custom-model","input":"question"}"""))
            .andRespond(withSuccess("""{"embeddings":[[2,3]]}""", MediaType.APPLICATION_JSON))
        assertEquals(listOf(2.0, 3.0), custom.embed("question"))
        server.verify()
    }

    @Test
    fun `unavailable embedding provider fails explicitly`() {
        server.expect(requestTo("http://kong.test:8000/embeddings/api/embed"))
            .andRespond(withStatus(HttpStatus.SERVICE_UNAVAILABLE))
        assertThrows(KongGatewayException::class.java) { client.embed("question") }
        server.verify()
    }

    @Test
    fun `empty zero malformed and multiple vectors are rejected`() {
        listOf(
            """{}""",
            """{"embeddings":[]}""",
            """{"embeddings":[[]]}""",
            """{"embeddings":[[0,0]]}""",
            """{"embeddings":[[1],[2]]}""",
            """{"embeddings":[["bad"]]}""",
            """{"embeddings":[[null]]}"""
        ).forEach { body ->
            server.reset()
            server.expect(requestTo("http://kong.test:8000/embeddings/api/embed"))
                .andRespond(withSuccess(body, MediaType.APPLICATION_JSON))
            assertThrows(KongGatewayException::class.java, { client.embed("question") }, body)
            server.verify()
        }
    }
}

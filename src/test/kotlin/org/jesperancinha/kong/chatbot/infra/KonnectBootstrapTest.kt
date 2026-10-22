package org.jesperancinha.kong.chatbot.infra

import com.fasterxml.jackson.module.kotlin.jacksonObjectMapper
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.io.TempDir
import java.nio.file.Files
import java.nio.file.Path

class KonnectBootstrapTest {
    @TempDir
    lateinit var directory: Path

    private val mapper = jacksonObjectMapper()

    @Test
    fun `bootstrap generates consistent private configuration and upserts only its own entities`() {
        assumeTrue(ProcessBuilder("sh", "-c", "command -v jq && command -v openssl").start().waitFor() == 0)
        listOf("scripts", "secrets", "terraform", "work", "bin").forEach { Files.createDirectories(directory.resolve(it)) }
        listOf("configure-konnect.sh", "konnect-api.sh").forEach {
            Files.copy(Path.of("scripts", it), directory.resolve("scripts/$it"))
        }
        Files.writeString(directory.resolve("secrets/konnect-cluster.crt"), "fixture")
        Files.writeString(directory.resolve("work/auth"), "fixture")
        Files.writeString(directory.resolve("work/control-plane.json"), """
            {"config":{"control_plane_endpoint":"https://example.cp.konghq.com",
            "telemetry_endpoint":"https://example.tp.konghq.com"}}
        """.trimIndent())
        val mockCurl = directory.resolve("bin/curl")
        Files.writeString(mockCurl, """
            #!/bin/sh
            set -eu
            method=GET
            body=
            while [ "${'$'}#" -gt 0 ]; do
              case "${'$'}1" in
                -X) method=${'$'}2; shift ;;
                --data-binary) body=${'$'}{2#@}; shift ;;
                --config|--connect-timeout|--max-time|-H) shift ;;
                https://*) url=${'$'}1 ;;
              esac
              shift
            done
            printf '%s %s\n' "${'$'}method" "${'$'}url" >> calls
            case "${'$'}url" in
              */dp-client-certificates) printf '{"items":[{"cert":"fixture"}]}' ;;
              */services/kong-chatbot-ai) jq '. + {id:"service-id"}' "${'$'}body" ;;
              */routes/*) jq '. + {id:"route-id"}' "${'$'}body" ;;
              */services/service-id/plugins)
                if [ -f plugins.json ]; then jq '{data:.}' plugins.json; else printf '{"data":[]}'; fi ;;
              */plugins|*/plugins/*)
                name=${'$'}(jq -r '.name' "${'$'}body")
                jq --arg id "${'$'}name-id" '. + {id:${'$'}id}' "${'$'}body" > plugin.json
                if [ ! -f plugins.json ]; then printf '[]' > plugins.json; fi
                jq --slurpfile plugin plugin.json 'map(select(.name != ${'$'}plugin[0].name)) + ${'$'}plugin' plugins.json > next.json
                mv next.json plugins.json
                jq 'if .name == "ai-rag-injector" then .config.embeddings.auth.header_value = "redacted" else . end' plugin.json ;;
              *) echo 'Unexpected API path' >&2; exit 1 ;;
            esac
        """.trimIndent() + "\n")
        assertTrue(mockCurl.toFile().setExecutable(true))

        fun bootstrap() {
            val process = ProcessBuilder(
                "sh", "scripts/configure-konnect.sh", directory.resolve("work").toString(),
                "https://eu.api.konghq.com", "/v2/control-planes/test"
            ).directory(directory.toFile()).redirectErrorStream(true)
            process.environment().apply {
                put("PATH", "${directory.resolve("bin")}:${System.getenv("PATH")}")
                put("OPENAI_API_KEY", "fixture-provider-key")
                put("REDIS_PASSWORD", "fixture-password-123456")
            }
            val execution = process.start()
            val output = execution.inputStream.bufferedReader().readText()
            assertEquals(0, execution.waitFor(), output)
            assertFalse(output.contains("fixture-provider-key"))
        }

        bootstrap()
        bootstrap()
        val calls = Files.readAllLines(directory.resolve("calls"))
        assertEquals(2, calls.count { it.startsWith("POST ") && it.endsWith("/plugins") })
        assertEquals(2, calls.count { it.startsWith("PUT ") && it.contains("/plugins/") })
        val plugin = mapper.readTree(directory.resolve("secrets/konnect-rag-plugin.json").toFile())
        assertEquals("ai-rag-injector-id", plugin["id"].asText())
        assertEquals("kong_chatbot_v1", plugin["config"]["vectordb_namespace"].asText())
        assertEquals(3072, plugin["config"]["vectordb"]["dimensions"].asInt())
        assertTrue(plugin["config"]["stop_on_failure"].asBoolean())
        assertEquals("fixture-password-123456", plugin["config"]["vectordb"]["redis"]["password"].asText())
        assertEquals("Bearer fixture-provider-key", plugin["config"]["embeddings"]["auth"]["header_value"].asText())
        val environment = Files.readString(directory.resolve(".env.konnect"))
        assertTrue(environment.contains("KONG_CLUSTER_CONTROL_PLANE=example.cp.konghq.com:443"))
        assertTrue(environment.contains("KONG_CLUSTER_SERVER_NAME=example.cp.konghq.com"))
        assertFalse(environment.contains("fixture-provider-key"))
        val terraform = Files.readString(directory.resolve("terraform/konnect.tfvars"))
        assertTrue(terraform.contains("""mode = "konnect""""))
        assertFalse(terraform.contains("fixture-provider-key"))
    }
}

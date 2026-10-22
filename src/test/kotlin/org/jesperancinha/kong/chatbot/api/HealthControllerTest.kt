package org.jesperancinha.kong.chatbot.api

import org.junit.jupiter.api.Test
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get
import org.springframework.test.web.servlet.result.MockMvcResultMatchers.content
import org.springframework.test.web.servlet.result.MockMvcResultMatchers.status
import org.springframework.test.web.servlet.setup.MockMvcBuilders

class HealthControllerTest {
    @Test
    fun `readiness endpoint returns only UP status`() {
        MockMvcBuilders.standaloneSetup(HealthController()).build()
            .perform(get("/health"))
            .andExpect(status().isOk)
            .andExpect(content().json("""{"status":"UP"}""", true))
    }
}

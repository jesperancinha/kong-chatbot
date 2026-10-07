package org.jesperancinha.kong.chatbot.api

import org.jesperancinha.kong.chatbot.gateway.KongGatewayException
import org.springframework.http.HttpStatus
import org.springframework.http.ResponseEntity
import org.springframework.web.bind.annotation.ExceptionHandler
import org.springframework.web.bind.annotation.RestControllerAdvice

@RestControllerAdvice
class ApiExceptionHandler {
    @ExceptionHandler(KongGatewayException::class)
    fun handleGatewayFailure(exception: KongGatewayException): ResponseEntity<ApiError> =
        ResponseEntity.status(HttpStatus.BAD_GATEWAY)
            .body(ApiError("ai_gateway_error", exception.message ?: "Kong AI Gateway request failed"))
}

data class ApiError(val code: String, val message: String)

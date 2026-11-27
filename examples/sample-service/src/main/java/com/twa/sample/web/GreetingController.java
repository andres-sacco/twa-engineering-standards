package com.twa.sample.web;

import com.twa.sample.dto.GreetingResponse;
import com.twa.sample.service.GreetingService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.ExampleObject;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.tags.Tag;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@Tag(name = "Greetings")
public class GreetingController {

    private final GreetingService greetingService;

    public GreetingController(GreetingService greetingService) {
        this.greetingService = greetingService;
    }

    @GetMapping(path = "/greetings", produces = "application/json")
    @Operation(operationId = "greet", summary = "Greet someone", description = "Devuelve un saludo para el nombre dado")
    @ApiResponse(
            responseCode = "200",
            description = "El saludo",
            content =
                    @Content(
                            mediaType = "application/json",
                            examples = @ExampleObject(name = "greeting", value = "{\"message\":\"Hola, Ana\"}")))
    public GreetingResponse greet(
            @Parameter(description = "Quién consume la API (web, checkout…)")
                    @RequestHeader(name = "X-Client-Id", required = false)
                    String clientId,
            @Parameter(description = "Nombre a saludar", example = "Ana") @RequestParam(required = false) String name) {
        return new GreetingResponse(greetingService.greet(name));
    }
}

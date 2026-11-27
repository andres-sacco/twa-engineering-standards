package com.twa.sample.controller;

import static org.assertj.core.api.Assertions.assertThat;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class GreetingIT {

    private final HttpClient client = HttpClient.newHttpClient();

    @Value("${local.server.port}")
    private int port;

    @Test
    void greetsOverHttp() throws Exception {
        HttpResponse<String> response = get("/greetings?name=Ana");

        assertThat(response.statusCode()).isEqualTo(200);
        assertThat(response.body()).contains("\"message\":\"Hola, Ana\"");
    }

    @Test
    void exposesLiveness() throws Exception {
        HttpResponse<String> response = get("/health/liveness");

        assertThat(response.statusCode()).isEqualTo(200);
        assertThat(response.body()).contains("\"UP\"");
    }

    private HttpResponse<String> get(String path) throws Exception {
        URI uri = URI.create("http://localhost:" + port + "/api/flights/sample" + path);
        return client.send(HttpRequest.newBuilder(uri).GET().build(), HttpResponse.BodyHandlers.ofString());
    }
}

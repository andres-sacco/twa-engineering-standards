package com.twa.sample.web;

import static org.assertj.core.api.Assertions.assertThat;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.file.Files;
import java.nio.file.Path;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;

/**
 * Exporta la spec que sirve la app a target/openapi.json: de ahí la leen API-01, API-02 (Spectral) y API-03 (oasdiff)
 * en java-ci.yml de twa-engineering-standards.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class OpenApiIT {

    @Value("${local.server.port}")
    private int port;

    @Test
    void exportsTheSpec() throws Exception {
        URI uri = URI.create("http://localhost:" + port + "/api/flights/sample/v3/api-docs");
        HttpResponse<String> response = HttpClient.newHttpClient()
                .send(HttpRequest.newBuilder(uri).GET().build(), HttpResponse.BodyHandlers.ofString());

        assertThat(response.statusCode()).isEqualTo(200);
        Files.writeString(Path.of("target", "openapi.json"), response.body());
    }
}

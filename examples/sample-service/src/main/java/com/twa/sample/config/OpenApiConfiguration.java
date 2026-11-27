package com.twa.sample.config;

import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Contact;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.info.License;
import io.swagger.v3.oas.models.servers.Server;
import io.swagger.v3.oas.models.tags.Tag;
import java.util.List;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/** Datos generales de la spec: el server es relativo, para que la spec sirva en cualquier ambiente. */
@Configuration
public class OpenApiConfiguration {

    @Bean
    public OpenAPI openApi() {
        return new OpenAPI()
                .info(new Info()
                        .title("Sample API")
                        .version("1.0.0")
                        .description("Servicio de prueba de twa-engineering-standards")
                        .contact(new Contact().url("https://github.com/andres-sacco/twa-engineering-standards"))
                        .license(new License().name("MIT").identifier("MIT")))
                .servers(List.of(new Server().url("/api/flights/sample")))
                .tags(List.of(new Tag().name("Greetings").description("Saludos")));
    }
}

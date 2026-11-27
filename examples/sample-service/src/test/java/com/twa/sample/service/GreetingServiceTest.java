package com.twa.sample.service;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class GreetingServiceTest {

    private final GreetingService service = new GreetingService();

    @Test
    void greetsByName() {
        assertThat(service.greet("  Ana ")).isEqualTo("Hola, Ana");
    }

    @Test
    void greetsTwaWithoutName() {
        assertThat(service.greet(null)).isEqualTo("Hola, TWA");
        assertThat(service.greet(" ")).isEqualTo("Hola, TWA");
    }
}

package com.twa.sample.service;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class GreetingServiceTest {

    private final GreetingService service = new GreetingService();

    @Test
    void greetsByName() {
        assertThat(service.greet("  Ana ").message()).isEqualTo("Hola, Ana");
    }

    @Test
    void greetsTwaWithoutName() {
        assertThat(service.greet(null).message()).isEqualTo("Hola, TWA");
        assertThat(service.greet(" ").message()).isEqualTo("Hola, TWA");
    }
}

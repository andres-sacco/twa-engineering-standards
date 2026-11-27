package com.twa.sample.service;

import org.springframework.stereotype.Service;

@Service
public class GreetingService {

    public String greet(String name) {
        String who = (name == null || name.isBlank()) ? "TWA" : name.strip();
        return "Hola, " + who;
    }
}

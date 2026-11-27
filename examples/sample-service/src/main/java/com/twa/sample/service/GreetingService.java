package com.twa.sample.service;

import com.twa.sample.dto.GreetingResponse;
import org.springframework.stereotype.Service;

@Service
public class GreetingService {

    public GreetingResponse greet(String name) {
        String who = (name == null || name.isBlank()) ? "TWA" : name.strip();
        return new GreetingResponse("Hola, " + who);
    }
}

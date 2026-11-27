package com.twa.sample.web;

import com.twa.sample.dto.GreetingResponse;
import com.twa.sample.service.GreetingService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class GreetingController {

    private final GreetingService greetingService;

    public GreetingController(GreetingService greetingService) {
        this.greetingService = greetingService;
    }

    @GetMapping("/greetings")
    public GreetingResponse greet(@RequestParam(required = false) String name) {
        return new GreetingResponse(greetingService.greet(name));
    }
}

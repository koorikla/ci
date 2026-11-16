package dev.koorikla.ci;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class GreetingController {

    static String greet(String name) {
        String n = name == null ? "" : name.strip();
        return "hello, " + (n.isEmpty() ? "world" : n);
    }

    @GetMapping("/")
    public String hello(@RequestParam(name = "name", defaultValue = "") String name) {
        return greet(name);
    }
}

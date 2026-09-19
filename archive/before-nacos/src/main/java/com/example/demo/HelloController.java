package com.example.demo;

import java.time.LocalDateTime;
import java.util.Map;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HelloController {

	@GetMapping("/hello")
	public String hello(@RequestParam(defaultValue = "Spring Boot") String name) {
		return "Hello, " + name + "!";
	}

	@GetMapping("/info")
	public Map<String, Object> info() {
		return Map.of(
				"app", "demo",
				"java", System.getProperty("java.version"),
				"springBoot", org.springframework.boot.SpringBootVersion.getVersion(),
				"time", LocalDateTime.now().toString());
	}
}

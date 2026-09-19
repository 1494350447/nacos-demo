package com.example.provider;

import java.util.LinkedHashMap;
import java.util.Map;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class GreetController {

	/** 当前实例端口，用来区分到底是哪个实例在响应 */
	@Value("${server.port}")
	private int port;

	@GetMapping("/greet")
	public Map<String, Object> greet(@RequestParam(defaultValue = "World") String name) {
		Map<String, Object> result = new LinkedHashMap<>();
		result.put("service", "provider");
		result.put("instance", "provider@" + port);
		result.put("message", "Hi " + name + ", 我是 provider 实例 " + port);
		return result;
	}
}

package com.example.demo;

import java.time.LocalDateTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.cloud.client.discovery.DiscoveryClient;
import org.springframework.cloud.context.config.annotation.RefreshScope;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RefreshScope
public class HelloController {

	private final DiscoveryClient discoveryClient;

	/** 来自 Nacos 配置中心 demo.yaml 的 demo.greeting */
	@Value("${demo.greeting:local-default-not-from-nacos}")
	private String greeting;

	/** 来自 Nacos 配置中心 demo.yaml 的 demo.version，用来观察动态刷新 */
	@Value("${demo.version:0}")
	private String configVersion;

	public HelloController(DiscoveryClient discoveryClient) {
		this.discoveryClient = discoveryClient;
	}

	@GetMapping("/hello")
	public String hello(@RequestParam(defaultValue = "Spring Boot") String name) {
		return "Hello, " + name + "!";
	}

	@GetMapping("/info")
	public Map<String, Object> info() {
		Map<String, Object> result = new LinkedHashMap<>();
		result.put("app", "demo");
		result.put("java", System.getProperty("java.version"));
		result.put("springBoot", org.springframework.boot.SpringBootVersion.getVersion());
		result.put("time", LocalDateTime.now().toString());
		return result;
	}

	/** 展示从 Nacos 配置中心读到的值；Nacos 侧修改后会自动刷新 */
	@GetMapping("/config")
	public Map<String, Object> config() {
		Map<String, Object> result = new LinkedHashMap<>();
		result.put("demo.greeting", greeting);
		result.put("demo.version", configVersion);
		return result;
	}

	/** 通过 Nacos 服务发现列出当前注册的服务实例 */
	@GetMapping("/services")
	public Map<String, Object> services() {
		Map<String, Object> result = new LinkedHashMap<>();
		List<String> names = discoveryClient.getServices();
		for (String name : names) {
			result.put(name, discoveryClient.getInstances(name).stream()
					.map(instance -> instance.getHost() + ":" + instance.getPort())
					.toList());
		}
		return result;
	}
}

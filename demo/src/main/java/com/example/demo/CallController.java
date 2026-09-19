package com.example.demo;

import java.util.LinkedHashMap;
import java.util.Map;

import org.springframework.cloud.client.loadbalancer.LoadBalanced;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestClient;

/**
 * 服务间调用示例：通过 Nacos 服务发现 + 客户端负载均衡调用 provider。
 * 只写服务名 http://provider/... ，不写具体 IP 和端口。
 */
@RestController
public class CallController {

	private final RestClient restClient;

	public CallController(@LoadBalanced RestClient.Builder loadBalancedRestClientBuilder) {
		this.restClient = loadBalancedRestClientBuilder.build();
	}

	@GetMapping("/call")
	public Map<String, Object> call(@RequestParam(defaultValue = "World") String name) {
		Map<String, Object> result = new LinkedHashMap<>();
		result.put("call", "GET http://provider/greet?name=" + name);
		result.put("response", restClient.get()
				.uri("http://provider/greet?name={name}", name)
				.retrieve()
				.body(Object.class));
		return result;
	}

	@Configuration
	static class LoadBalancerConfig {

		@Bean
		@LoadBalanced
		RestClient.Builder loadBalancedRestClientBuilder() {
			return RestClient.builder();
		}
	}
}

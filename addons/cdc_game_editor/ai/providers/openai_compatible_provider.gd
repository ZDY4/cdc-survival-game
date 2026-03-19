@tool
extends Node

const CHAT_COMPLETIONS_PATH := "/chat/completions"
const MODELS_PATH := "/models"


func generate_request(payload: Dictionary) -> Dictionary:
	return await _perform_chat_completion(payload, 0)


func test_connection(config: Dictionary) -> Dictionary:
	var base_url := str(config.get("base_url", "")).strip_edges().trim_suffix("/")
	var api_key := str(config.get("api_key", "")).strip_edges()
	if base_url.is_empty():
		return {"ok": false, "error": "Base URL 不能为空"}
	if api_key.is_empty():
		return {"ok": false, "error": "API Key 未配置"}

	var request := HTTPRequest.new()
	add_child(request)
	request.timeout = max(int(config.get("timeout_sec", 20)), 5)
	var headers := [
		"Accept: application/json",
		"Authorization: Bearer %s" % api_key
	]
	var err := request.request("%s%s" % [base_url, MODELS_PATH], headers, HTTPClient.METHOD_GET)
	if err != OK:
		request.queue_free()
		return {"ok": false, "error": "请求初始化失败: %s" % str(err)}

	var response: Array = await request.request_completed
	request.queue_free()
	return _map_http_response(response)


static func extract_json_payload(raw_text: String) -> Dictionary:
	var trimmed := raw_text.strip_edges()
	if trimmed.is_empty():
		return {"ok": false, "error": "响应为空", "raw_text": raw_text}

	var parsed := JSON.parse_string(trimmed)
	if parsed != null and parsed is Dictionary:
		return {"ok": true, "data": parsed, "raw_text": raw_text}

	var start_index := trimmed.find("{")
	var end_index := trimmed.rfind("}")
	if start_index < 0 or end_index < start_index:
		return {"ok": false, "error": "响应中未找到 JSON 对象", "raw_text": raw_text}

	var slice := trimmed.substr(start_index, end_index - start_index + 1)
	var reparsed := JSON.parse_string(slice)
	if reparsed != null and reparsed is Dictionary:
		return {"ok": true, "data": reparsed, "raw_text": raw_text}

	return {"ok": false, "error": "JSON 解析失败", "raw_text": raw_text}


static func map_http_error(status_code: int, raw_text: String) -> String:
	match status_code:
		400:
			return "请求格式错误 (400)"
		401:
			return "鉴权失败，请检查 API Key (401)"
		403:
			return "请求被拒绝 (403)"
		404:
			return "接口地址不存在 (404)"
		408:
			return "请求超时 (408)"
		429:
			return "请求过于频繁，请稍后重试 (429)"
		500, 502, 503, 504:
			return "AI 服务暂时不可用 (%d)" % status_code
		_:
			var suffix := ""
			if not raw_text.strip_edges().is_empty():
				suffix = ": %s" % raw_text.left(160)
			return "HTTP 错误 %d%s" % [status_code, suffix]


func _perform_chat_completion(payload: Dictionary, retry_count: int) -> Dictionary:
	var config: Dictionary = payload.get("provider_config", {})
	var base_url := str(config.get("base_url", "")).strip_edges().trim_suffix("/")
	var api_key := str(config.get("api_key", "")).strip_edges()
	var model := str(config.get("model", "")).strip_edges()
	if base_url.is_empty():
		return {"ok": false, "error": "Base URL 不能为空"}
	if model.is_empty():
		return {"ok": false, "error": "Model 不能为空"}
	if api_key.is_empty():
		return {"ok": false, "error": "API Key 未配置"}

	var request_body: Dictionary = {
		"model": model,
		"messages": payload.get("messages", []),
		"temperature": float(payload.get("temperature", 0.35)),
		"response_format": {"type": "json_object"}
	}
	if payload.has("max_tokens"):
		request_body["max_tokens"] = int(payload.get("max_tokens", 1200))

	var request := HTTPRequest.new()
	add_child(request)
	request.timeout = max(int(config.get("timeout_sec", 45)), 5)
	var headers := [
		"Content-Type: application/json",
		"Accept: application/json",
		"Authorization: Bearer %s" % api_key
	]
	var body := JSON.stringify(request_body)
	var err := request.request(
		"%s%s" % [base_url, CHAT_COMPLETIONS_PATH],
		headers,
		HTTPClient.METHOD_POST,
		body
	)
	if err != OK:
		request.queue_free()
		return {"ok": false, "error": "请求初始化失败: %s" % str(err)}

	var response: Array = await request.request_completed
	request.queue_free()
	var mapped := _map_http_response(response)
	if not bool(mapped.get("ok", false)):
		var status_code := int(mapped.get("status_code", 0))
		if retry_count < 1 and (status_code == 429 or status_code >= 500):
			await get_tree().create_timer(1.0).timeout
			return await _perform_chat_completion(payload, retry_count + 1)
		return mapped

	var response_data: Dictionary = mapped.get("data", {})
	var raw_content := _extract_message_content(response_data)
	var parsed_payload := extract_json_payload(raw_content)
	if not bool(parsed_payload.get("ok", false)):
		return {
			"ok": false,
			"error": str(parsed_payload.get("error", "JSON 解析失败")),
			"raw_text": raw_content,
			"status_code": int(mapped.get("status_code", 200))
		}

	return {
		"ok": true,
		"status_code": int(mapped.get("status_code", 200)),
		"raw_text": raw_content,
		"data": parsed_payload.get("data", {})
	}


func _map_http_response(response: Array) -> Dictionary:
	if response.size() < 4:
		return {"ok": false, "error": "响应格式错误"}
	var result_code := int(response[0])
	var response_code := int(response[1])
	var raw_bytes: PackedByteArray = response[3]
	var raw_text := raw_bytes.get_string_from_utf8()
	if result_code != HTTPRequest.RESULT_SUCCESS:
		return {
			"ok": false,
			"status_code": response_code,
			"raw_text": raw_text,
			"error": "网络请求失败: %s" % str(result_code)
		}
	if response_code < 200 or response_code >= 300:
		return {
			"ok": false,
			"status_code": response_code,
			"raw_text": raw_text,
			"error": map_http_error(response_code, raw_text)
		}
	var parsed := JSON.parse_string(raw_text)
	if parsed == null or not (parsed is Dictionary):
		return {
			"ok": false,
			"status_code": response_code,
			"raw_text": raw_text,
			"error": "响应不是合法 JSON"
		}
	return {
		"ok": true,
		"status_code": response_code,
		"raw_text": raw_text,
		"data": parsed
	}


func _extract_message_content(response_data: Dictionary) -> String:
	var choices: Array = response_data.get("choices", [])
	if choices.is_empty():
		return ""
	var first_choice: Dictionary = choices[0]
	var message: Dictionary = first_choice.get("message", {})
	var content := message.get("content", "")
	if content is String:
		return content
	if content is Array:
		var parts: Array[String] = []
		for part in content:
			if part is Dictionary:
				var text := str((part as Dictionary).get("text", "")).strip_edges()
				if not text.is_empty():
					parts.append(text)
		return "\n".join(parts)
	return str(content)

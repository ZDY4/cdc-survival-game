import http from "node:http";
import fs from "node:fs";
import process from "node:process";

const DEFAULT_PORT = 18765;
const portIndex = process.argv.indexOf("--port");
const port =
  portIndex >= 0 && process.argv[portIndex + 1]
    ? Number.parseInt(process.argv[portIndex + 1], 10)
    : DEFAULT_PORT;

const MODEL_ID = "narrative-lab-stub";
const LOG_PATH = process.env.CDC_NARRATIVE_STUB_LOG ?? "";

function readRequestBody(request) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    request.on("data", (chunk) => chunks.push(chunk));
    request.on("end", () => resolve(Buffer.concat(chunks).toString("utf8")));
    request.on("error", reject);
  });
}

function sendJson(response, statusCode, payload) {
  response.writeHead(statusCode, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
  });
  response.end(JSON.stringify(payload));
}

function sendStreamingInvalidJson(response) {
  response.writeHead(200, {
    "Content-Type": "text/event-stream; charset=utf-8",
    "Cache-Control": "no-store",
    Connection: "keep-alive",
  });
  response.write("data: {invalid-json}\n\n");
  response.write("data: [DONE]\n\n");
  response.end();
}

function sendStreamingDelayed(response, content, delayMs = 6000) {
  response.writeHead(200, {
    "Content-Type": "text/event-stream; charset=utf-8",
    "Cache-Control": "no-store",
    Connection: "keep-alive",
  });
  const parts = splitContent(content, 3);
  let index = 0;
  const timer = setInterval(() => {
    if (index >= parts.length) {
      clearInterval(timer);
      response.write("data: [DONE]\n\n");
      response.end();
      return;
    }

    response.write(
      `data: ${JSON.stringify({
        choices: [{ delta: { content: parts[index] } }],
      })}\n\n`,
    );
    index += 1;
  }, delayMs);

  response.on("close", () => {
    clearInterval(timer);
  });
}

function splitContent(content, segments) {
  const size = Math.max(1, Math.ceil(content.length / segments));
  const chunks = [];
  for (let index = 0; index < content.length; index += size) {
    chunks.push(content.slice(index, index + size));
  }
  return chunks;
}

function parsePromptPayload(rawBody) {
  const body = JSON.parse(rawBody || "{}");
  const content = body.messages?.at(-1)?.content ?? "{}";
  let parsed;
  try {
    parsed = JSON.parse(content);
  } catch {
    parsed = {};
  }

  const request = parsed.request ?? {};
  const prompt =
    parsed.submittedPrompt ??
    request.userPrompt ??
    request.submittedPrompt ??
    "";

  return {
    body,
    parsed,
    request,
    prompt,
    currentMarkdown: request.currentMarkdown ?? "",
  };
}

function openAiContent(payload) {
  return {
    id: "chatcmpl-narrative-stub",
    object: "chat.completion",
    created: Math.floor(Date.now() / 1000),
    model: MODEL_ID,
    choices: [
      {
        index: 0,
        message: {
          role: "assistant",
          content: JSON.stringify(payload),
        },
        finish_reason: "stop",
      },
    ],
  };
}

function appendStubLog(entry) {
  if (!LOG_PATH) {
    return;
  }

  fs.appendFileSync(LOG_PATH, `${JSON.stringify(entry)}\n`, "utf8");
}

function scenarioIdFromPrompt(prompt) {
  const rawPrompt = String(prompt);
  const explicitNeed = rawPrompt.includes("本轮需求：")
    ? rawPrompt.slice(rawPrompt.lastIndexOf("本轮需求：") + "本轮需求：".length)
    : rawPrompt;
  const normalized = explicitNeed.toLowerCase().trim();
  if (normalized.includes("还缺哪些必要信息")) {
    return "clarification-missing-brief";
  }
  if (normalized.includes("三个截然不同的推进方向")) {
    return "options-branching";
  }
  if (normalized.includes("分步骤执行计划")) {
    return "plan-complex-task";
  }
  if (normalized.includes("重写‘污染机制’小节")) {
    return "direct-revise-section";
  }
  if (normalized.includes("商人老王") && normalized.includes("单独创建")) {
    return "split-out-character-doc";
  }
  if (normalized.includes("废弃医院") && normalized.includes("地点设定文档")) {
    return "derive-location-note";
  }
  if (normalized.includes("先列出你建议执行的编辑动作")) {
    return "preview-actions-only";
  }
  if (normalized.includes("用于策划评审的补充说明")) {
    return "markdown-rich-render";
  }
  if (normalized.includes("结合陈医生角色卡")) {
    return "context-aware-revision";
  }
  if (normalized.includes("429 回归场景")) {
    return "provider-error-429";
  }
  if (normalized.includes("stream fallback 回归场景")) {
    return "stream-fallback";
  }
  if (normalized.includes("cancel inflight 回归场景")) {
    return "cancel-inflight";
  }
  return "default";
}

function replacePollutionSection(currentMarkdown) {
  return currentMarkdown.replace(
    /## 污染机制[\s\S]*?(?=\n## )/,
    [
      "## 污染机制",
      "",
      "相移污染更接近“现实错位”，而不是传统感染。受影响对象会先在认知上出现不协调，再逐步在结构上产生偏移。",
      "",
      "1. 物理层错乱：设备和门禁按错误顺序运作。",
      "2. 物质层扭结：血肉、建材和机械残件发生局部拼接。",
      "3. 意识层侵蚀：受影响者开始怀疑记忆、尺寸和静物是否可信。",
      "",
      "> 轻度污染最危险的地方，在于它看起来像疲劳和误判。",
      "",
    ].join("\n"),
  );
}

function removeTraderSection(currentMarkdown) {
  return currentMarkdown.replace(
    /### 商人老王[\s\S]*?(?=\n## )/,
    [
      "### 商人老王",
      "",
      "老王仍是据点交易秩序的关键角色，但涉及旧砖与守阈暗线的细节已拆到独立人物文稿中，以便后续单独扩写。",
      "",
    ].join("\n"),
  );
}

function appendMarkdownReview(currentMarkdown) {
  return [
    currentMarkdown.trimEnd(),
    "",
    "## 策划评审补充说明",
    "",
    "> 这一段用于验证 NarrativeLab 聊天区和文稿预览区都能稳定显示 Markdown 富文本。",
    "",
    "- 需要保留世界观的压迫感",
    "- 需要突出陈医生与医院线索的调查价值",
    "- 需要让玩家一眼理解据点为何仍能维持秩序",
    "",
    "| 评审维度 | 目标 |",
    "| --- | --- |",
    "| 叙事密度 | 每个地点至少有一个强线索锚点 |",
    "| 可拆分性 | 文稿应能继续拆成角色、地点和任务资料 |",
  ].join("\n");
}

function appendDoctorContext(currentMarkdown) {
  return currentMarkdown.replace(
    /### 陈医生[\s\S]*?(?=\n### 商人老王)/,
    [
      "### 陈医生",
      "",
      "原华西医院内科医生。爆发初期，他接诊过第一批“身体指标正常、语言逻辑完全断裂”的患者，因此知道污染并非单纯传染病。他现在负责据点医疗区，同时对外隐藏了部分早期病历内容。",
      "",
      "他之所以掌握首批污染线索，是因为最早那批病历恰好由他值班接手。病人没有器质性损伤，却反复描述墙体内部存在注视者，这让他比任何人都更早意识到异常来自认知层面的现实错位，而不是常规病原体。",
      "",
    ].join("\n"),
  );
}

function buildDerivedCharacterMarkdown() {
  return [
    "# 商人老王人物设定",
    "",
    "## 角色定位",
    "据点交易秩序的维持者，也是守阈暗线最不起眼的保管人。",
    "",
    "## 公开形象",
    "老练、谨慎、只相信能看见和能交换的东西。",
    "",
    "## 隐藏信息",
    "他保留的一块旧砖能延缓储物区污染扩散，但他并不知道那是守阈遗留物。",
  ].join("\n");
}

function buildDerivedLocationMarkdown() {
  return [
    "# 废弃医院扩展地点设定",
    "",
    "## 地点背景",
    "这里是陈医生最不愿重提的地方，因为最早期的异常病例让他第一次确认现实正在失去稳定边界。",
    "",
    "## 区域功能",
    "作为调查污染真相的关键节点，为玩家提供病历、值班表和封锁失败痕迹。",
    "",
    "## 驻留关系",
    "陈医生与这里存在强情绪连接，相关剧情应优先回收他掌握的首批线索。",
  ].join("\n");
}

function generationPayloadForScenario(scenarioId, currentMarkdown) {
  switch (scenarioId) {
    case "clarification-missing-brief":
      return {
        turn_kind: "clarification",
        assistant_message: "当前信息不足，我先帮你把关键缺口列出来。",
        questions: [
          {
            id: "goal",
            label: "这个新篇章主要想推动哪条主线或人物关系？",
            required: true,
          },
          {
            id: "tone",
            label: "你希望这一章更偏调查、冲突还是情绪修复？",
            required: true,
          },
        ],
        summary: "需要先补充核心目标与情绪方向。",
      };
    case "options-branching":
      return {
        turn_kind: "options",
        assistant_message: "我整理了三个推进方向，先选一个再继续最稳。",
        options: [
          {
            id: "hospital",
            label: "从医院调查切入",
            description: "强化陈医生与早期病例线索，适合偏调查推进。",
            followup_prompt: "请沿着废弃医院与陈医生线索继续扩写当前文稿。",
          },
          {
            id: "outpost",
            label: "从据点秩序切入",
            description: "围绕据点边界、交易秩序和旧砖秘密展开。",
            followup_prompt: "请沿着幸存者据点秩序与旧砖秘密继续扩写当前文稿。",
          },
          {
            id: "engineering",
            label: "从地下工程切入",
            description: "把深地工程、守阈人和污染源头放到前台。",
            followup_prompt: "请沿着深地工程、守阈人和污染源继续扩写当前文稿。",
          },
        ],
        summary: "已提供 3 个可继续推进的方向。",
      };
    case "plan-complex-task":
      return {
        turn_kind: "plan",
        assistant_message: "这类任务适合先拆计划，再逐步写入文稿。",
        plan_steps: [
          { id: "step-1", label: "定位主线目标与本轮范围", status: "completed" },
          { id: "step-2", label: "拆分角色、地点与关键冲突", status: "pending" },
          { id: "step-3", label: "确认需要独立派生的文稿", status: "pending" },
        ],
        summary: "已整理出三步计划。",
      };
    case "direct-revise-section":
      return {
        turn_kind: "final_answer",
        assistant_message: "我已经把污染机制小节压缩成更适合游戏内引用的版本。",
        draft_markdown: replacePollutionSection(currentMarkdown),
        summary: "已重写污染机制小节。",
      };
    case "split-out-character-doc":
      return {
        turn_kind: "final_answer",
        assistant_message: "我已将主文稿中的老王暗线压缩，并准备了一份独立人物设定。",
        draft_markdown: removeTraderSection(currentMarkdown),
        requested_actions: [
          {
            id: "create-trader-doc",
            action_type: "create_derived_document",
            title: "创建商人老王人物设定",
            description: "把老王的旧砖秘密与交易秩序职责拆到单独人物卡中。",
            payload: {
              docType: "character_card",
              title: "商人老王人物设定",
              slug: "trader-lao-wang-split",
              markdown: buildDerivedCharacterMarkdown(),
            },
            risk_level: "low",
          },
        ],
        summary: "已生成主文稿修订版，并附带独立人物文档动作。",
      };
    case "derive-location-note":
      return {
        turn_kind: "final_answer",
        assistant_message: "我准备了一份可单独创建的废弃医院扩展地点文档。",
        draft_markdown: currentMarkdown,
        requested_actions: [
          {
            id: "create-hospital-doc",
            action_type: "create_derived_document",
            title: "创建废弃医院扩展地点设定",
            description: "基于当前世界观和陈医生线索，生成独立地点文档。",
            payload: {
              docType: "location_note",
              title: "废弃医院扩展地点设定",
              slug: "abandoned-hospital-ai-note",
              markdown: buildDerivedLocationMarkdown(),
            },
            risk_level: "low",
          },
        ],
        summary: "已准备地点文档创建动作。",
      };
    case "preview-actions-only":
      return {
        turn_kind: "final_answer",
        assistant_message: "我先把建议动作列出来，仍然等待你批准。",
        draft_markdown: currentMarkdown,
        requested_actions: [
          {
            id: "preview-save",
            action_type: "save_active_document",
            title: "预览保存当前文稿",
            description: "用于验证待批准动作和 preview only 标签。",
            preview_only: true,
            risk_level: "low",
          },
        ],
        summary: "已生成预览动作。",
      };
    case "markdown-rich-render":
      return {
        turn_kind: "final_answer",
        assistant_message: "我已追加一段富文本策划评审说明。",
        draft_markdown: appendMarkdownReview(currentMarkdown),
        summary: "已追加引用、清单和表格。",
      };
    case "context-aware-revision":
      return {
        turn_kind: "final_answer",
        assistant_message: "我已把陈医生掌握首批线索的原因补进主文稿。",
        draft_markdown: appendDoctorContext(currentMarkdown),
        summary: "已补充陈医生的线索来源。",
      };
    case "stream-fallback":
      return {
        turn_kind: "final_answer",
        assistant_message: "流式失败后，已通过非流式回退拿到最终结果。",
        draft_markdown: `${currentMarkdown.trimEnd()}\n\n## 回退测试备注\n本段用于验证 stream fallback 成功收敛。\n`,
        summary: "stream fallback 已成功回退。",
      };
    default:
      return {
        turn_kind: "final_answer",
        assistant_message: "stub default response",
        draft_markdown: currentMarkdown,
        summary: "default",
      };
  }
}

function resolveActionIntent(prompt) {
  const scenarioId = scenarioIdFromPrompt(prompt);
  if (scenarioId === "split-out-character-doc") {
    return {
      action: "revise_document",
      assistant_message: "这轮需要先修改当前文档，并附带拆出的角色文档动作。",
      questions: [],
      options: [],
    };
  }

  return {
    action: "revise_document",
    assistant_message: "继续在当前文档流程内处理。",
    questions: [],
    options: [],
  };
}

const server = http.createServer(async (request, response) => {
  if (!request.url) {
    sendJson(response, 404, { error: { message: "Not found" } });
    return;
  }

  if (request.method === "GET" && request.url === "/v1/models") {
    sendJson(response, 200, {
      object: "list",
      data: [{ id: MODEL_ID, object: "model", created: 0, owned_by: "local" }],
    });
    return;
  }

  if (request.method === "POST" && request.url === "/v1/chat/completions") {
    const rawBody = await readRequestBody(request);
    const { body, parsed, prompt, currentMarkdown } = parsePromptPayload(rawBody);
    const scenarioId = scenarioIdFromPrompt(prompt);
    const isActionIntent = typeof parsed.submittedPrompt === "string";
    appendStubLog({
      timestamp: new Date().toISOString(),
      kind: isActionIntent ? "action-intent" : "generation",
      scenarioId,
      prompt,
    });

    if (!isActionIntent && scenarioId === "provider-error-429") {
      sendJson(response, 429, {
        error: {
          message: "stub rate limit for regression",
        },
      });
      return;
    }

    if (!isActionIntent && scenarioId === "stream-fallback" && body.stream) {
      sendStreamingInvalidJson(response);
      return;
    }

    if (!isActionIntent && scenarioId === "cancel-inflight") {
      const payload = {
        turn_kind: "final_answer",
        assistant_message: "这段内容本来会完成，但应当先被取消。",
        draft_markdown: `${currentMarkdown.trimEnd()}\n\n## 取消失败兜底\n如果你看见这段，说明取消逻辑没有及时生效。\n`,
        summary: "cancel inflight fallback",
      };
      sendStreamingDelayed(response, JSON.stringify(payload));
      return;
    }

    const payload = isActionIntent
      ? resolveActionIntent(prompt)
      : generationPayloadForScenario(scenarioId, currentMarkdown);

    sendJson(response, 200, openAiContent(payload));
    return;
  }

  sendJson(response, 404, { error: { message: "Not found" } });
});

server.listen(port, "127.0.0.1", () => {
  console.log(`[narrative-ai-stub] listening on http://127.0.0.1:${port}`);
});

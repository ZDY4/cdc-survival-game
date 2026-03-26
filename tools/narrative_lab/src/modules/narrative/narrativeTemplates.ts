import type { NarrativeDocType, NarrativeDocTypeEntry, NarrativeDocumentMeta } from "../../types";

export const NARRATIVE_DOC_TYPES: NarrativeDocTypeEntry[] = [
  { value: "project_brief", label: "项目总纲", directory: "project" },
  { value: "world_bible", label: "世界观手册", directory: "world" },
  { value: "faction_note", label: "势力设定", directory: "world" },
  { value: "character_card", label: "人物设定", directory: "characters" },
  { value: "arc_outline", label: "剧情弧大纲", directory: "arcs" },
  { value: "chapter_outline", label: "章节大纲", directory: "chapters" },
  { value: "branch_sheet", label: "分支设计", directory: "branches" },
  { value: "scene_draft", label: "场景稿", directory: "scenes" },
  { value: "dialogue_tone_sheet", label: "对白语气设定", directory: "scenes" },
];

export function docTypeLabel(docType: NarrativeDocType): string {
  return NARRATIVE_DOC_TYPES.find((entry) => entry.value === docType)?.label ?? docType;
}

export function docTypeDirectory(docType: NarrativeDocType): string {
  return NARRATIVE_DOC_TYPES.find((entry) => entry.value === docType)?.directory ?? "misc";
}

export function defaultNarrativeTitle(docType: NarrativeDocType): string {
  return `${docTypeLabel(docType)}草稿`;
}

export function defaultNarrativeMarkdown(docType: NarrativeDocType, title = defaultNarrativeTitle(docType)): string {
  const heading = `# ${title}`;
  const sections: Record<NarrativeDocType, string[]> = {
    project_brief: [
      "## 项目定位\n一句话说明这是怎样的末日叙事体验。",
      "## 核心主题\n明确主题、情绪、价值冲突与最终想抵达的表达。",
      "## 故事总体走向\n概括主线推进、转折和结局方向。",
      "## 关键人物与关系\n列出核心人物、诉求与关系张力。",
      "## 结构化落地提示\n可拆为主线任务、关键对话、章节推进条件、结局状态。",
    ],
    world_bible: [
      "## 世界状态\n描述灾变后的世界现状、秩序、资源与危险。",
      "## 关键规则\n记录会影响叙事和玩法的世界规则。",
      "## 典型地点\n列出主要区域、氛围、可探索内容和故事功能。",
      "## 结构化落地提示\n可拆为地点资料、背景线索、区域任务池、环境对白。",
    ],
    faction_note: [
      "## 势力概述\n介绍势力定位、口号、外部形象。",
      "## 内部目标\n说明势力真正想要什么。",
      "## 与主角的关系\n描述初始关系与可变化的信任路径。",
      "## 结构化落地提示\n可拆为阵营关系、任务发布者、敌对条件、特殊奖励。",
    ],
    character_card: [
      "## 角色定位\n一句话说明这个角色在故事中的作用。",
      "## 公开形象\n玩家最先看到的外在表现。",
      "## 隐藏信息\n这个角色不会轻易说出的秘密、伤口或立场。",
      "## 动机与欲望\n这个角色最在意什么，失去什么会崩。",
      "## 结构化落地提示\n可拆为角色数据、对白语气、好感条件、个人任务、事件触发。",
    ],
    arc_outline: [
      "## 剧情弧目标\n说明这条弧线负责推进什么主题或人物变化。",
      "## 起点状态\n故事开始时的局面。",
      "## 关键转折\n按顺序列出转折点、冲突升级和抉择。",
      "## 结构化落地提示\n可拆为章节任务链、分支节点、状态判定与收束结局。",
    ],
    chapter_outline: [
      "## 章节目标\n这一章要解决什么问题。",
      "## 前情承接\n承接哪些旧信息或旧选择。",
      "## 关键事件\n按顺序列出事件推进。",
      "## 分支点\n列出本章核心选择与结果差异。",
      "## 结构化落地提示\n可拆为章节任务、关键对话、分支条件、回收钩子。",
    ],
    branch_sheet: [
      "## 分支前提\n玩家做出选择前需要满足或知道什么。",
      "## 选择点\n明确玩家看到的几个选择。",
      "## 即时结果\n说明各选择的立刻反馈。",
      "## 长期回收\n说明哪些后果会在更晚阶段结算。",
      "## 结构化落地提示\n可拆为条件表达式、状态变量、任务分流、对白差异。",
    ],
    scene_draft: [
      "## 场景目标\n这一场景必须达成什么叙事目的。",
      "## 参与者\n列出出场角色、立场和初始气氛。",
      "## 场景推进\n按阶段描述冲突、动作、对白重点。",
      "## 后续钩子\n离开场景后留下什么问题或动力。",
      "## 结构化落地提示\n可拆为对白树、场景事件、交互对象、任务步骤推进。",
    ],
    dialogue_tone_sheet: [
      "## 角色语气\n描述角色说话方式、节奏、常用词。",
      "## 情绪变化\n角色在不同状态下的语气切换。",
      "## 禁区与敏感点\n哪些话题会触发防御或爆发。",
      "## 示例台词\n写几组可直接参考的短对白。",
      "## 结构化落地提示\n可拆为对白节点文风、分支语气条件、关系值反馈。",
    ],
  };

  return [heading, ...sections[docType]].join("\n\n");
}

export function fallbackNarrativeMeta(docType: NarrativeDocType, slug: string): NarrativeDocumentMeta {
  return {
    docType,
    slug,
    title: defaultNarrativeTitle(docType),
    status: "draft",
    tags: [],
    relatedDocs: [],
    sourceRefs: [],
  };
}

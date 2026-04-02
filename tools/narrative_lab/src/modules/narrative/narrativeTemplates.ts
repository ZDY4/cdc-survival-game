import type { NarrativeDocType, NarrativeDocTypeEntry, NarrativeDocumentMeta } from "../../types";

export const NARRATIVE_DOC_TYPES: NarrativeDocTypeEntry[] = [
  { value: "world_bible", label: "世界观手册", directory: "world" },
  { value: "task_setup", label: "任务设定", directory: "tasks" },
  { value: "location_note", label: "地点设定", directory: "locations" },
  { value: "character_card", label: "人物设定", directory: "characters" },
  { value: "monster_note", label: "怪物设定", directory: "monsters" },
  { value: "item_note", label: "物品设定", directory: "items" },
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

export function docTypeSummary(docType: NarrativeDocType): string {
  const summaries: Record<NarrativeDocType, string> = {
    world_bible: "沉淀世界状态、关键规则、典型地点与长期冲突背景。",
    task_setup: "梳理任务目标、推进阶段、关键选择与回收条件。",
    location_note: "沉淀地点背景、区域功能、危险与可探索内容。",
    character_card: "沉淀角色动机、秘密、关系与任务挂钩。",
    monster_note: "定义怪物谱系、生态、威胁来源与传闻印象。",
    item_note: "记录物品背景、用途语境、稀缺性与象征意义。",
  };

  return summaries[docType];
}

export function defaultNarrativeMarkdown(docType: NarrativeDocType, title = defaultNarrativeTitle(docType)): string {
  const heading = `# ${title}`;
  const sections: Record<NarrativeDocType, string[]> = {
    world_bible: [
      "## 世界状态\n描述灾变后的世界现状、秩序、资源与危险。",
      "## 关键规则\n记录会影响叙事和玩法的世界规则。",
      "## 典型地点\n列出主要区域、氛围、可探索内容和故事功能。",
      "## 典型冲突\n总结这个世界中反复出现的矛盾类型。",
      "## 结构化落地提示\n可拆为地点资料、背景线索、区域任务池、环境对白。",
    ],
    task_setup: [
      "## 任务目标\n说明玩家为什么要做这件事，以及完成后会改变什么。",
      "## 前置条件\n列出任务开启前必须满足的状态、关系、地点或物品条件。",
      "## 推进阶段\n按顺序拆解任务步骤、触发点和阶段性反馈。",
      "## 关键选择\n列出任务中的重要抉择，以及各自的即时与长期后果。",
      "## 涉及要素\n注明会关联到的人物、地点、怪物、物品与线索。",
      "## 结构化落地提示\n可拆为任务节点、对白触发、状态变量、分支条件与结局回收。",
    ],
    location_note: [
      "## 地点背景\n说明这个地点的来历、现状和它在世界中的位置。",
      "## 区域功能\n列出这个地点承担的叙事或玩法功能。",
      "## 氛围与视觉线索\n记录环境气质、声音、气味、地标与玩家第一印象。",
      "## 资源与危险\n说明这里常见的资源、风险、禁区和潜在冲突。",
      "## 驻留关系\n记录常驻人物、势力影响、传闻和关联任务。",
      "## 结构化落地提示\n可拆为地点数据、环境线索、区域对白、探索事件与地图标注。",
    ],
    character_card: [
      "## 角色定位\n一句话说明这个角色在故事中的作用。",
      "## 公开形象\n玩家最先看到的外在表现。",
      "## 隐藏信息\n这个角色不会轻易说出的秘密、伤口或立场。",
      "## 动机与欲望\n这个角色最在意什么，失去什么会崩。",
      "## 关系网络\n列出与其他角色、地点、任务的连接方式。",
      "## 成长轨迹\n说明这个角色可能的变化、崩塌点与回收方式。",
      "## 结构化落地提示\n可拆为角色资料、对白风格、关系条件、个人任务与事件触发。",
    ],
    monster_note: [
      "## 怪物概述\n说明这种怪物的来源、俗称与玩家印象。",
      "## 生态与出没环境\n描述它通常出现在哪些地点、与哪些环境共生。",
      "## 威胁特征\n总结它最危险的行为、压迫感来源和玩家应对感受。",
      "## 目击印象与传闻\n记录幸存者口中的见闻、谣言和恐惧叙述。",
      "## 相关要素\n注明会关联的人物、地点、任务或关键物品。",
      "## 结构化落地提示\n可映射为敌对角色、遭遇事件或传闻线索，但不直接代替数值定义。",
    ],
    item_note: [
      "## 物品概述\n说明这件物品在世界中的来历、俗称和核心用途。",
      "## 获取语境\n描述它通常出现在哪些地点、由谁持有、为什么稀缺或常见。",
      "## 文化与象征意义\n记录它在幸存者社会中的价值、身份意味或禁忌。",
      "## 使用体验\n说明玩家接触它时应感受到的质感、风险或机会。",
      "## 关联要素\n注明会关联的人物、地点、任务或怪物。",
      "## 结构化落地提示\n可映射为物品定义、线索或任务奖励，但不直接代替结构化物品数据。",
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

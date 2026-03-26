use serde::Serialize;

pub const DEFAULT_NARRATIVE_STATUS: &str = "draft";

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct NarrativeDocTypeEntry {
    pub value: String,
    pub label: String,
    pub directory: String,
}

const DOC_TYPES: &[(&str, &str, &str)] = &[
    ("project_brief", "项目总纲", "project"),
    ("world_bible", "世界观手册", "world"),
    ("faction_note", "势力设定", "world"),
    ("character_card", "人物设定", "characters"),
    ("arc_outline", "剧情弧大纲", "arcs"),
    ("chapter_outline", "章节大纲", "chapters"),
    ("branch_sheet", "分支设计", "branches"),
    ("scene_draft", "场景稿", "scenes"),
    ("dialogue_tone_sheet", "对白语气设定", "scenes"),
];

pub fn narrative_doc_type_entries() -> Vec<NarrativeDocTypeEntry> {
    DOC_TYPES
        .iter()
        .map(|(value, label, directory)| NarrativeDocTypeEntry {
            value: (*value).to_string(),
            label: (*label).to_string(),
            directory: (*directory).to_string(),
        })
        .collect()
}

pub fn is_known_doc_type(doc_type: &str) -> bool {
    DOC_TYPES.iter().any(|(value, _, _)| *value == doc_type)
}

pub fn doc_type_directory(doc_type: &str) -> &'static str {
    DOC_TYPES
        .iter()
        .find(|(value, _, _)| *value == doc_type)
        .map(|(_, _, directory)| *directory)
        .unwrap_or("misc")
}

pub fn doc_type_label(doc_type: &str) -> &'static str {
    DOC_TYPES
        .iter()
        .find(|(value, _, _)| *value == doc_type)
        .map(|(_, label, _)| *label)
        .unwrap_or("叙事文稿")
}

pub fn default_title(doc_type: &str) -> String {
    format!("{}草稿", doc_type_label(doc_type))
}

pub fn default_markdown(doc_type: &str, title: &str) -> String {
    let normalized_title = if title.trim().is_empty() {
        default_title(doc_type)
    } else {
        title.trim().to_string()
    };

    let sections = match doc_type {
        "project_brief" => vec![
            ("项目定位", "一句话说明这是怎样的末日叙事体验。"),
            ("核心主题", "明确主题、情绪、价值冲突与最终想抵达的表达。"),
            ("玩家体验目标", "玩家应该在这段内容里感受到什么。"),
            ("故事总体走向", "概括主线推进、转折和结局方向。"),
            ("关键人物与关系", "列出核心人物、诉求与关系张力。"),
            ("结构化落地提示", "可拆为主线任务、关键对话、章节推进条件、结局状态。"),
        ],
        "world_bible" => vec![
            ("世界状态", "描述灾变后的世界现状、秩序、资源与危险。"),
            ("关键规则", "记录会影响叙事和玩法的世界规则。"),
            ("典型地点", "列出主要区域、氛围、可探索内容和故事功能。"),
            ("典型冲突", "总结这个世界中反复出现的矛盾类型。"),
            ("结构化落地提示", "可拆为地点资料、背景线索、区域任务池、环境对白。"),
        ],
        "faction_note" => vec![
            ("势力概述", "介绍势力定位、口号、外部形象。"),
            ("内部目标", "说明势力真正想要什么。"),
            ("资源与手段", "说明他们拥有什么、如何行动。"),
            ("与主角的关系", "描述初始关系与可变化的信任路径。"),
            ("结构化落地提示", "可拆为阵营关系、任务发布者、敌对条件、特殊奖励。"),
        ],
        "character_card" => vec![
            ("角色定位", "一句话说明这个角色在故事中的作用。"),
            ("公开形象", "玩家最先看到的外在表现。"),
            ("隐藏信息", "这个角色不会轻易说出的秘密、伤口或立场。"),
            ("动机与欲望", "这个角色最在意什么，失去什么会崩。"),
            ("关系网络", "列出与其他角色的关系和张力来源。"),
            ("成长轨迹", "这个角色可能如何变化。"),
            ("结构化落地提示", "可拆为角色数据、对白语气、好感条件、个人任务、事件触发。"),
        ],
        "arc_outline" => vec![
            ("剧情弧目标", "说明这条弧线负责推进什么主题或人物变化。"),
            ("起点状态", "故事开始时的局面。"),
            ("关键转折", "按顺序列出转折点、冲突升级和抉择。"),
            ("高潮与回收", "说明高潮事件和前文伏笔如何回收。"),
            ("结构化落地提示", "可拆为章节任务链、分支节点、状态判定与收束结局。"),
        ],
        "chapter_outline" => vec![
            ("章节目标", "这一章要解决什么问题。"),
            ("前情承接", "承接哪些旧信息或旧选择。"),
            ("关键事件", "按顺序列出事件推进。"),
            ("分支点", "列出本章核心选择与结果差异。"),
            ("角色推进", "说明人物关系与心理变化。"),
            ("结构化落地提示", "可拆为章节任务、关键对话、分支条件、回收钩子。"),
        ],
        "branch_sheet" => vec![
            ("分支前提", "玩家做出选择前需要满足或知道什么。"),
            ("选择点", "明确玩家看到的几个选择。"),
            ("即时结果", "说明各选择的立刻反馈。"),
            ("中期影响", "说明各选择对后续章节的影响。"),
            ("长期回收", "说明哪些后果会在更晚阶段结算。"),
            ("结构化落地提示", "可拆为条件表达式、状态变量、任务分流、对白差异。"),
        ],
        "scene_draft" => vec![
            ("场景目标", "这一场景必须达成什么叙事目的。"),
            ("参与者", "列出出场角色、立场和初始气氛。"),
            ("场景推进", "按阶段描述冲突、动作、对白重点。"),
            ("可交互点", "玩家能介入或观察的地方。"),
            ("后续钩子", "离开场景后留下什么问题或动力。"),
            ("结构化落地提示", "可拆为对白树、场景事件、交互对象、任务步骤推进。"),
        ],
        "dialogue_tone_sheet" => vec![
            ("角色语气", "描述角色说话方式、节奏、常用词。"),
            ("情绪变化", "角色在不同状态下的语气切换。"),
            ("禁区与敏感点", "哪些话题会触发防御或爆发。"),
            ("示例台词", "写几组可直接参考的短对白。"),
            ("结构化落地提示", "可拆为对白节点文风、分支语气条件、关系值反馈。"),
        ],
        _ => vec![
            ("内容目标", "说明这份文稿打算回答什么问题。"),
            ("关键内容", "写下本次生成需要确认的信息。"),
            ("结构化落地提示", "说明后续可拆成哪些游戏数据。"),
        ],
    };

    let mut output = format!("# {normalized_title}\n\n");
    for (heading, hint) in sections {
        output.push_str(&format!("## {heading}\n{hint}\n\n"));
    }
    output.trim_end().to_string()
}

pub fn slugify(input: &str) -> String {
    let mut slug = String::new();
    let mut last_dash = false;
    for character in input.chars() {
        let normalized = character.to_ascii_lowercase();
        if normalized.is_ascii_alphanumeric() {
            slug.push(normalized);
            last_dash = false;
        } else if (character == '_' || character == '-' || character.is_ascii_whitespace()) && !last_dash {
            slug.push('-');
            last_dash = true;
        }
    }
    slug.trim_matches('-').to_string()
}

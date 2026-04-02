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
    ("world_bible", "世界观手册", "world"),
    ("task_setup", "任务设定", "tasks"),
    ("location_note", "地点设定", "locations"),
    ("character_card", "人物设定", "characters"),
    ("monster_note", "怪物设定", "monsters"),
    ("item_note", "物品设定", "items"),
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
        "world_bible" => vec![
            ("世界状态", "描述灾变后的世界现状、秩序、资源与危险。"),
            ("关键规则", "记录会影响叙事和玩法的世界规则。"),
            ("典型地点", "列出主要区域、氛围、可探索内容和故事功能。"),
            ("典型冲突", "总结这个世界中反复出现的矛盾类型。"),
            ("结构化落地提示", "可拆为地点资料、背景线索、区域任务池、环境对白。"),
        ],
        "task_setup" => vec![
            ("任务目标", "说明玩家为什么要做这件事，以及完成后会改变什么。"),
            (
                "前置条件",
                "列出任务开启前必须满足的状态、关系、地点或物品条件。",
            ),
            ("推进阶段", "按顺序拆解任务步骤、触发点和阶段性反馈。"),
            (
                "关键选择",
                "列出任务中的重要抉择，以及各自的即时与长期后果。",
            ),
            (
                "涉及要素",
                "注明会关联到的人物、地点、怪物、物品与线索。",
            ),
            (
                "结构化落地提示",
                "可拆为任务节点、对白触发、状态变量、分支条件与结局回收。",
            ),
        ],
        "location_note" => vec![
            ("地点背景", "说明这个地点的来历、现状和它在世界中的位置。"),
            ("区域功能", "列出这个地点承担的叙事或玩法功能。"),
            (
                "氛围与视觉线索",
                "记录环境气质、声音、气味、地标与玩家第一印象。",
            ),
            ("资源与危险", "说明这里常见的资源、风险、禁区和潜在冲突。"),
            ("驻留关系", "记录常驻人物、势力影响、传闻和关联任务。"),
            (
                "结构化落地提示",
                "可拆为地点数据、环境线索、区域对白、探索事件与地图标注。",
            ),
        ],
        "character_card" => vec![
            ("角色定位", "一句话说明这个角色在故事中的作用。"),
            ("公开形象", "玩家最先看到的外在表现。"),
            ("隐藏信息", "这个角色不会轻易说出的秘密、伤口或立场。"),
            ("动机与欲望", "这个角色最在意什么，失去什么会崩。"),
            ("关系网络", "列出与其他角色、地点、任务的连接方式。"),
            ("成长轨迹", "说明这个角色可能的变化、崩塌点与回收方式。"),
            (
                "结构化落地提示",
                "可拆为角色资料、对白风格、关系条件、个人任务与事件触发。",
            ),
        ],
        "monster_note" => vec![
            ("怪物概述", "说明这种怪物的来源、俗称与玩家印象。"),
            (
                "生态与出没环境",
                "描述它通常出现在哪些地点、与哪些环境共生。",
            ),
            (
                "威胁特征",
                "总结它最危险的行为、压迫感来源和玩家应对感受。",
            ),
            (
                "目击印象与传闻",
                "记录幸存者口中的见闻、谣言和恐惧叙述。",
            ),
            ("相关要素", "注明会关联的人物、地点、任务或关键物品。"),
            (
                "结构化落地提示",
                "可映射为敌对角色、遭遇事件或传闻线索，但不直接代替数值定义。",
            ),
        ],
        "item_note" => vec![
            ("物品概述", "说明这件物品在世界中的来历、俗称和核心用途。"),
            (
                "获取语境",
                "描述它通常出现在哪些地点、由谁持有、为什么稀缺或常见。",
            ),
            (
                "文化与象征意义",
                "记录它在幸存者社会中的价值、身份意味或禁忌。",
            ),
            ("使用体验", "说明玩家接触它时应感受到的质感、风险或机会。"),
            ("关联要素", "注明会关联的人物、地点、任务或怪物。"),
            (
                "结构化落地提示",
                "可映射为物品定义、线索或任务奖励，但不直接代替结构化物品数据。",
            ),
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
        } else if (character == '_' || character == '-' || character.is_ascii_whitespace())
            && !last_dash
        {
            slug.push('-');
            last_dash = true;
        }
    }
    slug.trim_matches('-').to_string()
}

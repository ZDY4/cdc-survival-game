//! 编辑器状态定义。
//! 集中放置资源、UI 状态、预览状态以及少量通用标签/格式化辅助函数。

use std::collections::BTreeMap;
use std::path::PathBuf;

use bevy::prelude::*;
use game_data::{
    AiModuleLibrary, CharacterAiPreview, CharacterAiPreviewContext, CharacterAppearanceLibrary,
    CharacterArchetype, CharacterDefinition, CharacterDisposition, CharacterLibrary, ItemLibrary,
    NpcRole, ResolvedCharacterAppearancePreview, ScheduleDay, SettlementLibrary,
};

/// 编辑器运行期持有的只读内容数据和校验结果。
#[derive(Resource)]
pub(crate) struct EditorData {
    pub(crate) repo_root: PathBuf,
    pub(crate) characters: CharacterLibrary,
    pub(crate) items: ItemLibrary,
    pub(crate) settlements: SettlementLibrary,
    pub(crate) ai_library: Option<AiModuleLibrary>,
    pub(crate) appearance_library: CharacterAppearanceLibrary,
    pub(crate) character_summaries: Vec<CharacterSummary>,
    pub(crate) item_catalog_by_slot: BTreeMap<String, Vec<ItemChoice>>,
    pub(crate) warnings: Vec<String>,
    pub(crate) ai_issues: Vec<EditorAiIssue>,
}

/// 左侧角色列表使用的轻量摘要结构。
#[derive(Debug, Clone)]
pub(crate) struct CharacterSummary {
    pub(crate) id: String,
    pub(crate) display_name: String,
    pub(crate) settlement_id: String,
    pub(crate) role: String,
    pub(crate) behavior_profile_id: String,
}

/// 外观试装下拉中使用的物品选项。
#[derive(Debug, Clone)]
pub(crate) struct ItemChoice {
    pub(crate) id: u32,
    pub(crate) name: String,
}

/// 结构化 AI 校验结果，供顶部诊断和当前角色过滤视图使用。
#[derive(Debug, Clone)]
pub(crate) struct EditorAiIssue {
    pub(crate) severity: String,
    pub(crate) code: String,
    pub(crate) settlement_id: Option<String>,
    pub(crate) character_id: Option<String>,
    pub(crate) message: String,
}

/// 右侧详情区的页签枚举。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum CharacterTab {
    Summary,
    Life,
    AiPreview,
    Appearance,
}

/// UI 层的交互状态，包括搜索、选中角色和预览输入上下文。
#[derive(Resource)]
pub(crate) struct EditorUiState {
    pub(crate) search_text: String,
    pub(crate) selected_character_id: Option<String>,
    pub(crate) selected_tab: CharacterTab,
    pub(crate) try_on: BTreeMap<String, u32>,
    pub(crate) preview_context: CharacterAiPreviewContext,
    pub(crate) status: String,
}

#[derive(Resource, Debug, Clone, Default)]
pub(crate) struct InitialCharacterSelection(pub(crate) Option<String>);

#[derive(Resource)]
pub(crate) struct ExternalCharacterSelectionState {
    pub(crate) repo_root: PathBuf,
    pub(crate) heartbeat_timer: Timer,
    pub(crate) request_poll_timer: Timer,
    pub(crate) last_request_id: Option<String>,
}

impl ExternalCharacterSelectionState {
    pub(crate) fn new(repo_root: PathBuf) -> Self {
        let mut heartbeat_timer = Timer::from_seconds(1.0, TimerMode::Repeating);
        heartbeat_timer.set_elapsed(heartbeat_timer.duration());

        let mut request_poll_timer = Timer::from_seconds(0.25, TimerMode::Repeating);
        request_poll_timer.set_elapsed(request_poll_timer.duration());

        Self {
            repo_root,
            heartbeat_timer,
            request_poll_timer,
            last_request_id: None,
        }
    }
}

impl Default for EditorUiState {
    fn default() -> Self {
        Self {
            search_text: String::new(),
            selected_character_id: None,
            selected_tab: CharacterTab::Summary,
            try_on: BTreeMap::new(),
            preview_context: default_preview_context(),
            status: "加载角色数据中…".to_string(),
        }
    }
}

#[derive(Resource, Default)]
pub(crate) struct PreviewState {
    pub(crate) revision: u64,
    pub(crate) applied_revision: u64,
    pub(crate) resolved_preview: Option<ResolvedCharacterAppearancePreview>,
    pub(crate) preview_notice: Option<String>,
    pub(crate) ai_preview: Option<CharacterAiPreview>,
    pub(crate) ai_error: Option<String>,
    pub(crate) appearance_error: Option<String>,
}

#[derive(Resource, Debug, Clone, Default)]
pub(crate) struct CharacterUiStyleState {
    pub(crate) initialized: bool,
}

/// 构造一个稳定的默认 AI 预览上下文。
pub(crate) fn default_preview_context() -> CharacterAiPreviewContext {
    CharacterAiPreviewContext {
        day: ScheduleDay::Monday,
        minute_of_day: 8 * 60,
        hunger: 20.0,
        energy: 80.0,
        morale: 65.0,
        world_alert_active: false,
        current_anchor: Some("home".to_string()),
        active_guards: 1,
        min_guard_on_duty: 1,
        availability: Default::default(),
    }
}

/// 中文化角色原型标签。
pub(crate) fn archetype_label(character: &CharacterDefinition) -> &'static str {
    match character.archetype {
        CharacterArchetype::Player => "玩家",
        CharacterArchetype::Npc => "NPC",
        CharacterArchetype::Enemy => "敌对单位",
    }
}

/// 中文化阵营关系标签。
pub(crate) fn disposition_label(character: &CharacterDefinition) -> &'static str {
    match character.faction.disposition {
        CharacterDisposition::Player => "玩家",
        CharacterDisposition::Friendly => "友善",
        CharacterDisposition::Hostile => "敌对",
        CharacterDisposition::Neutral => "中立",
    }
}

/// 中文化 NPC 职责标签。
pub(crate) fn npc_role_label(role: NpcRole) -> &'static str {
    match role {
        NpcRole::Guard => "守卫",
        NpcRole::Cook => "厨师",
        NpcRole::Doctor => "医生",
        NpcRole::Resident => "居民",
    }
}

/// 中文化星期标签。
pub(crate) fn schedule_day_label(day: ScheduleDay) -> &'static str {
    match day {
        ScheduleDay::Monday => "周一",
        ScheduleDay::Tuesday => "周二",
        ScheduleDay::Wednesday => "周三",
        ScheduleDay::Thursday => "周四",
        ScheduleDay::Friday => "周五",
        ScheduleDay::Saturday => "周六",
        ScheduleDay::Sunday => "周日",
    }
}

/// 空字符串统一显示为占位符，减少 UI 分支判断。
pub(crate) fn non_empty(value: &str) -> &str {
    if value.trim().is_empty() {
        "-"
    } else {
        value
    }
}

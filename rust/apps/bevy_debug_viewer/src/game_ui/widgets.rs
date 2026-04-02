//! UI 通用组件与格式化 helper：负责文本、按钮、详情展示结构和共享渲染辅助。

use super::*;

pub(super) fn clear_ui_children(commands: &mut Commands, children: Option<&Children>) {
    if let Some(children) = children {
        for child in children.iter() {
            commands.entity(child).despawn();
        }
    }
}

pub(super) fn ui_hierarchy_bundle() -> impl Bundle {
    (
        Visibility::Inherited,
        InheritedVisibility::VISIBLE,
        ViewVisibility::default(),
    )
}

pub(super) fn text_bundle(font: &ViewerUiFont, text: &str, size: f32, color: Color) -> impl Bundle {
    (
        Text::new(text.to_string()),
        TextFont::from_font_size(size).with_font(font.0.clone()),
        TextColor(color),
    )
}

pub(super) fn action_button(
    font: &ViewerUiFont,
    label: &str,
    action: GameUiButtonAction,
) -> impl Bundle {
    (
        Button,
        Node {
            padding: UiRect::axes(px(10), px(7)),
            margin: UiRect::bottom(px(4)),
            border: UiRect::all(px(1)),
            ..default()
        },
        BackgroundColor(interaction_menu_button_color(false, Interaction::None)),
        BorderColor::all(Color::srgba(0.19, 0.24, 0.32, 1.0)),
        action,
        Text::new(label.to_string()),
        TextFont::from_font_size(11.0).with_font(font.0.clone()),
        TextColor(Color::WHITE),
    )
}

pub(super) fn wrapped_text_bundle(
    font: &ViewerUiFont,
    text: &str,
    size: f32,
    color: Color,
) -> impl Bundle {
    (
        Text::new(text.to_string()),
        TextFont::from_font_size(size).with_font(font.0.clone()),
        TextColor(color),
        TextLayout::new(Justify::Left, LineBreak::WordBoundary),
        Node {
            width: Val::Percent(100.0),
            ..default()
        },
    )
}

#[derive(Debug, Clone)]
pub(super) struct DetailTextLine {
    text: String,
    size: f32,
    color: Color,
}

#[derive(Debug, Clone, Default)]
pub(super) struct DetailTextContent {
    lines: Vec<DetailTextLine>,
}

impl DetailTextContent {
    pub(super) fn push(&mut self, text: impl Into<String>, size: f32, color: Color) {
        self.lines.push(DetailTextLine {
            text: text.into(),
            size,
            color,
        });
    }

    pub(super) fn estimated_height(&self) -> f32 {
        self.lines.iter().map(|line| line.size + 6.0).sum::<f32>() + 26.0
    }
}

#[derive(Debug, Clone)]
pub(super) struct InventoryDetailDisplay {
    pub(super) content: DetailTextContent,
    pub(super) can_use: bool,
    pub(super) can_equip: bool,
}

#[derive(Debug, Clone)]
pub(super) struct SkillDetailDisplay {
    pub(super) content: DetailTextContent,
    pub(super) hotbar_eligible: bool,
}

pub(super) fn spawn_detail_text_content(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    content: &DetailTextContent,
) {
    for line in &content.lines {
        parent.spawn(wrapped_text_bundle(font, &line.text, line.size, line.color));
    }
}

pub(super) fn build_inventory_detail_display(
    detail: &game_bevy::UiInventoryDetailView,
    entry: Option<&game_bevy::UiInventoryEntryView>,
) -> InventoryDetailDisplay {
    let can_use = entry.map(|entry| entry.can_use).unwrap_or(false);
    let can_equip = entry.map(|entry| entry.can_equip).unwrap_or(false);
    let mut content = DetailTextContent::default();

    content.push(
        format!(
            "{} · {} x{}",
            detail.name,
            detail.item_type.as_str(),
            detail.count
        ),
        11.3,
        Color::WHITE,
    );
    content.push(
        format!("重量 {:.1}kg", detail.weight),
        10.1,
        Color::srgba(0.78, 0.84, 0.92, 1.0),
    );
    if !detail.description.trim().is_empty() {
        content.push(
            detail.description.clone(),
            10.1,
            Color::srgba(0.86, 0.89, 0.95, 1.0),
        );
    }
    if detail.attribute_bonuses.is_empty() {
        content.push("属性加成: 无", 10.0, Color::srgba(0.72, 0.76, 0.82, 1.0));
    } else {
        content.push("属性加成", 10.0, Color::srgba(0.74, 0.79, 0.88, 1.0));
        for (attribute, bonus) in &detail.attribute_bonuses {
            content.push(
                format!("{attribute} {bonus:+.1}"),
                10.0,
                Color::srgba(0.84, 0.88, 0.95, 1.0),
            );
        }
    }
    content.push(
        format!("操作: {}", inventory_capability_label(can_use, can_equip)),
        10.0,
        Color::srgba(0.74, 0.79, 0.88, 1.0),
    );

    InventoryDetailDisplay {
        content,
        can_use,
        can_equip,
    }
}

pub(super) fn inventory_capability_label(can_use: bool, can_equip: bool) -> &'static str {
    match (can_use, can_equip) {
        (true, true) => "可使用 / 可装备",
        (true, false) => "可使用",
        (false, true) => "可装备",
        (false, false) => "无可执行操作",
    }
}

pub(super) fn render_inventory_detail_content(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    display: &InventoryDetailDisplay,
    show_actions: bool,
) {
    spawn_detail_text_content(parent, font, &display.content);

    if !show_actions {
        return;
    }

    parent
        .spawn(Node {
            width: Val::Percent(100.0),
            flex_direction: FlexDirection::Row,
            flex_wrap: FlexWrap::Wrap,
            column_gap: px(8),
            row_gap: px(6),
            ..default()
        })
        .with_children(|actions| {
            if display.can_use {
                actions.spawn(action_button(
                    font,
                    "使用",
                    GameUiButtonAction::UseInventoryItem,
                ));
            }
            if display.can_equip {
                actions.spawn(action_button(
                    font,
                    "装备",
                    GameUiButtonAction::EquipInventoryItem,
                ));
            }
        });
}

pub(super) fn build_skill_detail_display(
    tree: Option<&game_bevy::UiSkillTreeView>,
    entry: &game_bevy::UiSkillEntryView,
    hotbar_state: &UiHotbarState,
) -> SkillDetailDisplay {
    let current_group_fill = hotbar_state
        .groups
        .get(hotbar_state.active_group)
        .map(|group| group.iter().filter(|slot| slot.skill_id.is_some()).count())
        .unwrap_or(0);
    let mut content = DetailTextContent::default();

    if let Some(tree) = tree {
        content.push(
            tree.tree_name.clone(),
            12.0,
            Color::srgba(0.82, 0.88, 0.96, 1.0),
        );
        if !tree.tree_description.trim().is_empty() {
            content.push(
                tree.tree_description.clone(),
                10.0,
                Color::srgba(0.70, 0.75, 0.82, 1.0),
            );
        }
    }

    content.push(entry.name.clone(), 14.0, Color::WHITE);
    content.push(
        format!(
            "等级 {}/{} · {} · 冷却 {:.1}s",
            entry.learned_level,
            entry.max_level,
            activation_mode_label(&entry.activation_mode),
            entry.cooldown_seconds
        ),
        10.8,
        Color::srgba(0.80, 0.86, 0.96, 1.0),
    );
    if !entry.description.trim().is_empty() {
        content.push(entry.description.clone(), 10.5, Color::WHITE);
    }
    content.push(
        format!("前置需求: {}", format_skill_prerequisites(entry)),
        10.0,
        Color::srgba(0.84, 0.88, 0.94, 1.0),
    );
    content.push(
        format!("属性需求: {}", format_skill_attribute_requirements(entry)),
        10.0,
        Color::srgba(0.84, 0.88, 0.94, 1.0),
    );
    content.push(
        format!(
            "当前快捷栏组 {} · 已占用 {}/10",
            hotbar_state.active_group + 1,
            current_group_fill
        ),
        10.0,
        Color::srgba(0.72, 0.78, 0.86, 1.0),
    );
    if let Some(slot_index) = current_group_skill_slot(hotbar_state, &entry.skill_id) {
        content.push(
            format!("当前组已绑定到第 {} 槽", slot_index + 1),
            10.0,
            Color::srgba(0.90, 0.80, 0.58, 1.0),
        );
    }
    content.push(
        if entry.hotbar_eligible {
            "快捷栏: 可加入当前组空槽"
        } else if entry.learned_level > 0 {
            "快捷栏: 该技能当前不进入快捷栏"
        } else {
            "快捷栏: 尚未学习，暂时不能加入快捷栏"
        },
        10.0,
        Color::srgba(0.72, 0.76, 0.82, 1.0),
    );

    SkillDetailDisplay {
        content,
        hotbar_eligible: entry.hotbar_eligible,
    }
}

pub(super) fn render_skill_detail_content(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    display: &SkillDetailDisplay,
    entry: &game_bevy::UiSkillEntryView,
    show_actions: bool,
) {
    spawn_detail_text_content(parent, font, &display.content);

    if show_actions && display.hotbar_eligible {
        parent.spawn(action_button(
            font,
            "加入当前组空槽",
            GameUiButtonAction::AssignSkillToFirstEmptyHotbarSlot(entry.skill_id.clone()),
        ));
    }
}

pub(super) fn panel_title(panel: UiMenuPanel) -> &'static str {
    match panel {
        UiMenuPanel::Inventory => "行囊",
        UiMenuPanel::Character => "角色",
        UiMenuPanel::Map => "地图",
        UiMenuPanel::Journal => "任务",
        UiMenuPanel::Skills => "技能",
        UiMenuPanel::Crafting => "制造",
        UiMenuPanel::Settings => "设置",
    }
}

pub(super) fn panel_tab_label(panel: UiMenuPanel) -> &'static str {
    match panel {
        UiMenuPanel::Inventory => "Inventory",
        UiMenuPanel::Character => "Character",
        UiMenuPanel::Map => "Map",
        UiMenuPanel::Journal => "Quest",
        UiMenuPanel::Skills => "Skills",
        UiMenuPanel::Crafting => "Crafting",
        UiMenuPanel::Settings => "Menu",
    }
}

pub(super) fn panel_width(panel: UiMenuPanel) -> f32 {
    match panel {
        UiMenuPanel::Skills => SKILLS_PANEL_WIDTH,
        _ => UI_PANEL_WIDTH,
    }
}

pub(super) fn player_hud_stats(
    runtime_state: &ViewerRuntimeState,
    actor_id: ActorId,
) -> Option<PlayerHudStats> {
    runtime_state
        .runtime
        .snapshot()
        .actors
        .into_iter()
        .find(|actor| actor.actor_id == actor_id)
        .map(|actor| PlayerHudStats {
            hp: actor.hp,
            max_hp: actor.max_hp,
            ap: actor.ap,
            available_steps: actor.available_steps,
            in_combat: actor.in_combat,
        })
}

pub(super) fn action_meter_ratio(stats: &PlayerHudStats) -> f32 {
    if stats.in_combat {
        (stats.ap / 10.0).clamp(0.0, 1.0)
    } else {
        ((stats.available_steps as f32) / 12.0).clamp(0.0, 1.0)
    }
}

pub(super) fn render_top_center_badges(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    scene_kind: ViewerSceneKind,
    viewer_state: &ViewerState,
    player_stats: Option<&PlayerHudStats>,
    menu_state: &UiMenuState,
) {
    if scene_kind.is_main_menu() {
        return;
    }
    let badges = [
        if let Some(stats) = player_stats {
            format!("HP {:.0}/{:.0}", stats.hp, stats.max_hp)
        } else {
            "HP --".to_string()
        },
        if let Some(stats) = player_stats {
            format!("行动 {:.1} / {}", stats.ap, stats.available_steps)
        } else {
            "行动 --".to_string()
        },
        format!("楼层 {}", viewer_state.current_level),
        format!("模式 {}", viewer_state.control_mode.label()),
        menu_state
            .active_panel
            .map(|panel| format!("面板 {}", panel_title(panel)))
            .unwrap_or_else(|| "探索".to_string()),
    ];
    parent
        .spawn((
            Node {
                position_type: PositionType::Absolute,
                top: px(SCREEN_EDGE_PADDING),
                left: Val::Percent(50.0),
                margin: UiRect {
                    left: px(-(TOP_BADGE_WIDTH / 2.0)),
                    ..default()
                },
                width: px(TOP_BADGE_WIDTH),
                justify_content: JustifyContent::Center,
                ..default()
            },
            FocusPolicy::Block,
            RelativeCursorPosition::default(),
            UiMouseBlocker,
            ui_hierarchy_bundle(),
        ))
        .with_children(|wrap| {
            wrap.spawn((
                Node {
                    padding: UiRect::axes(px(10), px(8)),
                    column_gap: px(6),
                    flex_wrap: FlexWrap::Wrap,
                    justify_content: JustifyContent::Center,
                    ..default()
                },
                ui_hierarchy_bundle(),
            ))
            .with_children(|row| {
                for badge in badges {
                    row.spawn((
                        Node {
                            padding: UiRect::axes(px(10), px(5)),
                            margin: UiRect::all(px(2)),
                            border: UiRect::all(px(1)),
                            ..default()
                        },
                        BackgroundColor(Color::srgba(0.08, 0.09, 0.13, 0.94)),
                        BorderColor::all(Color::srgba(0.24, 0.27, 0.37, 1.0)),
                        ui_hierarchy_bundle(),
                    ))
                    .with_children(|badge_node| {
                        badge_node.spawn(text_bundle(
                            font,
                            &badge,
                            9.6,
                            Color::srgba(0.92, 0.95, 1.0, 1.0),
                        ));
                    });
                }
            });
        });
}

pub(super) fn render_stat_meter(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    label: &str,
    value_text: &str,
    ratio: f32,
    fill_color: Color,
    border_color: Color,
) {
    parent
        .spawn((
            Node {
                flex_grow: 1.0,
                min_width: px(120),
                flex_direction: FlexDirection::Column,
                row_gap: px(4),
                ..default()
            },
            BackgroundColor(Color::NONE),
            ui_hierarchy_bundle(),
        ))
        .with_children(|meter| {
            meter
                .spawn((
                    Node {
                        width: Val::Percent(100.0),
                        flex_direction: FlexDirection::Row,
                        justify_content: JustifyContent::SpaceBetween,
                        ..default()
                    },
                    ui_hierarchy_bundle(),
                ))
                .with_children(|labels| {
                    labels.spawn(text_bundle(
                        font,
                        label,
                        9.6,
                        Color::srgba(0.84, 0.88, 0.95, 1.0),
                    ));
                    labels.spawn(text_bundle(font, value_text, 9.6, Color::WHITE));
                });
            meter
                .spawn((
                    Node {
                        width: Val::Percent(100.0),
                        height: px(18),
                        padding: UiRect::all(px(2)),
                        border: UiRect::all(px(1)),
                        ..default()
                    },
                    BackgroundColor(Color::srgba(0.05, 0.06, 0.08, 0.98)),
                    BorderColor::all(border_color),
                    ui_hierarchy_bundle(),
                ))
                .with_children(|track| {
                    track.spawn((
                        Node {
                            width: Val::Percent((ratio.clamp(0.0, 1.0)) * 100.0),
                            height: Val::Percent(100.0),
                            ..default()
                        },
                        BackgroundColor(fill_color),
                    ));
                });
        });
}

pub(super) fn dock_tab_button(
    font: &ViewerUiFont,
    label: &str,
    active: bool,
    action: GameUiButtonAction,
) -> impl Bundle {
    (
        Button,
        Node {
            height: px(BOTTOM_TAB_HEIGHT),
            padding: UiRect::axes(px(7), px(3)),
            border: UiRect::all(px(if active { 2.0 } else { 1.0 })),
            justify_content: JustifyContent::Center,
            align_items: AlignItems::Center,
            ..default()
        },
        BackgroundColor(if active {
            Color::srgba(0.15, 0.18, 0.26, 0.98).into()
        } else {
            Color::srgba(0.07, 0.08, 0.11, 0.95).into()
        }),
        BorderColor::all(if active {
            Color::srgba(0.62, 0.72, 0.90, 1.0)
        } else {
            Color::srgba(0.21, 0.24, 0.31, 1.0)
        }),
        action,
        Text::new(label.to_string()),
        TextFont::from_font_size(8.3).with_font(font.0.clone()),
        TextColor(if active {
            Color::WHITE
        } else {
            Color::srgba(0.80, 0.84, 0.90, 1.0)
        }),
    )
}

pub(super) fn activation_mode_label(mode: &str) -> String {
    match mode {
        "passive" => "被动".to_string(),
        "toggle" => "开关".to_string(),
        "active" => "主动".to_string(),
        "instant" => "瞬发".to_string(),
        "channeled" => "引导".to_string(),
        other => other.to_string(),
    }
}

pub(super) fn truncate_ui_text(text: &str, max_chars: usize) -> String {
    let trimmed = text.trim();
    let total_chars = trimmed.chars().count();
    if total_chars <= max_chars {
        return trimmed.to_string();
    }
    let visible = max_chars.saturating_sub(1);
    let prefix = trimmed.chars().take(visible).collect::<String>();
    format!("{prefix}…")
}

pub(super) fn compact_skill_name(name: &str, max_chars: usize) -> String {
    truncate_ui_text(name, max_chars)
}

pub(super) fn abbreviated_skill_name(name: &str) -> String {
    let initials = name
        .split(|ch: char| ch.is_whitespace() || ch == '_' || ch == '-')
        .filter(|part| !part.is_empty())
        .filter_map(|part| part.chars().next())
        .take(2)
        .collect::<String>()
        .to_uppercase();
    if !initials.is_empty() {
        return initials;
    }
    let fallback = name.trim();
    if fallback.is_empty() {
        "·".to_string()
    } else {
        fallback.chars().take(2).collect::<String>().to_uppercase()
    }
}

pub(super) fn hotbar_key_label(slot_index: usize) -> &'static str {
    match slot_index {
        0 => "1",
        1 => "2",
        2 => "3",
        3 => "4",
        4 => "5",
        5 => "6",
        6 => "7",
        7 => "8",
        8 => "9",
        9 => "0",
        _ => "?",
    }
}

pub(super) fn skill_tree_progress(tree: &game_bevy::UiSkillTreeView) -> (usize, usize) {
    let learned = tree
        .entries
        .iter()
        .filter(|entry| entry.learned_level > 0)
        .count();
    (learned, tree.entries.len())
}

pub(super) fn selected_skill_tree<'a>(
    snapshot: &'a game_bevy::UiSkillsSnapshot,
    menu_state: &UiMenuState,
) -> Option<&'a game_bevy::UiSkillTreeView> {
    menu_state
        .selected_skill_tree_id
        .as_deref()
        .and_then(|tree_id| snapshot.trees.iter().find(|tree| tree.tree_id == tree_id))
        .or_else(|| {
            menu_state
                .selected_skill_id
                .as_deref()
                .and_then(|skill_id| find_skill_tree_id(snapshot, skill_id))
                .and_then(|tree_id| snapshot.trees.iter().find(|tree| tree.tree_id == tree_id))
        })
        .or_else(|| snapshot.trees.iter().find(|tree| !tree.entries.is_empty()))
        .or_else(|| snapshot.trees.first())
}

pub(super) fn selected_skill_entry<'a>(
    tree: &'a game_bevy::UiSkillTreeView,
    selected_skill_id: Option<&str>,
) -> Option<&'a game_bevy::UiSkillEntryView> {
    selected_skill_id
        .and_then(|skill_id| tree.entries.iter().find(|entry| entry.skill_id == skill_id))
        .or_else(|| tree.entries.first())
}

pub(super) fn current_group_skill_slot(
    hotbar_state: &UiHotbarState,
    skill_id: &str,
) -> Option<usize> {
    hotbar_state
        .groups
        .get(hotbar_state.active_group)
        .and_then(|group| {
            group
                .iter()
                .position(|slot| slot.skill_id.as_deref() == Some(skill_id))
        })
}

pub(super) fn format_skill_prerequisites(entry: &game_bevy::UiSkillEntryView) -> String {
    if entry.prerequisite_names.is_empty() {
        "无".to_string()
    } else {
        entry.prerequisite_names.join(" · ")
    }
}

pub(super) fn format_skill_attribute_requirements(entry: &game_bevy::UiSkillEntryView) -> String {
    if entry.attribute_requirements.is_empty() {
        "无".to_string()
    } else {
        entry
            .attribute_requirements
            .iter()
            .map(|(attribute, value)| format!("{attribute} {value}"))
            .collect::<Vec<_>>()
            .join(" · ")
    }
}

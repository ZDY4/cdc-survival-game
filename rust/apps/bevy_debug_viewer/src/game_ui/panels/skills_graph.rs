//! 技能树图渲染 helper：负责把 snapshot 中的节点/连线布局渲染成可点击树图。

use std::collections::BTreeMap;

use super::*;

const SKILL_TREE_NODE_WIDTH: f32 = 136.0;
const SKILL_TREE_NODE_HEIGHT: f32 = 72.0;
const SKILL_TREE_CANVAS_PADDING: f32 = 28.0;
const SKILL_TREE_LINK_THICKNESS: f32 = 2.0;
const SKILL_TREE_MIN_CANVAS_HEIGHT: f32 = 260.0;

#[derive(Debug, Clone, Copy)]
pub(super) struct SkillTreeCanvasNodeFrame {
    pub left: f32,
    pub top: f32,
    pub center_x: f32,
    pub center_y: f32,
}

#[derive(Debug, Clone)]
pub(super) struct SkillTreeCanvasLayout {
    pub width: f32,
    pub height: f32,
    pub node_frames: BTreeMap<String, SkillTreeCanvasNodeFrame>,
}

pub(super) fn build_skill_tree_canvas_layout(
    tree: &game_bevy::UiSkillTreeView,
) -> SkillTreeCanvasLayout {
    if tree.nodes.is_empty() {
        return SkillTreeCanvasLayout {
            width: SKILL_TREE_NODE_WIDTH + SKILL_TREE_CANVAS_PADDING * 2.0,
            height: SKILL_TREE_MIN_CANVAS_HEIGHT,
            node_frames: BTreeMap::new(),
        };
    }

    let min_x = tree
        .nodes
        .iter()
        .map(|node| node.x)
        .min_by(f32::total_cmp)
        .unwrap_or_default();
    let max_x = tree
        .nodes
        .iter()
        .map(|node| node.x)
        .max_by(f32::total_cmp)
        .unwrap_or_default();
    let min_y = tree
        .nodes
        .iter()
        .map(|node| node.y)
        .min_by(f32::total_cmp)
        .unwrap_or_default();
    let max_y = tree
        .nodes
        .iter()
        .map(|node| node.y)
        .max_by(f32::total_cmp)
        .unwrap_or_default();

    let node_frames = tree
        .nodes
        .iter()
        .map(|node| {
            let left = SKILL_TREE_CANVAS_PADDING + (node.x - min_x);
            let top = SKILL_TREE_CANVAS_PADDING + (node.y - min_y);
            (
                node.skill_id.clone(),
                SkillTreeCanvasNodeFrame {
                    left,
                    top,
                    center_x: left + SKILL_TREE_NODE_WIDTH * 0.5,
                    center_y: top + SKILL_TREE_NODE_HEIGHT * 0.5,
                },
            )
        })
        .collect();

    SkillTreeCanvasLayout {
        width: (max_x - min_x) + SKILL_TREE_NODE_WIDTH + SKILL_TREE_CANVAS_PADDING * 2.0,
        height: ((max_y - min_y) + SKILL_TREE_NODE_HEIGHT + SKILL_TREE_CANVAS_PADDING * 2.0)
            .max(SKILL_TREE_MIN_CANVAS_HEIGHT),
        node_frames,
    }
}

pub(super) fn render_skill_tree_canvas(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    tree: &game_bevy::UiSkillTreeView,
    menu_state: &UiMenuState,
) {
    let layout = build_skill_tree_canvas_layout(tree);
    let entries_by_id = tree
        .entries
        .iter()
        .map(|entry| (entry.skill_id.as_str(), entry))
        .collect::<BTreeMap<_, _>>();

    parent
        .spawn((
            Node {
                width: Val::Percent(100.0),
                min_height: px(layout.height),
                padding: UiRect::all(px(10)),
                justify_content: JustifyContent::Center,
                align_items: AlignItems::Start,
                overflow: Overflow::clip(),
                border: UiRect::all(px(1)),
                ..default()
            },
            BackgroundColor(ui_panel_background_alt().into()),
            BorderColor::all(ui_border_color()),
            viewer_ui_passthrough_bundle(),
        ))
        .with_children(|frame| {
            frame
                .spawn((
                    Node {
                        width: px(layout.width),
                        height: px(layout.height),
                        min_width: px(layout.width),
                        min_height: px(layout.height),
                        ..default()
                    },
                    viewer_ui_passthrough_bundle(),
                ))
                .with_children(|canvas| {
                    for link in &tree.links {
                        let Some(from_frame) = layout.node_frames.get(&link.from_skill_id) else {
                            continue;
                        };
                        let Some(to_frame) = layout.node_frames.get(&link.to_skill_id) else {
                            continue;
                        };
                        spawn_skill_tree_link(canvas, *from_frame, *to_frame);
                    }

                    for node in &tree.nodes {
                        let Some(entry) = entries_by_id.get(node.skill_id.as_str()) else {
                            continue;
                        };
                        let Some(frame_rect) = layout.node_frames.get(&node.skill_id) else {
                            continue;
                        };
                        let is_selected = menu_state
                            .selected_skill_id
                            .as_deref()
                            .map(|selected| selected == entry.skill_id)
                            .unwrap_or(false);
                        let state_label = skill_node_state_label(entry);
                        let state_color = skill_node_state_color(entry);

                        canvas
                            .spawn((
                                Button,
                                Node {
                                    position_type: PositionType::Absolute,
                                    left: px(frame_rect.left),
                                    top: px(frame_rect.top),
                                    width: px(SKILL_TREE_NODE_WIDTH),
                                    height: px(SKILL_TREE_NODE_HEIGHT),
                                    padding: UiRect::axes(px(8), px(6)),
                                    flex_direction: FlexDirection::Column,
                                    justify_content: JustifyContent::Center,
                                    row_gap: px(2),
                                    border: UiRect::all(px(if is_selected { 2.0 } else { 1.0 })),
                                    ..default()
                                },
                                BackgroundColor(skill_node_background(entry, is_selected).into()),
                                BorderColor::all(if is_selected {
                                    ui_border_selected_color()
                                } else {
                                    skill_node_border(entry)
                                }),
                                GameUiButtonAction::SelectSkill(entry.skill_id.clone()),
                                SkillHoverTarget {
                                    tree_id: tree.tree_id.clone(),
                                    skill_id: entry.skill_id.clone(),
                                },
                                RelativeCursorPosition::default(),
                                viewer_ui_passthrough_bundle(),
                            ))
                            .with_children(|button| {
                                button.spawn(text_bundle(
                                    font,
                                    &compact_skill_name(&entry.name, 14),
                                    10.4,
                                    if entry.learned_level > 0 {
                                        Color::WHITE
                                    } else {
                                        ui_text_secondary_color()
                                    },
                                ));
                                button.spawn(text_bundle(
                                    font,
                                    &format!("Lv {}/{}", entry.learned_level, entry.max_level),
                                    8.8,
                                    ui_text_muted_color(),
                                ));
                                button.spawn(text_bundle(font, state_label, 8.8, state_color));
                            });
                    }
                });
        });
}

fn spawn_skill_tree_link(
    parent: &mut ChildSpawnerCommands,
    from: SkillTreeCanvasNodeFrame,
    to: SkillTreeCanvasNodeFrame,
) {
    let color = Color::srgba(0.43, 0.49, 0.58, 0.95);
    let mid_x = (from.center_x + to.center_x) * 0.5;
    let first_left = from.center_x.min(mid_x);
    let first_width = (from.center_x - mid_x).abs().max(SKILL_TREE_LINK_THICKNESS);
    let second_top = from.center_y.min(to.center_y);
    let second_height = (from.center_y - to.center_y)
        .abs()
        .max(SKILL_TREE_LINK_THICKNESS);
    let third_left = mid_x.min(to.center_x);
    let third_width = (mid_x - to.center_x).abs().max(SKILL_TREE_LINK_THICKNESS);

    spawn_skill_tree_link_segment(
        parent,
        first_left,
        from.center_y - SKILL_TREE_LINK_THICKNESS * 0.5,
        first_width,
        SKILL_TREE_LINK_THICKNESS,
        color,
    );
    spawn_skill_tree_link_segment(
        parent,
        mid_x - SKILL_TREE_LINK_THICKNESS * 0.5,
        second_top,
        SKILL_TREE_LINK_THICKNESS,
        second_height,
        color,
    );
    spawn_skill_tree_link_segment(
        parent,
        third_left,
        to.center_y - SKILL_TREE_LINK_THICKNESS * 0.5,
        third_width,
        SKILL_TREE_LINK_THICKNESS,
        color,
    );
}

fn spawn_skill_tree_link_segment(
    parent: &mut ChildSpawnerCommands,
    left: f32,
    top: f32,
    width: f32,
    height: f32,
    color: Color,
) {
    parent.spawn((
        Node {
            position_type: PositionType::Absolute,
            left: px(left),
            top: px(top),
            width: px(width),
            height: px(height),
            ..default()
        },
        BackgroundColor(color.into()),
        viewer_ui_passthrough_bundle(),
    ));
}

fn skill_node_background(entry: &game_bevy::UiSkillEntryView, is_selected: bool) -> Color {
    if is_selected {
        ui_panel_background_selected()
    } else if entry.learned_level > 0 {
        Color::srgba(0.17, 0.24, 0.19, 0.96)
    } else {
        ui_panel_background()
    }
}

fn skill_node_border(entry: &game_bevy::UiSkillEntryView) -> Color {
    if entry.learned_level > 0 {
        Color::srgba(0.40, 0.64, 0.44, 1.0)
    } else {
        ui_border_color()
    }
}

fn skill_node_state_label(entry: &game_bevy::UiSkillEntryView) -> &'static str {
    if entry.learned_level > 0 {
        if entry.hotbar_eligible {
            "可绑定"
        } else {
            "已学习"
        }
    } else {
        "未学习"
    }
}

fn skill_node_state_color(entry: &game_bevy::UiSkillEntryView) -> Color {
    if entry.learned_level > 0 {
        Color::srgba(0.72, 0.92, 0.72, 1.0)
    } else {
        Color::srgba(0.58, 0.63, 0.70, 1.0)
    }
}

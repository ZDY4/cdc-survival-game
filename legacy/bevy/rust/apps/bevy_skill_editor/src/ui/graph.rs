use std::collections::BTreeMap;

use bevy_egui::egui;

use crate::commands::SkillEditorCommand;
use crate::state::{display_skill_name, skill_activation_mode, EditorState, SkillEditorCatalogs};

const NODE_WIDTH: f32 = 152.0;
const NODE_HEIGHT: f32 = 74.0;
const CANVAS_PADDING: f32 = 32.0;
const FALLBACK_COLUMNS: usize = 3;
const FALLBACK_X_STEP: f32 = 220.0;
const FALLBACK_Y_STEP: f32 = 150.0;

#[derive(Debug, Clone, Copy)]
struct GraphNodeFrame {
    left: f32,
    top: f32,
}

pub(crate) fn render_skill_tree_graph(
    ui: &mut egui::Ui,
    editor: &EditorState,
    catalogs: &SkillEditorCatalogs,
    commands: &mut bevy::ecs::message::MessageWriter<SkillEditorCommand>,
) {
    let Some(tree_id) = editor.selected_tree_id.as_deref() else {
        ui.label("没有已选择的技能树。");
        return;
    };
    let Some(tree) = catalogs.tree(tree_id) else {
        ui.label("当前技能树不存在。");
        return;
    };

    let skill_ids = catalogs.tree_skill_ids(tree_id);
    if skill_ids.is_empty() {
        ui.label("该技能树没有技能。");
        return;
    }

    let layout = build_graph_layout(tree, skill_ids);
    egui::ScrollArea::both()
        .auto_shrink([false, false])
        .show(ui, |ui| {
            let (canvas_rect, _) = ui.allocate_exact_size(
                egui::vec2(layout.width, layout.height),
                egui::Sense::hover(),
            );
            let painter = ui.painter_at(canvas_rect);

            for link in &tree.links {
                let Some(from) = layout.node_frames.get(&link.from) else {
                    continue;
                };
                let Some(to) = layout.node_frames.get(&link.to) else {
                    continue;
                };
                let start = canvas_rect.min
                    + egui::vec2(from.left + NODE_WIDTH * 0.5, from.top + NODE_HEIGHT * 0.5);
                let end = canvas_rect.min
                    + egui::vec2(to.left + NODE_WIDTH * 0.5, to.top + NODE_HEIGHT * 0.5);
                painter.line_segment(
                    [start, end],
                    egui::Stroke::new(2.0, egui::Color32::from_rgb(93, 103, 122)),
                );
            }

            for skill_id in skill_ids {
                let Some(skill) = catalogs.skill(skill_id) else {
                    continue;
                };
                let Some(frame) = layout.node_frames.get(skill_id) else {
                    continue;
                };
                let selected = editor.selected_skill_id.as_deref() == Some(skill_id.as_str());
                let rect = egui::Rect::from_min_size(
                    canvas_rect.min + egui::vec2(frame.left, frame.top),
                    egui::vec2(NODE_WIDTH, NODE_HEIGHT),
                );
                let label = format!(
                    "{}\n{}",
                    compact_skill_name(&display_skill_name(skill), 16),
                    skill_activation_mode(skill)
                );
                let response = ui.put(
                    rect,
                    egui::Button::new(
                        egui::RichText::new(label)
                            .size(12.0)
                            .color(egui::Color32::from_rgb(242, 244, 247)),
                    )
                    .min_size(rect.size())
                    .fill(node_fill_color(skill_activation_mode(skill)))
                    .stroke(egui::Stroke::new(
                        if selected { 2.0 } else { 1.0 },
                        if selected {
                            egui::Color32::from_rgb(255, 220, 135)
                        } else {
                            egui::Color32::from_rgb(68, 76, 94)
                        },
                    )),
                );
                if response.clicked() {
                    commands.write(SkillEditorCommand::SelectSkill(skill_id.clone()));
                }
                response.on_hover_text(format!(
                    "{}\n{}\n{}",
                    display_skill_name(skill),
                    skill.id,
                    skill.tree_id
                ));
            }
        });
}

struct GraphLayout {
    width: f32,
    height: f32,
    node_frames: BTreeMap<String, GraphNodeFrame>,
}

fn build_graph_layout(tree: &game_data::SkillTreeDefinition, skill_ids: &[String]) -> GraphLayout {
    let mut raw_positions = BTreeMap::<String, (f32, f32)>::new();
    let max_existing_y = tree
        .layout
        .values()
        .map(|position| position.y)
        .max_by(f32::total_cmp)
        .unwrap_or(0.0);
    let mut fallback_index = 0usize;

    for skill_id in skill_ids {
        if let Some(position) = tree.layout.get(skill_id) {
            raw_positions.insert(skill_id.clone(), (position.x, position.y));
        } else {
            let column = (fallback_index % FALLBACK_COLUMNS) as f32;
            let row = (fallback_index / FALLBACK_COLUMNS) as f32;
            raw_positions.insert(
                skill_id.clone(),
                (
                    column * FALLBACK_X_STEP,
                    max_existing_y + FALLBACK_Y_STEP + row * FALLBACK_Y_STEP,
                ),
            );
            fallback_index += 1;
        }
    }

    let min_x = raw_positions
        .values()
        .map(|(x, _)| *x)
        .min_by(f32::total_cmp)
        .unwrap_or(0.0);
    let max_x = raw_positions
        .values()
        .map(|(x, _)| *x)
        .max_by(f32::total_cmp)
        .unwrap_or(0.0);
    let min_y = raw_positions
        .values()
        .map(|(_, y)| *y)
        .min_by(f32::total_cmp)
        .unwrap_or(0.0);
    let max_y = raw_positions
        .values()
        .map(|(_, y)| *y)
        .max_by(f32::total_cmp)
        .unwrap_or(0.0);

    let node_frames = raw_positions
        .into_iter()
        .map(|(skill_id, (x, y))| {
            (
                skill_id,
                GraphNodeFrame {
                    left: CANVAS_PADDING + (x - min_x),
                    top: CANVAS_PADDING + (y - min_y),
                },
            )
        })
        .collect::<BTreeMap<_, _>>();

    GraphLayout {
        width: (max_x - min_x) + NODE_WIDTH + CANVAS_PADDING * 2.0,
        height: (max_y - min_y) + NODE_HEIGHT + CANVAS_PADDING * 2.0,
        node_frames,
    }
}

fn node_fill_color(mode: &str) -> egui::Color32 {
    match mode {
        "active" => egui::Color32::from_rgb(56, 73, 103),
        "toggle" => egui::Color32::from_rgb(72, 83, 54),
        _ => egui::Color32::from_rgb(61, 61, 68),
    }
}

fn compact_skill_name(name: &str, max_chars: usize) -> String {
    let trimmed = name.trim();
    if trimmed.chars().count() <= max_chars {
        return trimmed.to_string();
    }
    let visible = max_chars.saturating_sub(1);
    let prefix = trimmed.chars().take(visible).collect::<String>();
    format!("{prefix}…")
}

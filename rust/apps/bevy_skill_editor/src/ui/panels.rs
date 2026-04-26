use bevy_egui::egui;

use crate::commands::SkillEditorCommand;
use crate::state::{
    display_skill_name, display_tree_name, skill_activation_mode, EditorState, SkillEditorCatalogs,
};

use super::graph::render_skill_tree_graph;

pub(crate) const LEFT_PANEL_WIDTH: f32 = 320.0;
pub(crate) const RIGHT_PANEL_WIDTH: f32 = 430.0;

pub(crate) fn render_top_bar(
    ui: &mut egui::Ui,
    editor: &EditorState,
    catalogs: &SkillEditorCatalogs,
    commands: &mut bevy::ecs::message::MessageWriter<SkillEditorCommand>,
) {
    ui.horizontal(|ui| {
        ui.heading("技能编辑器");
        ui.separator();
        ui.label(format!("技能树 {}", catalogs.sorted_tree_ids.len()));
        ui.separator();
        ui.label(format!("技能 {}", catalogs.skills.len()));
        ui.separator();
        ui.small(format!("仓库 {}", editor.repo_root.display()));
        ui.separator();
        ui.small(&editor.status);

        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
            if ui.button("重新加载").clicked() {
                commands.write(SkillEditorCommand::Reload);
            }
        });
    });
}

pub(crate) fn render_left_panel(
    ui: &mut egui::Ui,
    editor: &mut EditorState,
    catalogs: &SkillEditorCatalogs,
    commands: &mut bevy::ecs::message::MessageWriter<SkillEditorCommand>,
) {
    ui.heading("技能树");
    ui.separator();

    egui::ScrollArea::vertical()
        .max_height(240.0)
        .auto_shrink([false, false])
        .show(ui, |ui| {
            for tree_id in &catalogs.sorted_tree_ids {
                let Some(tree) = catalogs.tree(tree_id) else {
                    continue;
                };
                let selected = editor.selected_tree_id.as_deref() == Some(tree_id.as_str())
                    && editor.selected_skill_id.is_none();
                let label = format!(
                    "{}  [{}]",
                    display_tree_name(tree),
                    catalogs.tree_skill_ids(tree_id).len()
                );
                if ui
                    .add_sized(
                        [ui.available_width(), 0.0],
                        egui::Button::new(label.as_str())
                            .selected(selected)
                            .truncate(),
                    )
                    .on_hover_text(tree.id.as_str())
                    .clicked()
                {
                    commands.write(SkillEditorCommand::SelectTree(tree_id.clone()));
                }
            }
        });

    ui.add_space(10.0);
    ui.heading("技能搜索");
    ui.horizontal(|ui| {
        ui.label("关键词");
        ui.add(
            egui::TextEdit::singleline(&mut editor.search_text)
                .hint_text("技能名 / 技能 ID / 技能树")
                .desired_width(f32::INFINITY),
        );
    });
    ui.separator();

    let needle = editor.search_text.trim().to_lowercase();
    let results = catalogs
        .search_entries
        .iter()
        .filter(|entry| needle.is_empty() || entry.search_blob.contains(&needle))
        .collect::<Vec<_>>();
    ui.small(format!("{} 个结果", results.len()));

    egui::ScrollArea::vertical()
        .auto_shrink([false, false])
        .show(ui, |ui| {
            for entry in results {
                let selected = editor.selected_skill_id.as_deref() == Some(entry.skill_id.as_str());
                let label = format!(
                    "{}  [{}] · {}",
                    entry.skill_name, entry.skill_id, entry.tree_name
                );
                if ui
                    .add_sized(
                        [ui.available_width(), 0.0],
                        egui::Button::new(label.as_str())
                            .selected(selected)
                            .truncate(),
                    )
                    .on_hover_text(format!(
                        "skill: {}\ntree: {}",
                        entry.skill_id, entry.tree_id
                    ))
                    .clicked()
                {
                    commands.write(SkillEditorCommand::SelectSkill(entry.skill_id.clone()));
                }
            }
        });
}

pub(crate) fn render_tree_graph_panel(
    ui: &mut egui::Ui,
    editor: &EditorState,
    catalogs: &SkillEditorCatalogs,
    commands: &mut bevy::ecs::message::MessageWriter<SkillEditorCommand>,
) {
    let Some(tree_id) = editor.selected_tree_id.as_deref() else {
        ui.label("没有可显示的技能树。");
        return;
    };
    let Some(tree) = catalogs.tree(tree_id) else {
        ui.label("当前技能树不存在。");
        return;
    };

    ui.heading(display_tree_name(tree));
    if !tree.description.trim().is_empty() {
        ui.label(&tree.description);
    }
    ui.small("点击节点查看技能详情。节点颜色反映 activation mode，连线表示技能关系。");
    ui.add_space(8.0);

    render_skill_tree_graph(ui, editor, catalogs, commands);
}

pub(crate) fn render_detail_panel(
    ui: &mut egui::Ui,
    editor: &EditorState,
    catalogs: &SkillEditorCatalogs,
) {
    if let Some(skill_id) = editor.selected_skill_id.as_deref() {
        if let Some(skill) = catalogs.skill(skill_id) {
            render_skill_detail(ui, skill, catalogs);
            return;
        }
    }

    let Some(tree_id) = editor.selected_tree_id.as_deref() else {
        ui.label("没有可显示的技能树详情。");
        return;
    };
    let Some(tree) = catalogs.tree(tree_id) else {
        ui.label("当前技能树不存在。");
        return;
    };

    ui.heading(display_tree_name(tree));
    ui.small(format!("tree_id: {}", tree.id));
    if !tree.description.trim().is_empty() {
        ui.add_space(6.0);
        ui.label(&tree.description);
    }

    ui.add_space(8.0);
    ui.collapsing("树摘要", |ui| {
        ui.label(format!(
            "技能数: {}",
            catalogs.tree_skill_ids(tree_id).len()
        ));
        ui.label(format!("连线数: {}", tree.links.len()));
        ui.label(format!(
            "布局覆盖: {}/{}",
            tree.layout.len(),
            catalogs.tree_skill_ids(tree_id).len()
        ));
    });

    ui.add_space(8.0);
    ui.collapsing("技能列表", |ui| {
        if catalogs.tree_skill_ids(tree_id).is_empty() {
            ui.label("该技能树当前没有技能。");
        } else {
            for skill_id in catalogs.tree_skill_ids(tree_id) {
                let Some(skill) = catalogs.skill(skill_id) else {
                    continue;
                };
                ui.label(format!(
                    "{} · {} · {}",
                    display_skill_name(skill),
                    skill.id,
                    skill_activation_mode(skill)
                ));
            }
        }
    });

    ui.add_space(8.0);
    ui.collapsing("当前技能树 JSON", |ui| {
        let mut raw = serde_json::to_string_pretty(tree).unwrap_or_else(|_| "{}".to_string());
        ui.add(
            egui::TextEdit::multiline(&mut raw)
                .desired_width(f32::INFINITY)
                .desired_rows(18)
                .font(egui::TextStyle::Monospace)
                .interactive(false),
        );
    });
}

fn render_skill_detail(
    ui: &mut egui::Ui,
    skill: &game_data::SkillDefinition,
    catalogs: &SkillEditorCatalogs,
) {
    let tree_name = catalogs.display_tree_name(&skill.tree_id);
    let reverse_prerequisites = catalogs
        .reverse_prerequisites
        .get(&skill.id)
        .cloned()
        .unwrap_or_default();

    ui.heading(display_skill_name(skill));
    ui.small(format!("skill_id: {}", skill.id));
    ui.small(format!("所属技能树: {} [{}]", tree_name, skill.tree_id));
    ui.small(format!("activation: {}", skill_activation_mode(skill)));

    if !skill.description.trim().is_empty() {
        ui.add_space(6.0);
        ui.label(&skill.description);
    }

    ui.add_space(8.0);
    ui.collapsing("基础信息", |ui| {
        ui.label(format!("最大等级: {}", skill.max_level));
        ui.label(format!("前置技能数: {}", skill.prerequisites.len()));
        ui.label(format!(
            "属性要求数: {}",
            skill.attribute_requirements.len()
        ));
    });

    ui.add_space(8.0);
    ui.collapsing("前置技能", |ui| {
        if skill.prerequisites.is_empty() {
            ui.label("无前置技能。");
        } else {
            for prerequisite_id in &skill.prerequisites {
                ui.label(format!(
                    "{} · {}",
                    catalogs.display_skill_name(prerequisite_id),
                    prerequisite_id
                ));
            }
        }
    });

    ui.add_space(8.0);
    ui.collapsing("反向依赖", |ui| {
        if reverse_prerequisites.is_empty() {
            ui.label("当前没有其他技能依赖它。");
        } else {
            for skill_id in reverse_prerequisites {
                ui.label(format!(
                    "{} · {}",
                    catalogs.display_skill_name(&skill_id),
                    skill_id
                ));
            }
        }
    });

    ui.add_space(8.0);
    ui.collapsing("属性要求", |ui| {
        if skill.attribute_requirements.is_empty() {
            ui.label("无属性要求。");
        } else {
            for (attribute, value) in &skill.attribute_requirements {
                ui.label(format!("{attribute}: {value}"));
            }
        }
    });

    ui.add_space(8.0);
    ui.collapsing("Activation", |ui| {
        if let Some(activation) = skill.activation.as_ref() {
            ui.label(format!("mode: {}", skill_activation_mode(skill)));
            ui.label(format!("cooldown: {:.1}", activation.cooldown));
            if let Some(effect) = activation.effect.as_ref() {
                ui.separator();
                ui.label(format!("effect.duration: {:.1}", effect.duration));
                ui.label(format!("effect.is_infinite: {}", effect.is_infinite));
                ui.label(format!(
                    "effect.category: {}",
                    empty_placeholder(&effect.category)
                ));
                if effect.modifiers.is_empty() {
                    ui.label("effect.modifiers: 无");
                } else {
                    for (modifier_id, modifier) in &effect.modifiers {
                        ui.label(format!(
                            "{} => base {:.2}, per_level {:.2}, max {:.2}",
                            modifier_id, modifier.base, modifier.per_level, modifier.max_value
                        ));
                    }
                }
            }
        } else {
            ui.label("无 activation 定义。");
        }
    });

    ui.add_space(8.0);
    ui.collapsing("Targeting", |ui| {
        let Some(targeting) = skill
            .activation
            .as_ref()
            .and_then(|activation| activation.targeting.as_ref())
        else {
            ui.label("无 targeting 定义。");
            return;
        };

        ui.label(format!("enabled: {}", targeting.enabled));
        ui.label(format!("range_cells: {}", targeting.range_cells));
        ui.label(format!("shape: {}", empty_placeholder(&targeting.shape)));
        ui.label(format!("radius: {}", targeting.radius));
        ui.label(format!("execution_kind: {:?}", targeting.execution_kind));
        ui.label(format!(
            "target_side_rule: {:?}",
            targeting.target_side_rule
        ));
        ui.label(format!("require_los: {}", targeting.require_los));
        ui.label(format!("allow_self: {}", targeting.allow_self));
        ui.label(format!(
            "allow_friendly_fire: {}",
            targeting.allow_friendly_fire
        ));
    });

    ui.add_space(8.0);
    ui.collapsing("Gameplay Effect", |ui| {
        let Some(effect) = skill.gameplay_effect.as_ref() else {
            ui.label("无 gameplay_effect 定义。");
            return;
        };
        if effect.modifiers.is_empty() {
            ui.label("无 modifiers。");
        } else {
            for (modifier_id, modifier) in &effect.modifiers {
                ui.label(format!(
                    "{} => base {:.2}, per_level {:.2}, max {:.2}",
                    modifier_id, modifier.base, modifier.per_level, modifier.max_value
                ));
            }
        }
    });

    ui.add_space(8.0);
    ui.collapsing("当前技能 JSON", |ui| {
        let mut raw = serde_json::to_string_pretty(skill).unwrap_or_else(|_| "{}".to_string());
        ui.add(
            egui::TextEdit::multiline(&mut raw)
                .desired_width(f32::INFINITY)
                .desired_rows(18)
                .font(egui::TextStyle::Monospace)
                .interactive(false),
        );
    });
}

fn empty_placeholder(value: &str) -> &str {
    if value.trim().is_empty() {
        "-"
    } else {
        value
    }
}

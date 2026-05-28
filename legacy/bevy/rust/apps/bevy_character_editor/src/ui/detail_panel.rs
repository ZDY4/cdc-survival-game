//! 右侧详情面板。
//! 负责角色摘要、生活页、AI 页、外观页的页签路由和公共头部操作。

use bevy::prelude::MessageWriter;
use bevy_egui::egui;
use game_data::{CharacterDefinition, SettlementId};

use crate::camera_mode::PreviewCameraModeState;
use crate::commands::CharacterEditorCommand;
use crate::preview::selected_character;
use crate::state::{
    archetype_label, disposition_label, non_empty, npc_role_label, CharacterTab, EditorData,
    EditorUiState, PreviewState,
};

use super::ai_tab::render_ai_tab;
use super::appearance_tab::render_appearance_tab;
use super::common::{key_value, key_value_with_tooltip, tab_button};

// 右侧详情区入口，统一组织页签切换和当前角色头部操作。
pub(crate) fn render_detail_panel(
    ui: &mut egui::Ui,
    data: &EditorData,
    ui_state: &mut EditorUiState,
    preview_state: &PreviewState,
    _camera_mode: &PreviewCameraModeState,
    requests: &mut MessageWriter<CharacterEditorCommand>,
) {
    let Some(character) = selected_character(data, ui_state) else {
        ui.label("没有可用角色数据。");
        return;
    };

    ui.horizontal(|ui| {
        ui.heading(format!(
            "{}  [{}]",
            character.identity.display_name,
            character.id.as_str()
        ));
        if ui
            .small_button("重置相机")
            .on_hover_text("将预览相机重置到当前模式的默认构图。")
            .clicked()
        {
            requests.write(CharacterEditorCommand::ResetCamera);
        }
        if ui
            .small_button("清空试装")
            .on_hover_text("清空所有临时试装槽位，仅显示角色基础外观。")
            .clicked()
        {
            requests.write(CharacterEditorCommand::ClearTryOn);
        }
    });
    ui.small(format!(
        "{} / {} / {}",
        archetype_label(character),
        disposition_label(character),
        non_empty(&character.faction.camp_id)
    ));
    ui.separator();

    ui.horizontal_wrapped(|ui| {
        tab_button(ui, ui_state, CharacterTab::Summary, "摘要");
        tab_button(ui, ui_state, CharacterTab::Life, "生活");
        tab_button(ui, ui_state, CharacterTab::AiPreview, "AI 预览");
        tab_button(ui, ui_state, CharacterTab::Appearance, "外观");
    });
    ui.separator();

    egui::ScrollArea::vertical()
        .auto_shrink([false, false])
        .show(ui, |ui| match ui_state.selected_tab {
            CharacterTab::Summary => render_summary_tab(ui, character),
            CharacterTab::Life => render_life_tab(ui, character, data),
            CharacterTab::AiPreview => {
                render_ai_tab(ui, character, data, ui_state, preview_state, requests)
            }
            CharacterTab::Appearance => {
                render_appearance_tab(ui, character, data, ui_state, preview_state, requests)
            }
        });
}

// 角色摘要页，只显示基础静态信息。
fn render_summary_tab(ui: &mut egui::Ui, character: &CharacterDefinition) {
    key_value(ui, "原型", archetype_label(character));
    key_value(ui, "阵营关系", disposition_label(character));
    key_value(ui, "阵营", non_empty(&character.faction.camp_id));
    key_value(ui, "等级", &character.progression.level.to_string());
    key_value(ui, "战斗行为", non_empty(&character.combat.behavior));
    key_value(ui, "经验奖励", &character.combat.xp_reward.to_string());
    key_value(ui, "外观配置", non_empty(&character.appearance_profile_id));
    if !character.identity.description.trim().is_empty() {
        ui.separator();
        ui.label(&character.identity.description);
    }
}

// 生活页，展示角色 life profile 及其据点绑定摘要。
fn render_life_tab(ui: &mut egui::Ui, character: &CharacterDefinition, data: &EditorData) {
    let Some(life) = character.life.as_ref() else {
        ui.label("该角色没有 life profile。");
        return;
    };
    key_value_with_tooltip(
        ui,
        "据点",
        non_empty(&life.settlement_id),
        life_field_tooltip("据点"),
    );
    key_value_with_tooltip(
        ui,
        "角色职责",
        npc_role_label(life.role),
        life_field_tooltip("角色职责"),
    );
    key_value_with_tooltip(
        ui,
        "行为包",
        non_empty(&life.ai_behavior_profile_id),
        life_field_tooltip("行为包"),
    );
    key_value_with_tooltip(
        ui,
        "日程模板",
        non_empty(&life.schedule_profile_id),
        life_field_tooltip("日程模板"),
    );
    key_value_with_tooltip(
        ui,
        "性格模板",
        non_empty(&life.personality_profile_id),
        life_field_tooltip("性格模板"),
    );
    key_value_with_tooltip(
        ui,
        "需求模板",
        non_empty(&life.need_profile_id),
        life_field_tooltip("需求模板"),
    );
    key_value_with_tooltip(
        ui,
        "智能物体访问",
        non_empty(&life.smart_object_access_profile_id),
        life_field_tooltip("智能物体访问"),
    );
    key_value_with_tooltip(
        ui,
        "家锚点",
        non_empty(&life.home_anchor),
        life_field_tooltip("家锚点"),
    );
    key_value_with_tooltip(
        ui,
        "执勤路线",
        non_empty(&life.duty_route_id),
        life_field_tooltip("执勤路线"),
    );

    if let Some(settlement) = data
        .settlements
        .get(&SettlementId(life.settlement_id.clone()))
    {
        ui.separator();
        ui.collapsing("据点引用详情", |ui| {
            key_value_with_tooltip(
                ui,
                "地图",
                settlement.map_id.as_str(),
                settlement_detail_tooltip("地图"),
            );
            key_value_with_tooltip(
                ui,
                "锚点数",
                &settlement.anchors.len().to_string(),
                settlement_detail_tooltip("锚点数"),
            );
            key_value_with_tooltip(
                ui,
                "路线数",
                &settlement.routes.len().to_string(),
                settlement_detail_tooltip("路线数"),
            );
            key_value_with_tooltip(
                ui,
                "智能物体数",
                &settlement.smart_objects.len().to_string(),
                settlement_detail_tooltip("智能物体数"),
            );
            key_value_with_tooltip(
                ui,
                "最低值班守卫",
                &settlement.service_rules.min_guard_on_duty.to_string(),
                settlement_detail_tooltip("最低值班守卫"),
            );
        })
        .header_response
        .on_hover_text(
            "查看当前 life profile 绑定据点的结构摘要。这里展示地图、锚点、路线和 smart object 的引用规模。",
        );
    }
}

fn life_field_tooltip(label: &str) -> &'static str {
    match label {
        "据点" => "角色绑定的生活据点 ID。AI 会在这个据点内解析锚点、路线和服务规则。",
        "角色职责" => "角色在据点中的常驻职责。它会影响默认日程、行为倾向和可用目标。",
        "行为包" => {
            "角色引用的 AI 行为配置 ID，不是直接规则内容。AI 预览会按这个行为包计算 goal 和 action。"
        }
        "日程模板" => {
            "角色引用的日程模板 ID，不是具体时间表内容。它决定一天中各时段默认应执行什么生活块。"
        }
        "性格模板" => {
            "角色引用的性格模板 ID，不是直接数值。它会写入 AI blackboard，影响偏好和目标评分。"
        }
        "需求模板" => {
            "角色引用的需求模板 ID，不是直接状态值。它决定饥饿、休息等需求如何参与生活与 AI 决策。"
        }
        "智能物体访问" => {
            "角色引用的智能物体访问配置 ID。它决定角色优先访问哪些 smart object，以及是否允许回退到任意对象。"
        }
        "家锚点" => "角色在据点内的默认归属锚点。休息、回家或缺省定位时会优先使用它。",
        "执勤路线" => "角色引用的巡逻或执勤路线 ID。守卫、巡逻等行为会用它解析移动路径。",
        _ => "",
    }
}

fn settlement_detail_tooltip(label: &str) -> &'static str {
    match label {
        "地图" => "据点引用的地图资源 ID。角色生活与 AI 行为最终发生在这张地图上。",
        "锚点数" => "当前据点定义的锚点数量。家锚点、食堂锚点等都会从这里解析。",
        "路线数" => "当前据点定义的路线数量。巡逻、执勤或引导类行为会从这里取路线。",
        "智能物体数" => {
            "当前据点注册的 smart object 数量。进食、休息、娱乐、治疗等会在这些对象中选目标。"
        }
        "最低值班守卫" => {
            "据点服务规则要求的最低守卫人数。AI 会把它作为守卫类目标和警戒调度的输入。"
        }
        _ => "",
    }
}

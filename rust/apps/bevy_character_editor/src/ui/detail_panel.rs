//! 右侧详情面板。
//! 负责角色摘要、生活页、AI 页、外观页的页签路由和公共头部操作。

use bevy_egui::egui;
use game_data::{CharacterDefinition, SettlementId};
use game_editor::PreviewCameraController;

use crate::preview::{refresh_preview_state, reset_orbit_from_current_preview, selected_character};
use crate::state::{
    archetype_label, disposition_label, non_empty, npc_role_label, CharacterTab, EditorData,
    EditorUiState, PreviewState,
};

use super::ai_tab::render_ai_tab;
use super::appearance_tab::render_appearance_tab;
use super::common::{key_value, tab_button};

// 右侧详情区入口，统一组织页签切换和当前角色头部操作。
pub(crate) fn render_detail_panel(
    ui: &mut egui::Ui,
    data: &EditorData,
    ui_state: &mut EditorUiState,
    preview_state: &mut PreviewState,
    preview_camera: &mut PreviewCameraController,
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
            .on_hover_text("将预览相机重置到标准角色视角。")
            .clicked()
        {
            reset_orbit_from_current_preview(preview_state, preview_camera);
        }
        if ui
            .small_button("清空试装")
            .on_hover_text("清空所有临时试装槽位，仅显示角色基础外观。")
            .clicked()
        {
            ui_state.try_on.clear();
            refresh_preview_state(data, ui_state, preview_state, preview_camera, false);
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
                render_ai_tab(ui, character, data, ui_state, preview_state, preview_camera)
            }
            CharacterTab::Appearance => {
                render_appearance_tab(ui, character, data, ui_state, preview_state, preview_camera)
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
    key_value(ui, "据点", non_empty(&life.settlement_id));
    key_value(ui, "角色职责", npc_role_label(life.role));
    key_value(ui, "行为包", non_empty(&life.ai_behavior_profile_id));
    key_value(ui, "日程模板", non_empty(&life.schedule_profile_id));
    key_value(ui, "性格模板", non_empty(&life.personality_profile_id));
    key_value(ui, "需求模板", non_empty(&life.need_profile_id));
    key_value(
        ui,
        "智能物体访问",
        non_empty(&life.smart_object_access_profile_id),
    );
    key_value(ui, "家锚点", non_empty(&life.home_anchor));
    key_value(ui, "执勤路线", non_empty(&life.duty_route_id));

    if let Some(settlement) = data
        .settlements
        .get(&SettlementId(life.settlement_id.clone()))
    {
        ui.separator();
        ui.collapsing("据点引用详情", |ui| {
            key_value(ui, "地图", settlement.map_id.as_str());
            key_value(ui, "锚点数", &settlement.anchors.len().to_string());
            key_value(ui, "路线数", &settlement.routes.len().to_string());
            key_value(
                ui,
                "智能物体数",
                &settlement.smart_objects.len().to_string(),
            );
            key_value(
                ui,
                "最低值班守卫",
                &settlement.service_rules.min_guard_on_duty.to_string(),
            );
        });
    }
}

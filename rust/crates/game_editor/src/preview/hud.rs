use bevy::prelude::Vec3;
use bevy_egui::egui;

#[derive(Debug, Clone, Copy)]
pub struct ModelPreviewHud<'a> {
    pub title: &'a str,
    pub size: Option<Vec3>,
    pub status: Option<&'a str>,
    pub ground_visible: bool,
    pub pivot_visible: bool,
}

#[derive(Debug, Clone, Copy, Default)]
pub struct ModelPreviewHudResponse {
    pub hovered: bool,
    pub toggle_ground: bool,
    pub toggle_pivot: bool,
}

pub fn render_model_preview_hud(
    ctx: &egui::Context,
    id: impl Into<egui::Id>,
    rect: egui::Rect,
    hud: ModelPreviewHud<'_>,
    extra_controls: impl FnOnce(&mut egui::Ui),
) -> ModelPreviewHudResponse {
    let mut response = ModelPreviewHudResponse::default();
    let area = egui::Area::new(id.into())
        .order(egui::Order::Foreground)
        .fixed_pos(rect.left_top() + egui::vec2(10.0, 10.0))
        .show(ctx, |ui| {
            egui::Frame::NONE
                .fill(egui::Color32::from_rgba_unmultiplied(18, 21, 28, 176))
                .corner_radius(6.0)
                .inner_margin(egui::Margin::symmetric(10, 8))
                .show(ui, |ui| {
                    ui.set_max_width(540.0);
                    ui.horizontal_wrapped(|ui| {
                        ui.label(
                            egui::RichText::new(hud.title)
                                .size(13.0)
                                .color(egui::Color32::from_rgb(228, 231, 238)),
                        );
                        ui.separator();
                        ui.label(
                            egui::RichText::new(size_label(hud.size))
                                .size(12.0)
                                .color(egui::Color32::from_rgb(174, 181, 194)),
                        );
                        if let Some(status) = hud.status.filter(|value| !value.trim().is_empty()) {
                            ui.separator();
                            ui.label(
                                egui::RichText::new(status)
                                    .size(12.0)
                                    .color(egui::Color32::from_rgb(220, 170, 72)),
                            );
                        }
                    });
                    ui.add_space(4.0);
                    ui.horizontal_wrapped(|ui| {
                        let mut ground_visible = hud.ground_visible;
                        if ui.checkbox(&mut ground_visible, "显示地面").changed() {
                            response.toggle_ground = true;
                        }
                        let mut pivot_visible = hud.pivot_visible;
                        if ui.checkbox(&mut pivot_visible, "显示 Pivot").changed() {
                            response.toggle_pivot = true;
                        }
                        extra_controls(ui);
                    });
                });
        });
    response.hovered = area.response.hovered();
    response
}

pub fn preview_size_label(size: Option<Vec3>) -> String {
    size_label(size)
}

fn size_label(size: Option<Vec3>) -> String {
    match size {
        Some(size) => format!("大小: {:.2} × {:.2} × {:.2}", size.x, size.y, size.z),
        None => "大小: -".to_string(),
    }
}

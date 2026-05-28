use bevy_egui::egui;

const TRUNCATION_SUFFIX: &str = ".....";
const MIN_ROW_HEIGHT: f32 = 24.0;

pub fn selectable_list_row(ui: &mut egui::Ui, selected: bool, label: &str) -> egui::Response {
    let width = ui.available_width();
    let height = ui.spacing().interact_size.y.max(MIN_ROW_HEIGHT);
    let (rect, response) = ui.allocate_exact_size(egui::vec2(width, height), egui::Sense::click());

    if ui.is_rect_visible(rect) {
        let visuals = ui.style().interact_selectable(&response, selected);
        ui.painter().rect(
            rect,
            visuals.corner_radius,
            visuals.bg_fill,
            visuals.bg_stroke,
            egui::StrokeKind::Middle,
        );

        let font_id = egui::TextStyle::Button.resolve(ui.style());
        let text_padding = ui.style().spacing.button_padding.x;
        let text_width = (rect.width() - text_padding * 2.0).max(0.0);
        let truncated = truncate_label_to_width(ui, label, &font_id, text_width);
        let text_pos = egui::pos2(rect.left() + text_padding, rect.center().y);
        ui.painter().text(
            text_pos,
            egui::Align2::LEFT_CENTER,
            truncated,
            font_id,
            visuals.text_color(),
        );
    }

    response
}

fn truncate_label_to_width(
    ui: &egui::Ui,
    label: &str,
    font_id: &egui::FontId,
    max_width: f32,
) -> String {
    if label.is_empty() || max_width <= 0.0 {
        return String::new();
    }

    if measure_text_width(ui, label, font_id) <= max_width {
        return label.to_string();
    }

    let suffix_width = measure_text_width(ui, TRUNCATION_SUFFIX, font_id);
    if suffix_width >= max_width {
        return TRUNCATION_SUFFIX.to_string();
    }

    let chars = label.chars().collect::<Vec<_>>();
    let mut low = 0usize;
    let mut high = chars.len();

    while low < high {
        let mid = (low + high + 1) / 2;
        let candidate = chars[..mid].iter().collect::<String>() + TRUNCATION_SUFFIX;
        if measure_text_width(ui, &candidate, font_id) <= max_width {
            low = mid;
        } else {
            high = mid - 1;
        }
    }

    let prefix = chars[..low].iter().collect::<String>();
    format!("{prefix}{TRUNCATION_SUFFIX}")
}

fn measure_text_width(ui: &egui::Ui, text: &str, font_id: &egui::FontId) -> f32 {
    ui.painter()
        .layout_no_wrap(text.to_string(), font_id.clone(), egui::Color32::WHITE)
        .size()
        .x
}

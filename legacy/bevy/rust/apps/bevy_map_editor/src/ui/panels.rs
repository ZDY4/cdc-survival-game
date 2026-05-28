use bevy::diagnostic::{DiagnosticsStore, FrameTimeDiagnosticsPlugin};
use bevy_egui::egui;
use game_data::{MapEditDiagnostic, MapEditDiagnosticSeverity, OverworldId};

use crate::state::{map_display_name, yes_no, EditorState, LibraryView};

pub(crate) fn editor_top_summary(editor: &EditorState) -> String {
    match editor.selected_view {
        LibraryView::Maps => {
            let Some(selected_map_id) = editor.selected_map_id.as_ref() else {
                return "Map: none".to_string();
            };
            let Some(doc) = editor.maps.get(selected_map_id) else {
                return format!("Map: {} (missing)", map_display_name(selected_map_id));
            };
            let diagnostic_count = doc.diagnostics.len();
            format!(
                "Map {} · {} x {} · levels {} · objects {} · dirty {} · diagnostics {}",
                map_display_name(doc.definition.id.as_str()),
                doc.definition.size.width,
                doc.definition.size.height,
                doc.definition.levels.len(),
                doc.definition.objects.len(),
                yes_no(doc.dirty),
                diagnostic_count
            )
        }
        LibraryView::Overworlds => {
            let Some(selected_overworld_id) = editor.selected_overworld_id.as_ref() else {
                return "Overworld: none".to_string();
            };
            let Some(definition) = editor
                .overworld_library
                .get(&OverworldId(selected_overworld_id.clone()))
            else {
                return format!("Overworld {} (missing)", selected_overworld_id);
            };
            format!(
                "Overworld {} · {} x {} · locations {}",
                definition.id.as_str(),
                definition.size.width,
                definition.size.height,
                definition.locations.len()
            )
        }
    }
}

pub(crate) fn current_fps_label(diagnostics: &DiagnosticsStore) -> String {
    let fps = diagnostics
        .get(&FrameTimeDiagnosticsPlugin::FPS)
        .and_then(|diagnostic| diagnostic.smoothed())
        .or_else(|| {
            diagnostics
                .get(&FrameTimeDiagnosticsPlugin::FPS)
                .and_then(|diagnostic| diagnostic.average())
        });
    fps.map(|value| format!("{value:.0}"))
        .unwrap_or_else(|| "--".to_string())
}

pub(crate) fn draw_diagnostic(ui: &mut egui::Ui, diagnostic: &MapEditDiagnostic) {
    let color = match diagnostic.severity {
        MapEditDiagnosticSeverity::Error => egui::Color32::from_rgb(242, 94, 94),
        MapEditDiagnosticSeverity::Warning => egui::Color32::from_rgb(233, 180, 64),
        MapEditDiagnosticSeverity::Info => egui::Color32::from_rgb(120, 180, 255),
    };
    ui.colored_label(
        color,
        format!("[{}] {}", diagnostic.code, diagnostic.message),
    );
}

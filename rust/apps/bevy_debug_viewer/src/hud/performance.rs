use bevy::diagnostic::{DiagnosticsStore, FrameTimeDiagnosticsPlugin};

use crate::profiling::ViewerSystemProfilerState;

use super::{kv, section};

pub(crate) fn current_fps_label(diagnostics: &DiagnosticsStore) -> String {
    let fps = diagnostics
        .get(&FrameTimeDiagnosticsPlugin::FPS)
        .and_then(|diagnostic| diagnostic.smoothed())
        .or_else(|| {
            diagnostics
                .get(&FrameTimeDiagnosticsPlugin::FPS)
                .and_then(|diagnostic| diagnostic.average())
        });
    format_fps_value(fps)
}

pub(crate) fn format_fps_value(fps: Option<f64>) -> String {
    fps.map(|fps| format!("{fps:.0}"))
        .unwrap_or_else(|| "--".to_string())
}

pub(crate) fn format_frame_timings_section(profiler: &ViewerSystemProfilerState) -> String {
    let mut lines = vec![kv(
        "Tracked Avg",
        format!("{:.2} ms", profiler.tracked_total_smoothed_ms()),
    )];
    let top_entries = profiler.top_entries(6);
    if top_entries.is_empty() {
        lines.push("No samples yet".to_string());
    } else {
        lines.extend(top_entries.into_iter().map(|entry| {
            format!(
                "{}: {:.2} ms (last {:.2})",
                entry.name, entry.smoothed_ms, entry.last_ms
            )
        }));
    }
    section("Frame Timings", lines)
}

pub(crate) fn format_performance_panel(profiler: &ViewerSystemProfilerState) -> String {
    section(
        "Performance",
        vec![
            kv(
                "Collection",
                if profiler.is_empty() {
                    "warming up"
                } else {
                    "active"
                },
            ),
            format_frame_timings_section(profiler),
        ],
    )
}

#[cfg(test)]
mod tests {
    use super::{
        current_fps_label, format_fps_value, format_frame_timings_section, format_performance_panel,
    };
    use crate::profiling::ViewerSystemProfilerState;
    use bevy::diagnostic::{Diagnostic, DiagnosticMeasurement, DiagnosticPath, DiagnosticsStore};
    use std::time::Instant;

    #[test]
    fn format_fps_value_formats_integer() {
        assert_eq!(format_fps_value(Some(60.3)), "60");
    }

    #[test]
    fn format_fps_value_falls_back_when_no_samples_exist() {
        assert_eq!(format_fps_value(None), "--");
    }

    #[test]
    fn frame_timings_section_renders_entries() {
        let mut profiler = ViewerSystemProfilerState::default();
        profiler.record_sample("tick_runtime", 1.5);

        let section = format_frame_timings_section(&profiler);

        assert!(section.contains("Frame Timings"));
        assert!(section.contains("tick_runtime"));
    }

    #[test]
    fn performance_panel_contains_totals() {
        let mut profiler = ViewerSystemProfilerState::default();
        profiler.record_sample("draw_world", 2.0);

        let panel = format_performance_panel(&profiler);

        assert!(panel.contains("Performance"));
        assert!(panel.contains("Collection"));
        assert!(panel.contains("Frame Timings"));
    }

    #[test]
    fn current_fps_label_prefers_smoothed_then_average() {
        let mut diagnostics = DiagnosticsStore::default();
        let mut diagnostic = Diagnostic::new(DiagnosticPath::new("fps"));
        diagnostic.add_measurement(DiagnosticMeasurement {
            time: Instant::now(),
            value: 60.0,
        });
        diagnostics.add(diagnostic);
        let label = current_fps_label(&diagnostics);
        assert_eq!(label, "60");
    }
}

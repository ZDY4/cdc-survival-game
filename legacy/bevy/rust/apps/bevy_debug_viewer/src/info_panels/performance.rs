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
    fps.map(|value| format!("{value:.0}"))
        .unwrap_or_else(|| "--".to_string())
}

pub(crate) fn format_performance_panel(profiler: &ViewerSystemProfilerState) -> String {
    let mut lines = vec![kv(
        "Collection",
        if profiler.is_empty() {
            "warming up"
        } else {
            "active"
        },
    )];

    let mut timing_lines = vec![kv(
        "Tracked Avg",
        format!("{:.2} ms", profiler.tracked_total_smoothed_ms()),
    )];
    let top_entries = profiler.top_entries(6);
    if top_entries.is_empty() {
        timing_lines.push("No samples yet".to_string());
    } else {
        timing_lines.extend(top_entries.into_iter().map(|entry| {
            format!(
                "{}: {:.2} ms (last {:.2})",
                entry.name, entry.smoothed_ms, entry.last_ms
            )
        }));
    }
    lines.push(section("Frame Timings", timing_lines));

    section("Performance", lines)
}

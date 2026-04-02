use crate::state::{HudEventCategory, HudEventFilter, ViewerEventEntry, ViewerRuntimeState};

use super::{kv, section};

fn event_badge(category: HudEventCategory) -> &'static str {
    match category {
        HudEventCategory::Combat => "COMBAT",
        HudEventCategory::Interaction => "INTERACT",
        HudEventCategory::World => "WORLD",
    }
}

pub(crate) fn event_matches_filter(event: &ViewerEventEntry, filter: HudEventFilter) -> bool {
    match filter {
        HudEventFilter::All => true,
        HudEventFilter::Combat => event.category == HudEventCategory::Combat,
        HudEventFilter::Interaction => event.category == HudEventCategory::Interaction,
        HudEventFilter::World => event.category == HudEventCategory::World,
    }
}

pub(crate) fn format_events_panel(
    runtime_state: &ViewerRuntimeState,
    event_filter: HudEventFilter,
) -> String {
    let events: Vec<String> = runtime_state
        .recent_events
        .iter()
        .filter(|entry| event_matches_filter(entry, event_filter))
        .rev()
        .take(20)
        .map(|entry| {
            format!(
                "{} · t={} · {}",
                event_badge(entry.category),
                entry.turn_index,
                entry.text
            )
        })
        .collect::<Vec<_>>()
        .into_iter()
        .rev()
        .collect();

    section(
        "Events",
        if events.is_empty() {
            vec![kv("Filter", event_filter.label()), kv("Visible", 0)]
        } else {
            std::iter::once(kv("Filter", event_filter.label()))
                .chain(std::iter::once(kv("Visible", events.len())))
                .chain(events)
                .collect()
        },
    )
}

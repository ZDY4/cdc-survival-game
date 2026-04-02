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

pub(crate) fn format_event_line(entry: &ViewerEventEntry) -> String {
    format!(
        "{} · t={} · {}",
        event_badge(entry.category),
        entry.turn_index,
        entry.text
    )
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
        .map(format_event_line)
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

#[cfg(test)]
mod tests {
    use super::{event_matches_filter, format_event_line};
    use crate::state::{HudEventCategory, HudEventFilter, ViewerEventEntry, ViewerHudPage};

    #[test]
    fn event_matches_filter_respects_categories() {
        let combat = ViewerEventEntry {
            category: HudEventCategory::Combat,
            turn_index: 3,
            text: "combat".to_string(),
        };
        assert!(event_matches_filter(&combat, HudEventFilter::Combat));
        assert!(!event_matches_filter(&combat, HudEventFilter::Interaction));

        let interaction = ViewerEventEntry {
            category: HudEventCategory::Interaction,
            turn_index: 2,
            text: "interaction".to_string(),
        };
        assert_eq!(interaction.category, HudEventCategory::Interaction);
        assert!(event_matches_filter(&interaction, HudEventFilter::All));
    }

    #[test]
    fn footer_hint_contains_global_shortcuts_and_page_specific_action() {
        let overview_hint = crate::hud::footer::footer_hint(ViewerHudPage::Overview);
        let events_hint = crate::hud::footer::footer_hint(ViewerHudPage::Events);
        let perf_hint = crate::hud::footer::footer_hint(ViewerHudPage::Performance);

        assert!(overview_hint.contains("F1-7"));
        assert!(events_hint.contains("[ / ]"));
        assert!(perf_hint.contains("仅当前页统计函数耗时"));
    }

    #[test]
    fn format_event_line_shows_turn_and_text() {
        let entry = ViewerEventEntry {
            category: HudEventCategory::World,
            turn_index: 1,
            text: "test".to_string(),
        };
        let line = format_event_line(&entry);
        assert!(line.contains("t=1"));
        assert!(line.contains("test"));
    }
}

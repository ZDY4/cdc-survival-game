//! 信息面板状态：定义信息页签、启用状态和信息面板相关 ECS 标记组件。

use bevy::prelude::*;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub(crate) enum ViewerHudPage {
    #[default]
    Overview,
    Selection,
    SelectedActor,
    World,
    Interaction,
    TurnSys,
    Events,
    Ai,
    Performance,
}

impl ViewerHudPage {
    pub(crate) const ALL: [Self; 9] = [
        Self::Overview,
        Self::Selection,
        Self::SelectedActor,
        Self::World,
        Self::Interaction,
        Self::TurnSys,
        Self::Events,
        Self::Ai,
        Self::Performance,
    ];

    pub(crate) fn title(self) -> &'static str {
        match self {
            Self::Overview => "Overview",
            Self::Selection => "Selection",
            Self::SelectedActor => "Selected Actor",
            Self::World => "World",
            Self::Interaction => "Interaction",
            Self::TurnSys => "Turn System",
            Self::Events => "Events",
            Self::Ai => "AI",
            Self::Performance => "Performance",
        }
    }

    pub(crate) fn tab_label(self) -> &'static str {
        match self {
            Self::Overview => "Overview",
            Self::Selection => "Select",
            Self::SelectedActor => "Actor",
            Self::World => "World",
            Self::Interaction => "Interact",
            Self::TurnSys => "Turn",
            Self::Events => "Events",
            Self::Ai => "AI",
            Self::Performance => "Perf",
        }
    }

    pub(crate) fn console_name(self) -> &'static str {
        match self {
            Self::Overview => "overview",
            Self::Selection => "selection",
            Self::SelectedActor => "actor",
            Self::World => "world",
            Self::Interaction => "interaction",
            Self::TurnSys => "turn_sys",
            Self::Events => "events",
            Self::Ai => "ai",
            Self::Performance => "performance",
        }
    }

    pub(crate) fn from_console_name(name: &str) -> Option<Self> {
        match name {
            "overview" => Some(Self::Overview),
            "selection" => Some(Self::Selection),
            "actor" => Some(Self::SelectedActor),
            "world" => Some(Self::World),
            "interaction" => Some(Self::Interaction),
            "turn_sys" => Some(Self::TurnSys),
            "events" => Some(Self::Events),
            "ai" => Some(Self::Ai),
            "performance" => Some(Self::Performance),
            _ => None,
        }
    }
}

#[derive(Resource, Debug, Clone, Default)]
pub(crate) struct ViewerInfoPanelState {
    pub enabled_pages: Vec<ViewerHudPage>,
    pub active_page: Option<ViewerHudPage>,
}

impl ViewerInfoPanelState {
    pub(crate) fn is_empty(&self) -> bool {
        self.enabled_pages.is_empty() || self.active_page.is_none()
    }

    pub(crate) fn active_page(&self) -> Option<ViewerHudPage> {
        self.active_page
    }

    pub(crate) fn enabled_pages(&self) -> &[ViewerHudPage] {
        &self.enabled_pages
    }

    pub(crate) fn is_enabled(&self, page: ViewerHudPage) -> bool {
        self.enabled_pages.contains(&page)
    }

    pub(crate) fn set_active(&mut self, page: ViewerHudPage) -> bool {
        if self.is_enabled(page) {
            self.active_page = Some(page);
            true
        } else {
            false
        }
    }

    pub(crate) fn toggle(&mut self, page: ViewerHudPage) -> bool {
        if self.is_enabled(page) {
            self.disable(page);
            false
        } else {
            self.enable(page);
            true
        }
    }

    pub(crate) fn cycle_next(&mut self) -> Option<ViewerHudPage> {
        let active = self.active_page?;
        let current_index = self.enabled_pages.iter().position(|page| *page == active)?;
        let next_index = (current_index + 1) % self.enabled_pages.len();
        let next = self.enabled_pages[next_index];
        self.active_page = Some(next);
        Some(next)
    }

    pub(crate) fn cycle_previous(&mut self) -> Option<ViewerHudPage> {
        let active = self.active_page?;
        let current_index = self.enabled_pages.iter().position(|page| *page == active)?;
        let previous_index = if current_index == 0 {
            self.enabled_pages.len().saturating_sub(1)
        } else {
            current_index - 1
        };
        let previous = self.enabled_pages[previous_index];
        self.active_page = Some(previous);
        Some(previous)
    }

    fn enable(&mut self, page: ViewerHudPage) {
        self.enabled_pages.push(page);
        self.enabled_pages.sort_by_key(|enabled| {
            ViewerHudPage::ALL
                .iter()
                .position(|candidate| candidate == enabled)
                .unwrap_or(usize::MAX)
        });
        self.active_page = Some(page);
    }

    fn disable(&mut self, page: ViewerHudPage) {
        let removed_index = self
            .enabled_pages
            .iter()
            .position(|enabled| *enabled == page);
        self.enabled_pages.retain(|enabled| *enabled != page);

        if self.enabled_pages.is_empty() {
            self.active_page = None;
            return;
        }

        if self.active_page == Some(page) {
            let next_index = removed_index
                .map(|index| index.min(self.enabled_pages.len().saturating_sub(1)))
                .unwrap_or(0);
            self.active_page = self.enabled_pages.get(next_index).copied();
        }
    }
}

#[derive(Component)]
pub(crate) struct InfoPanelText;

#[derive(Component)]
pub(crate) struct InfoPanelFooterText;

#[derive(Component)]
pub(crate) struct InfoPanelTabBarRoot;

#[derive(Component, Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct InfoPanelTabButton {
    pub page: ViewerHudPage,
}

#[derive(Component)]
pub(crate) struct FpsOverlayText;

#[derive(Component)]
pub(crate) struct FreeObserveIndicatorRoot;

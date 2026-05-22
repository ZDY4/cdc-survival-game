use super::*;

#[derive(Resource, Debug, Clone, PartialEq, Eq)]
pub(crate) struct ViewerDebugPanelState {
    pub is_open: bool,
    pub active_tab: DebugPanelTab,
    pub selected_item_id: Option<u32>,
    pub item_filter: String,
    pub quantity_input: String,
    pub item_dropdown_open: bool,
    pub text_focus: DebugPanelTextFocus,
    pub last_feedback: Option<DebugPanelFeedback>,
}

impl Default for ViewerDebugPanelState {
    fn default() -> Self {
        Self {
            is_open: false,
            active_tab: DebugPanelTab::Console,
            selected_item_id: None,
            item_filter: String::new(),
            quantity_input: "1".to_string(),
            item_dropdown_open: false,
            text_focus: DebugPanelTextFocus::None,
            last_feedback: None,
        }
    }
}

impl ViewerDebugPanelState {
    pub(super) fn close(&mut self) {
        self.is_open = false;
        self.item_dropdown_open = false;
        self.text_focus = DebugPanelTextFocus::None;
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub(crate) enum DebugPanelTab {
    #[default]
    Console,
    Cheats,
}

impl DebugPanelTab {
    pub(super) const ALL: [Self; 2] = [Self::Console, Self::Cheats];

    pub(super) fn label(self) -> &'static str {
        match self {
            Self::Console => "Console",
            Self::Cheats => "Cheats",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub(crate) enum DebugPanelTextFocus {
    #[default]
    None,
    ItemFilter,
    Quantity,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct DebugPanelFeedback {
    pub is_error: bool,
    pub text: String,
}

impl From<ConsoleFeedback> for DebugPanelFeedback {
    fn from(feedback: ConsoleFeedback) -> Self {
        Self {
            is_error: feedback.is_error,
            text: feedback.text,
        }
    }
}

#[derive(Component)]
pub(crate) struct DebugPanelRoot;

#[derive(Component)]
pub(crate) struct DebugPanelBodyRoot;

#[derive(Component, Debug, Clone, PartialEq, Eq)]
pub(crate) enum DebugPanelButtonAction {
    SelectTab(DebugPanelTab),
    ExecuteConsoleCommand(&'static str),
    ToggleItemDropdown,
    FocusItemFilter,
    SelectItem(u32),
    FocusQuantity,
    AddItem,
}

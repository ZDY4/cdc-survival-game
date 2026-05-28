use super::super::{InteractionKindSpec, InteractionKindValidation, InteractionOptionKind};

const TARGET_REQUIRED: InteractionKindValidation = InteractionKindValidation {
    requires_item_id: false,
    requires_target_id: true,
};

pub(super) const ENTER_SUBSCENE_SPEC: InteractionKindSpec = InteractionKindSpec {
    kind: InteractionOptionKind::EnterSubscene,
    default_option_id: "enter_subscene",
    default_display_name: "进入场景",
    default_priority: 860,
    legacy_names: &["enter_subscene"],
    is_scene_transition: true,
    validation: TARGET_REQUIRED,
};

pub(super) const ENTER_OVERWORLD_SPEC: InteractionKindSpec = InteractionKindSpec {
    kind: InteractionOptionKind::EnterOverworld,
    default_option_id: "enter_overworld",
    default_display_name: "返回大地图",
    default_priority: 850,
    legacy_names: &["enter_overworld"],
    is_scene_transition: true,
    validation: TARGET_REQUIRED,
};

pub(super) const EXIT_TO_OUTDOOR_SPEC: InteractionKindSpec = InteractionKindSpec {
    kind: InteractionOptionKind::ExitToOutdoor,
    default_option_id: "exit_to_outdoor",
    default_display_name: "离开",
    default_priority: 850,
    legacy_names: &["exit_to_outdoor"],
    is_scene_transition: true,
    validation: TARGET_REQUIRED,
};

pub(super) const ENTER_OUTDOOR_LOCATION_SPEC: InteractionKindSpec = InteractionKindSpec {
    kind: InteractionOptionKind::EnterOutdoorLocation,
    default_option_id: "enter_outdoor_location",
    default_display_name: "进入地点",
    default_priority: 840,
    legacy_names: &["enter_outdoor_location"],
    is_scene_transition: true,
    validation: TARGET_REQUIRED,
};

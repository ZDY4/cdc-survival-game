use super::super::{InteractionKindSpec, InteractionKindValidation, InteractionOptionKind};

pub(super) const SPEC: InteractionKindSpec = InteractionKindSpec {
    kind: InteractionOptionKind::Pickup,
    default_option_id: "pickup",
    default_display_name: "拾取",
    default_priority: 900,
    legacy_names: &["pickup"],
    is_scene_transition: false,
    validation: InteractionKindValidation {
        requires_item_id: true,
        requires_target_id: false,
    },
};

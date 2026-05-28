use super::super::{InteractionKindSpec, InteractionKindValidation, InteractionOptionKind};

pub(super) const SPEC: InteractionKindSpec = InteractionKindSpec {
    kind: InteractionOptionKind::Talk,
    default_option_id: "talk",
    default_display_name: "对话",
    default_priority: 800,
    legacy_names: &["talk"],
    is_scene_transition: false,
    validation: InteractionKindValidation::NONE,
};

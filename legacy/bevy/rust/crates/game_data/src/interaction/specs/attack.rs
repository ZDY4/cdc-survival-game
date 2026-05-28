use super::super::{InteractionKindSpec, InteractionKindValidation, InteractionOptionKind};

pub(super) const SPEC: InteractionKindSpec = InteractionKindSpec {
    kind: InteractionOptionKind::Attack,
    default_option_id: "attack",
    default_display_name: "攻击",
    default_priority: 700,
    legacy_names: &["attack"],
    is_scene_transition: false,
    validation: InteractionKindValidation::NONE,
};

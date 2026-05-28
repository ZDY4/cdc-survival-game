use super::super::{InteractionKindSpec, InteractionKindValidation, InteractionOptionKind};

pub(super) const SPEC: InteractionKindSpec = InteractionKindSpec {
    kind: InteractionOptionKind::Wait,
    default_option_id: "wait",
    default_display_name: "等待",
    default_priority: 950,
    legacy_names: &["wait"],
    is_scene_transition: false,
    validation: InteractionKindValidation::NONE,
};

use super::super::{InteractionKindSpec, InteractionKindValidation, InteractionOptionKind};

pub(super) const SPEC: InteractionKindSpec = InteractionKindSpec {
    kind: InteractionOptionKind::OpenContainer,
    default_option_id: "open_container",
    default_display_name: "打开容器",
    default_priority: 850,
    legacy_names: &["open_container", "container"],
    is_scene_transition: false,
    validation: InteractionKindValidation::NONE,
};

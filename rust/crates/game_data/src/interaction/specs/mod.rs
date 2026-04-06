mod attack;
mod door;
mod pickup;
mod scene_transition;
mod talk;
mod wait;

use super::{InteractionKindSpec, InteractionOptionKind};

static SPECS: [InteractionKindSpec; 12] = [
    wait::SPEC,
    talk::SPEC,
    attack::SPEC,
    pickup::SPEC,
    door::OPEN_SPEC,
    door::CLOSE_SPEC,
    door::UNLOCK_SPEC,
    door::PICK_LOCK_SPEC,
    scene_transition::ENTER_SUBSCENE_SPEC,
    scene_transition::ENTER_OVERWORLD_SPEC,
    scene_transition::EXIT_TO_OUTDOOR_SPEC,
    scene_transition::ENTER_OUTDOOR_LOCATION_SPEC,
];

pub fn all_interaction_kind_specs() -> &'static [InteractionKindSpec] {
    &SPECS
}

pub fn interaction_kind_spec(kind: InteractionOptionKind) -> &'static InteractionKindSpec {
    all_interaction_kind_specs()
        .iter()
        .find(|spec| spec.kind == kind)
        .unwrap_or_else(|| panic!("missing interaction kind spec for {kind:?}"))
}

pub fn parse_legacy_interaction_kind(value: &str) -> Option<InteractionOptionKind> {
    let trimmed = value.trim();
    all_interaction_kind_specs()
        .iter()
        .find(|spec| spec.legacy_names.iter().any(|name| *name == trimmed))
        .map(|spec| spec.kind)
}

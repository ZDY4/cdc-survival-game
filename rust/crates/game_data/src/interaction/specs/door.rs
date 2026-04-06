use super::super::{InteractionKindSpec, InteractionKindValidation, InteractionOptionKind};

const NO_VALIDATION: InteractionKindValidation = InteractionKindValidation::NONE;

pub(super) const OPEN_SPEC: InteractionKindSpec = InteractionKindSpec {
    kind: InteractionOptionKind::OpenDoor,
    default_option_id: "open_door",
    default_display_name: "开门",
    default_priority: 880,
    legacy_names: &["open_door"],
    is_scene_transition: false,
    validation: NO_VALIDATION,
};

pub(super) const CLOSE_SPEC: InteractionKindSpec = InteractionKindSpec {
    kind: InteractionOptionKind::CloseDoor,
    default_option_id: "close_door",
    default_display_name: "关门",
    default_priority: 880,
    legacy_names: &["close_door"],
    is_scene_transition: false,
    validation: NO_VALIDATION,
};

pub(super) const UNLOCK_SPEC: InteractionKindSpec = InteractionKindSpec {
    kind: InteractionOptionKind::UnlockDoor,
    default_option_id: "unlock_door",
    default_display_name: "解锁",
    default_priority: 790,
    legacy_names: &["unlock_door"],
    is_scene_transition: false,
    validation: NO_VALIDATION,
};

pub(super) const PICK_LOCK_SPEC: InteractionKindSpec = InteractionKindSpec {
    kind: InteractionOptionKind::PickLockDoor,
    default_option_id: "pick_lock_door",
    default_display_name: "撬锁",
    default_priority: 780,
    legacy_names: &["pick_lock_door"],
    is_scene_transition: false,
    validation: NO_VALIDATION,
};

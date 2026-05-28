//! 地图交互对象的选项补全与校验辅助逻辑。

use crate::interaction::{
    default_display_name_for_kind, default_option_id_for_kind, default_priority_for_kind,
    interaction_kind_spec, parse_legacy_interaction_kind, InteractionOptionDefinition,
    InteractionOptionId, InteractionOptionKind,
};

use super::types::{default_interaction_distance, MapInteractiveProps, MapObjectDefinition};
use super::validation::MapDefinitionValidationError;

fn resolve_interactive_object_display_name(
    object: &MapObjectDefinition,
    interactive: &MapInteractiveProps,
) -> String {
    if !interactive.display_name.trim().is_empty() {
        return interactive.display_name.clone();
    }
    if let Some(container) = object.props.container.as_ref() {
        if !container.display_name.trim().is_empty() {
            return container.display_name.clone();
        }
    }
    object.object_id.clone()
}

pub(crate) fn resolve_interactive_object_options(
    object: &MapObjectDefinition,
    interactive: &MapInteractiveProps,
) -> Vec<InteractionOptionDefinition> {
    let options = interactive.resolved_options();
    if !options.is_empty() {
        return options;
    }
    let Some(_container) = object.props.container.as_ref() else {
        return Vec::new();
    };

    let mut option = InteractionOptionDefinition {
        kind: InteractionOptionKind::OpenContainer,
        display_name: resolve_interactive_object_display_name(object, interactive),
        interaction_distance: interactive
            .interaction_distance
            .max(default_interaction_distance()),
        priority: default_priority_for_kind(InteractionOptionKind::OpenContainer),
        ..InteractionOptionDefinition::default()
    };
    option.ensure_defaults();
    vec![option]
}

pub(crate) fn resolve_map_object_options(
    display_name: &str,
    interaction_distance: f32,
    interaction_kind: &str,
    target_id: Option<&str>,
    options: &[InteractionOptionDefinition],
) -> Vec<InteractionOptionDefinition> {
    if !options.is_empty() {
        let mut resolved = options.to_vec();
        for option in &mut resolved {
            option.ensure_defaults();
        }
        return resolved;
    }

    let Some(kind) = parse_legacy_interaction_kind(interaction_kind) else {
        return Vec::new();
    };

    let mut option = InteractionOptionDefinition {
        id: InteractionOptionId(default_option_id_for_kind(kind)),
        display_name: if display_name.trim().is_empty() {
            default_display_name_for_kind(kind).to_string()
        } else {
            display_name.to_string()
        },
        priority: default_priority_for_kind(kind),
        interaction_distance: interaction_distance.max(default_interaction_distance()),
        kind,
        target_id: target_id.unwrap_or_default().to_string(),
        ..InteractionOptionDefinition::default()
    };
    option.ensure_defaults();
    vec![option]
}

pub(crate) fn resolved_option_id(option: &InteractionOptionDefinition) -> String {
    if option.id.as_str().trim().is_empty() {
        default_option_id_for_kind(option.kind)
    } else {
        option.id.as_str().to_string()
    }
}

pub(crate) fn validate_interaction_option(
    object_id: &str,
    object_kind: &'static str,
    option: &InteractionOptionDefinition,
) -> Result<(), MapDefinitionValidationError> {
    let option_id = resolved_option_id(option);
    let spec = interaction_kind_spec(option.kind);

    if option.interaction_distance < 0.0 {
        return Err(MapDefinitionValidationError::InvalidInteractionDistance {
            object_id: object_id.to_string(),
            object_kind,
            option_id,
            distance: option.interaction_distance,
        });
    }

    if spec.validation.requires_item_id && option.item_id.trim().is_empty() {
        return Err(
            MapDefinitionValidationError::MissingInteractionPickupItemId {
                object_id: object_id.to_string(),
                object_kind,
                option_id,
            },
        );
    }

    if spec.validation.requires_target_id
        && option.target_id.trim().is_empty()
        && option.target_map_id.trim().is_empty()
    {
        return Err(MapDefinitionValidationError::MissingInteractionTargetId {
            object_id: object_id.to_string(),
            object_kind,
            option_id,
        });
    }

    Ok(())
}

use super::*;

pub(super) fn runtime_protocol_error(operation: &str, error: String) -> ProtocolError {
    let stable = stable_runtime_error_code(&error).unwrap_or("failed");
    protocol_error(format!("{operation}_{stable}"), error, false)
}

pub(super) fn stable_runtime_error_code(error: &str) -> Option<&str> {
    let prefix = error.split(':').next().unwrap_or(error).trim();
    if prefix.is_empty() {
        return None;
    }
    if prefix
        .chars()
        .all(|ch| ch.is_ascii_lowercase() || ch.is_ascii_digit() || ch == '_')
    {
        Some(prefix)
    } else {
        None
    }
}

pub(super) fn require_items(
    definitions: ServerProtocolDefinitions<'_>,
) -> Result<&ItemLibrary, ProtocolError> {
    definitions.items.ok_or_else(|| {
        protocol_error(
            "missing_item_library",
            "server protocol handler requires item definitions for this message",
            false,
        )
    })
}

pub(super) fn require_skills(
    definitions: ServerProtocolDefinitions<'_>,
) -> Result<&SkillLibrary, ProtocolError> {
    definitions.skills.ok_or_else(|| {
        protocol_error(
            "missing_skill_library",
            "server protocol handler requires skill definitions for this message",
            false,
        )
    })
}

pub(super) fn require_recipes(
    definitions: ServerProtocolDefinitions<'_>,
) -> Result<&RecipeLibrary, ProtocolError> {
    definitions.recipes.ok_or_else(|| {
        protocol_error(
            "missing_recipe_library",
            "server protocol handler requires recipe definitions for this message",
            false,
        )
    })
}

pub(super) fn require_shops(
    definitions: ServerProtocolDefinitions<'_>,
) -> Result<&ShopLibrary, ProtocolError> {
    definitions.shops.ok_or_else(|| {
        protocol_error(
            "missing_shop_library",
            "server protocol handler requires shop definitions for this message",
            false,
        )
    })
}

pub(super) fn economy_protocol_error(operation: &str, error: EconomyRuntimeError) -> ProtocolError {
    let code = match error {
        EconomyRuntimeError::UnknownActor { .. } => "unknown_actor",
        EconomyRuntimeError::ActionRejected { ref reason } => reason.as_str(),
        EconomyRuntimeError::UnknownItem { .. } => "unknown_item",
        EconomyRuntimeError::UnknownSkill { .. } => "unknown_skill",
        EconomyRuntimeError::UnknownRecipe { .. } => "unknown_recipe",
        EconomyRuntimeError::UnknownShop { .. } => "unknown_shop",
        EconomyRuntimeError::UnknownContainer { .. } => "unknown_container",
        EconomyRuntimeError::InvalidCount { .. } => "invalid_count",
        EconomyRuntimeError::NotEnoughItems { .. } => "not_enough_items",
        EconomyRuntimeError::NotEnoughMoney { .. } => "not_enough_money",
        EconomyRuntimeError::ShopInventoryInsufficient { .. } => "shop_inventory_insufficient",
        EconomyRuntimeError::ShopOutOfMoney { .. } => "shop_out_of_money",
        EconomyRuntimeError::ContainerInventoryInsufficient { .. } => {
            "container_inventory_insufficient"
        }
        EconomyRuntimeError::InventoryOverCapacity { .. } => "inventory_over_capacity",
        EconomyRuntimeError::SkillPrerequisiteMissing { .. } => "skill_prerequisite_missing",
        EconomyRuntimeError::SkillAttributeRequirementMissing { .. } => {
            "skill_attribute_requirement_missing"
        }
        EconomyRuntimeError::MissingSkillPoints { .. } => "missing_skill_points",
        EconomyRuntimeError::SkillAlreadyMaxed { .. } => "skill_already_maxed",
        EconomyRuntimeError::ItemNotEquippable { .. } => "item_not_equippable",
        EconomyRuntimeError::InvalidEquipmentSlot { .. } => "invalid_equipment_slot",
        EconomyRuntimeError::ItemLevelRequirementMissing { .. } => "item_level_requirement_missing",
        EconomyRuntimeError::EmptyEquipmentSlot { .. } => "empty_equipment_slot",
        EconomyRuntimeError::ItemNotWeapon { .. } => "item_not_weapon",
        EconomyRuntimeError::WeaponDoesNotUseAmmo { .. } => "weapon_does_not_use_ammo",
        EconomyRuntimeError::NotEnoughAmmo { .. } => "not_enough_ammo",
        EconomyRuntimeError::RecipeLocked { .. } => "recipe_locked",
        EconomyRuntimeError::MissingRecipeMaterials { .. } => "missing_recipe_materials",
        EconomyRuntimeError::MissingRecipeTools { .. } => "missing_recipe_tools",
        EconomyRuntimeError::MissingRecipeSkills { .. } => "missing_recipe_skills",
        EconomyRuntimeError::MissingRecipeStation { .. } => "missing_recipe_station",
        EconomyRuntimeError::MissingRecipeUnlock { .. } => "missing_recipe_unlock",
        EconomyRuntimeError::UnsupportedRepairRecipe { .. } => "unsupported_repair_recipe",
    };
    protocol_error(format!("{operation}_{code}"), error.to_string(), false)
}

pub(super) fn protocol_error(
    code: impl Into<String>,
    message: impl Into<String>,
    retryable: bool,
) -> ProtocolError {
    ProtocolError {
        code: code.into(),
        message: message.into(),
        retryable,
    }
}

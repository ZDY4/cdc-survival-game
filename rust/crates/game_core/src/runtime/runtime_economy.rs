use super::*;

impl SimulationRuntime {
    pub fn economy(&self) -> &HeadlessEconomyRuntime {
        self.simulation.economy()
    }

    pub fn economy_mut(&mut self) -> &mut HeadlessEconomyRuntime {
        self.simulation.economy_mut()
    }

    pub fn equip_item(
        &mut self,
        actor_id: ActorId,
        item_id: u32,
        target_slot: Option<&str>,
        items: &ItemLibrary,
    ) -> Result<Option<u32>, EconomyRuntimeError> {
        let target_slot = target_slot.map(str::to_string);
        self.run_ap_action(
            actor_id,
            ActionType::Item,
            None,
            economy_action_error,
            move |simulation| {
                simulation.economy_mut().equip_item(
                    actor_id,
                    item_id,
                    target_slot.as_deref(),
                    items,
                )
            },
        )
    }

    pub fn unequip_item(
        &mut self,
        actor_id: ActorId,
        slot: &str,
    ) -> Result<u32, EconomyRuntimeError> {
        let slot = slot.to_string();
        self.run_ap_action(
            actor_id,
            ActionType::Item,
            None,
            economy_action_error,
            move |simulation| simulation.economy_mut().unequip_item(actor_id, &slot),
        )
    }

    pub fn reload_equipped_weapon(
        &mut self,
        actor_id: ActorId,
        slot: &str,
        items: &ItemLibrary,
    ) -> Result<i32, EconomyRuntimeError> {
        let slot = slot.to_string();
        self.run_ap_action(
            actor_id,
            ActionType::Item,
            None,
            economy_action_error,
            move |simulation| {
                simulation
                    .economy_mut()
                    .reload_equipped_weapon(actor_id, &slot, items)
            },
        )
    }

    pub fn learn_skill(
        &mut self,
        actor_id: ActorId,
        skill_id: &str,
        skills: &SkillLibrary,
    ) -> Result<i32, EconomyRuntimeError> {
        let skill_id = skill_id.to_string();
        self.run_ap_action(
            actor_id,
            ActionType::Item,
            None,
            economy_action_error,
            move |simulation| {
                simulation
                    .economy_mut()
                    .learn_skill(actor_id, &skill_id, skills)
            },
        )
    }

    pub fn craft_recipe(
        &mut self,
        actor_id: ActorId,
        recipe_id: &str,
        recipes: &RecipeLibrary,
        items: &ItemLibrary,
    ) -> Result<CraftOutcome, EconomyRuntimeError> {
        let recipe_id = recipe_id.to_string();
        self.run_ap_action(
            actor_id,
            ActionType::Item,
            None,
            economy_action_error,
            move |simulation| {
                simulation
                    .economy_mut()
                    .craft_recipe(actor_id, &recipe_id, recipes, items)
            },
        )
    }

    pub fn buy_item_from_shop(
        &mut self,
        actor_id: ActorId,
        shop_id: &str,
        item_id: u32,
        count: i32,
        items: &ItemLibrary,
    ) -> Result<TradeOutcome, EconomyRuntimeError> {
        let shop_id = shop_id.to_string();
        self.run_ap_action(
            actor_id,
            ActionType::Item,
            None,
            economy_action_error,
            move |simulation| {
                simulation
                    .economy_mut()
                    .buy_item_from_shop(actor_id, &shop_id, item_id, count, items)
            },
        )
    }

    pub fn sell_item_to_shop(
        &mut self,
        actor_id: ActorId,
        shop_id: &str,
        item_id: u32,
        count: i32,
        items: &ItemLibrary,
    ) -> Result<TradeOutcome, EconomyRuntimeError> {
        let shop_id = shop_id.to_string();
        self.run_ap_action(
            actor_id,
            ActionType::Item,
            None,
            economy_action_error,
            move |simulation| {
                simulation
                    .economy_mut()
                    .sell_item_to_shop(actor_id, &shop_id, item_id, count, items)
            },
        )
    }

    pub fn sell_equipped_item_to_shop(
        &mut self,
        actor_id: ActorId,
        shop_id: &str,
        slot_id: &str,
        items: &ItemLibrary,
    ) -> Result<TradeOutcome, EconomyRuntimeError> {
        let shop_id = shop_id.to_string();
        let slot_id = slot_id.to_string();
        self.run_ap_action(
            actor_id,
            ActionType::Item,
            None,
            economy_action_error,
            move |simulation| {
                simulation.economy_mut().sell_equipped_item_to_shop(
                    actor_id,
                    &shop_id,
                    &slot_id,
                    items,
                )
            },
        )
    }

    pub fn drop_item_to_ground(
        &mut self,
        actor_id: ActorId,
        item_id: u32,
        count: i32,
        _items: &ItemLibrary,
    ) -> Result<DropItemOutcome, String> {
        self.run_ap_action(
            actor_id,
            ActionType::Item,
            None,
            string_action_error,
            move |simulation| simulation.drop_item_to_ground(actor_id, item_id, count),
        )
    }

    pub fn drop_equipped_item_to_ground(
        &mut self,
        actor_id: ActorId,
        slot: &str,
        _items: &ItemLibrary,
    ) -> Result<DropItemOutcome, String> {
        let slot = slot.to_string();
        self.run_ap_action(
            actor_id,
            ActionType::Item,
            None,
            string_action_error,
            move |simulation| simulation.drop_equipped_item_to_ground(actor_id, &slot),
        )
    }

    pub fn move_equipped_item(
        &mut self,
        actor_id: ActorId,
        from_slot: &str,
        to_slot: &str,
        items: &ItemLibrary,
    ) -> Result<(), EconomyRuntimeError> {
        let from_slot = from_slot.to_string();
        let to_slot = to_slot.to_string();
        self.run_ap_action(
            actor_id,
            ActionType::Item,
            None,
            economy_action_error,
            move |simulation| {
                simulation
                    .economy_mut()
                    .move_equipped_item(actor_id, &from_slot, &to_slot, items)
            },
        )
    }

    pub fn clear_actor_loadout(&mut self, actor_id: ActorId) -> Result<(), EconomyRuntimeError> {
        self.run_ap_action(
            actor_id,
            ActionType::Item,
            None,
            economy_action_error,
            move |simulation| simulation.economy_mut().clear_actor_loadout(actor_id),
        )
    }

    pub fn move_inventory_item_before(
        &mut self,
        actor_id: ActorId,
        item_id: u32,
        before_item_id: Option<u32>,
    ) -> Result<(), EconomyRuntimeError> {
        self.simulation
            .economy_mut()
            .move_inventory_item_before(actor_id, item_id, before_item_id)
    }

    pub fn allocate_attribute_point(
        &mut self,
        actor_id: ActorId,
        attribute: &str,
    ) -> Result<i32, String> {
        self.simulation
            .allocate_attribute_point(actor_id, attribute)
    }

    pub fn get_actor_resource(&self, actor_id: ActorId, resource: &str) -> f32 {
        self.simulation.actor_resource(actor_id, resource)
    }

    pub fn set_actor_resource(&mut self, actor_id: ActorId, resource: &str, value: f32) {
        self.simulation
            .set_actor_resource(actor_id, resource, value);
    }

    pub fn get_actor_combat_attribute(&self, actor_id: ActorId, attribute: &str) -> f32 {
        self.simulation.actor_combat_attribute(actor_id, attribute)
    }

    pub fn get_actor_max_hit_points(&self, actor_id: ActorId) -> f32 {
        self.simulation.max_hit_points(actor_id)
    }

    pub fn use_item(
        &mut self,
        actor_id: ActorId,
        item_id: u32,
        items: &ItemLibrary,
        effects: &EffectLibrary,
    ) -> Result<String, String> {
        let definition = items
            .get(item_id)
            .ok_or_else(|| format!("unknown_item:{item_id}"))?;
        let Some(ItemFragment::Usable {
            consume_on_use,
            effect_ids,
            ..
        }) = definition
            .fragments
            .iter()
            .find(|fragment| matches!(fragment, ItemFragment::Usable { .. }))
        else {
            return Err(format!("item_not_usable:{item_id}"));
        };

        if self
            .simulation
            .economy()
            .inventory_count(actor_id, item_id)
            .unwrap_or(0)
            <= 0
        {
            return Err(format!("item_missing:{item_id}"));
        }

        let effect_ids = effect_ids.clone();
        let item_name = definition.name.clone();
        let consume_on_use = *consume_on_use;

        self.run_ap_action(
            actor_id,
            ActionType::Item,
            None,
            string_action_error,
            move |simulation| {
                for effect_id in &effect_ids {
                    let Some(effect) = effects.get(effect_id) else {
                        continue;
                    };
                    if let Some(gameplay_effect) = effect.gameplay_effect.as_ref() {
                        for (resource, delta) in &gameplay_effect.resource_deltas {
                            let runtime_resource = match resource.as_str() {
                                "health" => "hp",
                                other => other,
                            };
                            let current = simulation.actor_resource(actor_id, runtime_resource);
                            let max_value = if runtime_resource == "hp" {
                                simulation.max_hit_points(actor_id)
                            } else {
                                f32::MAX
                            };
                            simulation.set_actor_resource(
                                actor_id,
                                runtime_resource,
                                (current + *delta).clamp(0.0, max_value),
                            );
                        }
                    }
                }

                if consume_on_use {
                    simulation
                        .economy_mut()
                        .remove_item(actor_id, item_id, 1)
                        .map_err(|error| error.to_string())?;
                }

                Ok(item_name)
            },
        )
    }
}

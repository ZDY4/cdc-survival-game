use std::collections::{BTreeMap, BTreeSet};

use bevy_ecs::prelude::*;
use game_data::SettlementLibrary;

#[derive(Resource, Debug, Clone, PartialEq, Eq, Default)]
pub struct SmartObjectReservations {
    capacities: BTreeMap<String, u32>,
    active: BTreeMap<String, BTreeSet<Entity>>,
}

impl SmartObjectReservations {
    pub fn sync_settlement_catalog(&mut self, settlements: &SettlementLibrary) {
        self.capacities.clear();
        for (_settlement_id, settlement) in settlements.iter() {
            for object in &settlement.smart_objects {
                self.capacities
                    .insert(object.id.clone(), object.capacity.max(1));
            }
        }
        self.active
            .retain(|object_id, _owners| self.capacities.contains_key(object_id));
    }

    pub fn try_acquire(
        &mut self,
        object_id: &str,
        owner: Entity,
    ) -> Result<(), ReservationConflict> {
        let capacity = self.capacities.get(object_id).copied().unwrap_or(1);
        let owners = self.active.entry(object_id.to_string()).or_default();
        if owners.contains(&owner) {
            return Ok(());
        }
        if owners.len() as u32 >= capacity {
            return Err(ReservationConflict {
                object_id: object_id.to_string(),
                owner,
            });
        }
        owners.insert(owner);
        Ok(())
    }

    pub fn release(&mut self, object_id: &str, owner: Entity) -> bool {
        let Some(owners) = self.active.get_mut(object_id) else {
            return false;
        };
        let removed = owners.remove(&owner);
        if owners.is_empty() {
            self.active.remove(object_id);
        }
        removed
    }

    pub fn holds(&self, object_id: &str, owner: Entity) -> bool {
        self.active
            .get(object_id)
            .map(|owners| owners.contains(&owner))
            .unwrap_or(false)
    }

    pub fn can_acquire(&self, object_id: &str, owner: Entity) -> bool {
        let capacity = self.capacities.get(object_id).copied().unwrap_or(1);
        let owner_count = self
            .active
            .get(object_id)
            .map(|owners| {
                if owners.contains(&owner) {
                    owners.len().saturating_sub(1)
                } else {
                    owners.len()
                }
            })
            .unwrap_or(0);

        owner_count < capacity as usize
    }

    pub fn active_for(&self, owner: Entity) -> BTreeSet<String> {
        self.active
            .iter()
            .filter_map(|(object_id, owners)| owners.contains(&owner).then_some(object_id.clone()))
            .collect()
    }

    pub fn object_owners(&self, object_id: &str) -> Vec<Entity> {
        self.active
            .get(object_id)
            .map(|owners| owners.iter().copied().collect())
            .unwrap_or_default()
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReservationConflict {
    pub object_id: String,
    pub owner: Entity,
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use bevy_ecs::prelude::*;
    use game_data::{
        GridCoord, MapId, ServiceRules, SettlementAnchorDefinition, SettlementDefinition,
        SettlementId, SettlementLibrary, SmartObjectDefinition, SmartObjectKind,
    };

    use super::SmartObjectReservations;

    #[test]
    fn reservation_service_honors_capacity_and_release() {
        let mut world = World::new();
        let one = world.spawn_empty().id();
        let two = world.spawn_empty().id();
        let three = world.spawn_empty().id();

        let mut service = SmartObjectReservations::default();
        service.sync_settlement_catalog(&SettlementLibrary::from(BTreeMap::from([(
            SettlementId("safehouse".into()),
            SettlementDefinition {
                id: SettlementId("safehouse".into()),
                map_id: MapId("safehouse_grid".into()),
                anchors: vec![SettlementAnchorDefinition {
                    id: "north_gate".into(),
                    grid: GridCoord::new(1, 0, 1),
                }],
                routes: Vec::new(),
                smart_objects: vec![SmartObjectDefinition {
                    id: "guard_post".into(),
                    kind: SmartObjectKind::GuardPost,
                    anchor_id: "north_gate".into(),
                    capacity: 2,
                    tags: vec!["guard".into()],
                }],
                service_rules: ServiceRules::default(),
            },
        )])));

        assert!(service.try_acquire("guard_post", one).is_ok());
        assert!(service.try_acquire("guard_post", two).is_ok());
        assert!(service.try_acquire("guard_post", three).is_err());
        assert!(service.release("guard_post", one));
        assert!(service.try_acquire("guard_post", three).is_ok());
    }
}

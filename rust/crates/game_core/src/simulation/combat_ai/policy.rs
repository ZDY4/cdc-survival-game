use std::cmp::Ordering;

use game_data::{ActorId, ActorSide};

use crate::simulation::Simulation;

use super::{CombatAiIntent, CombatAiSnapshot, CombatTargetOption};

const TERRITORIAL_APPROACH_DISTANCE_SCORE: i64 = 2;
const TERRITORIAL_APPROACH_MAX_STEPS: u32 = 2;
const TERRITORIAL_RETREAT_HP_RATIO: f32 = 0.45;

impl Simulation {
    pub(crate) fn execute_builtin_combat_tactic_step(&mut self, actor_id: ActorId) -> bool {
        if self.get_actor_side(actor_id) == Some(ActorSide::Player) {
            return false;
        }

        let Some(snapshot) = self.build_combat_ai_snapshot(actor_id) else {
            return false;
        };
        let Some(intent) = select_combat_ai_intent_for_profile("neutral", &snapshot) else {
            return false;
        };

        self.execute_combat_ai_intent(actor_id, intent).performed
    }
}

pub fn resolve_combat_tactic_profile_id(behavior: &str) -> &'static str {
    match behavior.trim() {
        "" | "neutral" => "neutral",
        "aggressive" => "aggressive",
        "territorial" => "territorial",
        "passive" => "passive",
        "player" => "player",
        _ => "neutral",
    }
}

pub fn select_combat_ai_intent_for_profile(
    behavior: &str,
    snapshot: &CombatAiSnapshot,
) -> Option<CombatAiIntent> {
    match resolve_combat_tactic_profile_id(behavior) {
        "player" => None,
        "passive" => select_reactive_combat_ai_intent(snapshot),
        "territorial" => select_territorial_combat_ai_intent(snapshot),
        "aggressive" => select_aggressive_combat_ai_intent(snapshot),
        "neutral" => select_default_combat_ai_intent(snapshot),
        _ => None,
    }
}

pub fn select_default_combat_ai_intent(snapshot: &CombatAiSnapshot) -> Option<CombatAiIntent> {
    let target = snapshot.target_options.first()?;
    select_target_intent(target).or_else(|| {
        target
            .approach_goals
            .first()
            .copied()
            .map(|goal| CombatAiIntent::Approach {
                target_actor: target.target_actor_id,
                goal,
            })
    })
}

fn select_reactive_combat_ai_intent(snapshot: &CombatAiSnapshot) -> Option<CombatAiIntent> {
    snapshot.target_options.iter().find_map(select_target_intent)
}

fn select_aggressive_combat_ai_intent(snapshot: &CombatAiSnapshot) -> Option<CombatAiIntent> {
    if let Some(target) = snapshot
        .target_options
        .iter()
        .filter(|target| can_execute_direct_action(target))
        .min_by(|left, right| compare_aggressive_target_priority(left, right))
    {
        return select_target_intent(target);
    }

    snapshot
        .target_options
        .iter()
        .filter(|target| target.approach_distance_steps.is_some())
        .min_by(|left, right| compare_aggressive_target_priority(left, right))
        .and_then(select_approach_intent)
}

fn select_territorial_combat_ai_intent(snapshot: &CombatAiSnapshot) -> Option<CombatAiIntent> {
    if let Some(intent) = snapshot.target_options.iter().find_map(select_target_intent) {
        return Some(intent);
    }
    if snapshot.actor_hp_ratio < TERRITORIAL_RETREAT_HP_RATIO {
        return None;
    }

    snapshot
        .target_options
        .iter()
        .filter(|target| {
            target.distance_score <= TERRITORIAL_APPROACH_DISTANCE_SCORE
                && target
                    .approach_distance_steps
                    .is_some_and(|steps| steps <= TERRITORIAL_APPROACH_MAX_STEPS)
        })
        .min_by(|left, right| compare_neutral_target_priority(left, right))
        .and_then(select_approach_intent)
}

fn select_target_intent(target: &CombatTargetOption) -> Option<CombatAiIntent> {
    if let Some(skill) = target.skill_options.first() {
        return Some(CombatAiIntent::UseSkill {
            target_actor: target.target_actor_id,
            skill_id: skill.skill_id.clone(),
        });
    }
    if target.can_basic_attack {
        return Some(CombatAiIntent::Attack {
            target_actor: target.target_actor_id,
        });
    }

    None
}

fn select_approach_intent(target: &CombatTargetOption) -> Option<CombatAiIntent> {
    target
        .approach_goals
        .first()
        .copied()
        .map(|goal| CombatAiIntent::Approach {
            target_actor: target.target_actor_id,
            goal,
        })
}

fn can_execute_direct_action(target: &CombatTargetOption) -> bool {
    target.can_basic_attack || !target.skill_options.is_empty()
}

fn compare_neutral_target_priority(
    left: &CombatTargetOption,
    right: &CombatTargetOption,
) -> Ordering {
    (left.distance_score, left.target_actor_id.0).cmp(&(right.distance_score, right.target_actor_id.0))
}

fn compare_aggressive_target_priority(
    left: &CombatTargetOption,
    right: &CombatTargetOption,
) -> Ordering {
    left.target_hp_ratio
        .partial_cmp(&right.target_hp_ratio)
        .unwrap_or(Ordering::Equal)
        .then_with(|| {
            left.approach_distance_steps
                .unwrap_or(u32::MAX)
                .cmp(&right.approach_distance_steps.unwrap_or(u32::MAX))
        })
        .then_with(|| compare_neutral_target_priority(left, right))
}

#[cfg(test)]
mod tests {
    use game_data::{ActorId, GridCoord};

    use super::{
        resolve_combat_tactic_profile_id, select_combat_ai_intent_for_profile,
        select_default_combat_ai_intent,
    };
    use crate::{CombatAiIntent, CombatAiSnapshot, CombatTargetOption};

    #[test]
    fn default_profile_approaches_when_no_direct_action_exists() {
        let snapshot = CombatAiSnapshot {
            actor_id: ActorId(1),
            actor_ap: 1.0,
            attack_ap_cost: 1.0,
            actor_hp_ratio: 1.0,
            target_options: vec![CombatTargetOption {
                target_actor_id: ActorId(2),
                distance_score: 4,
                target_hp_ratio: 1.0,
                can_basic_attack: false,
                approach_distance_steps: Some(1),
                skill_options: Vec::new(),
                approach_goals: vec![GridCoord::new(1, 0, 0)],
            }],
        };

        assert_eq!(
            select_default_combat_ai_intent(&snapshot),
            Some(CombatAiIntent::Approach {
                target_actor: ActorId(2),
                goal: GridCoord::new(1, 0, 0),
            })
        );
    }

    #[test]
    fn passive_profile_does_not_chase_targets() {
        let snapshot = CombatAiSnapshot {
            actor_id: ActorId(1),
            actor_ap: 1.0,
            attack_ap_cost: 1.0,
            actor_hp_ratio: 1.0,
            target_options: vec![CombatTargetOption {
                target_actor_id: ActorId(2),
                distance_score: 4,
                target_hp_ratio: 1.0,
                can_basic_attack: false,
                approach_distance_steps: Some(1),
                skill_options: Vec::new(),
                approach_goals: vec![GridCoord::new(1, 0, 0)],
            }],
        };

        assert_eq!(select_combat_ai_intent_for_profile("passive", &snapshot), None);
    }

    #[test]
    fn territorial_profile_only_closes_when_target_is_nearby() {
        let far_snapshot = CombatAiSnapshot {
            actor_id: ActorId(1),
            actor_ap: 1.0,
            attack_ap_cost: 1.0,
            actor_hp_ratio: 1.0,
            target_options: vec![CombatTargetOption {
                target_actor_id: ActorId(2),
                distance_score: 4,
                target_hp_ratio: 1.0,
                can_basic_attack: false,
                approach_distance_steps: Some(3),
                skill_options: Vec::new(),
                approach_goals: vec![GridCoord::new(1, 0, 0)],
            }],
        };
        let nearby_snapshot = CombatAiSnapshot {
            actor_id: ActorId(1),
            actor_ap: 1.0,
            attack_ap_cost: 1.0,
            actor_hp_ratio: 1.0,
            target_options: vec![CombatTargetOption {
                target_actor_id: ActorId(2),
                distance_score: 2,
                target_hp_ratio: 1.0,
                can_basic_attack: false,
                approach_distance_steps: Some(2),
                skill_options: Vec::new(),
                approach_goals: vec![GridCoord::new(1, 0, 0)],
            }],
        };

        assert_eq!(
            select_combat_ai_intent_for_profile("territorial", &far_snapshot),
            None
        );
        assert_eq!(
            select_combat_ai_intent_for_profile("territorial", &nearby_snapshot),
            Some(CombatAiIntent::Approach {
                target_actor: ActorId(2),
                goal: GridCoord::new(1, 0, 0),
            })
        );
    }

    #[test]
    fn unknown_profile_falls_back_to_neutral() {
        let snapshot = CombatAiSnapshot {
            actor_id: ActorId(1),
            actor_ap: 1.0,
            attack_ap_cost: 1.0,
            actor_hp_ratio: 1.0,
            target_options: vec![CombatTargetOption {
                target_actor_id: ActorId(2),
                distance_score: 1,
                target_hp_ratio: 0.2,
                can_basic_attack: true,
                approach_distance_steps: None,
                skill_options: Vec::new(),
                approach_goals: Vec::new(),
            }],
        };

        assert_eq!(resolve_combat_tactic_profile_id("mystery"), "neutral");
        assert_eq!(
            select_combat_ai_intent_for_profile("mystery", &snapshot),
            Some(CombatAiIntent::Attack {
                target_actor: ActorId(2),
            })
        );
    }

    #[test]
    fn aggressive_profile_prefers_weaker_target_over_nearest_one() {
        let snapshot = CombatAiSnapshot {
            actor_id: ActorId(1),
            actor_ap: 1.0,
            attack_ap_cost: 1.0,
            actor_hp_ratio: 1.0,
            target_options: vec![
                CombatTargetOption {
                    target_actor_id: ActorId(2),
                    distance_score: 1,
                    target_hp_ratio: 0.9,
                    can_basic_attack: true,
                    approach_distance_steps: None,
                    skill_options: Vec::new(),
                    approach_goals: Vec::new(),
                },
                CombatTargetOption {
                    target_actor_id: ActorId(3),
                    distance_score: 2,
                    target_hp_ratio: 0.1,
                    can_basic_attack: true,
                    approach_distance_steps: None,
                    skill_options: Vec::new(),
                    approach_goals: Vec::new(),
                },
            ],
        };

        assert_eq!(
            select_combat_ai_intent_for_profile("aggressive", &snapshot),
            Some(CombatAiIntent::Attack {
                target_actor: ActorId(3),
            })
        );
    }

    #[test]
    fn territorial_profile_holds_when_badly_hurt() {
        let snapshot = CombatAiSnapshot {
            actor_id: ActorId(1),
            actor_ap: 1.0,
            attack_ap_cost: 1.0,
            actor_hp_ratio: 0.2,
            target_options: vec![CombatTargetOption {
                target_actor_id: ActorId(2),
                distance_score: 1,
                target_hp_ratio: 1.0,
                can_basic_attack: false,
                approach_distance_steps: Some(1),
                skill_options: Vec::new(),
                approach_goals: vec![GridCoord::new(1, 0, 0)],
            }],
        };

        assert_eq!(
            select_combat_ai_intent_for_profile("territorial", &snapshot),
            None
        );
    }
}

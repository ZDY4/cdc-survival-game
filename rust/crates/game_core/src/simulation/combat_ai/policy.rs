//! 战斗 AI 策略模块。
//! 负责按战术 profile 选择战斗意图，不负责战斗快照采样或具体动作执行。

use std::cmp::Ordering;

use game_data::{normalize_combat_behavior_id, ActorId, ActorSide};

use crate::simulation::Simulation;

use super::{CombatAiIntent, CombatAiSnapshot, CombatSkillOption, CombatTargetOption};

const TERRITORIAL_APPROACH_DISTANCE_SCORE: i64 = 2;
const TERRITORIAL_APPROACH_MAX_STEPS: u32 = 2;
const TERRITORIAL_RETREAT_HP_RATIO: f32 = 0.45;
const TERRITORIAL_GUARD_DISTANCE_SCORE: i64 = 3;
const DEFENSIVE_RETREAT_HP_RATIO: f32 = 0.35;

impl Simulation {
    pub(crate) fn execute_builtin_combat_tactic_step(&mut self, actor_id: ActorId) -> bool {
        if self.get_actor_side(actor_id) == Some(ActorSide::Player) {
            return false;
        }

        let Some(snapshot) = self.build_combat_ai_snapshot(actor_id) else {
            return false;
        };
        let behavior = self.actor_combat_behavior(actor_id).unwrap_or("neutral");
        let Some(intent) = select_combat_ai_intent_for_profile(behavior, &snapshot) else {
            return false;
        };

        self.execute_combat_ai_intent(actor_id, intent).performed
    }
}

pub fn resolve_combat_tactic_profile_id(behavior: &str) -> &'static str {
    normalize_combat_behavior_id(behavior).unwrap_or("neutral")
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
    if let Some(intent) = select_retreat_combat_ai_intent(snapshot, DEFENSIVE_RETREAT_HP_RATIO) {
        return Some(intent);
    }

    let target = snapshot.target_options.first()?;
    select_target_intent(target).or_else(|| select_approach_intent(target))
}

fn select_reactive_combat_ai_intent(snapshot: &CombatAiSnapshot) -> Option<CombatAiIntent> {
    if let Some(target) = snapshot
        .target_options
        .iter()
        .filter(|target| can_execute_direct_action(target))
        .max_by(|left, right| compare_reactive_target_priority(left, right))
    {
        return select_target_intent(target);
    }

    select_retreat_combat_ai_intent(snapshot, DEFENSIVE_RETREAT_HP_RATIO)
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
    if let Some(target) = snapshot
        .target_options
        .iter()
        .filter(|target| can_execute_direct_action(target))
        .max_by(|left, right| compare_reactive_target_priority(left, right))
    {
        return select_target_intent(target);
    }
    if let Some(intent) = select_retreat_combat_ai_intent(snapshot, TERRITORIAL_RETREAT_HP_RATIO) {
        return Some(intent);
    }

    snapshot
        .target_options
        .iter()
        .filter(|target| {
            target.distance_score <= TERRITORIAL_APPROACH_DISTANCE_SCORE
                && target.guard_distance_score.unwrap_or(i64::MAX)
                    <= TERRITORIAL_GUARD_DISTANCE_SCORE
                && target
                    .approach_distance_steps
                    .is_some_and(|steps| steps <= TERRITORIAL_APPROACH_MAX_STEPS)
        })
        .min_by(|left, right| compare_threatened_target_priority(left, right))
        .and_then(select_approach_intent)
}

fn select_retreat_combat_ai_intent(
    snapshot: &CombatAiSnapshot,
    retreat_hp_ratio: f32,
) -> Option<CombatAiIntent> {
    if snapshot.actor_hp_ratio > retreat_hp_ratio {
        return None;
    }

    snapshot
        .target_options
        .iter()
        .filter(|target| !target.retreat_goals.is_empty())
        .max_by(|left, right| compare_threatened_target_priority(left, right))
        .and_then(select_retreat_intent)
}

fn select_target_intent(target: &CombatTargetOption) -> Option<CombatAiIntent> {
    if let Some(skill) = best_skill_option(target) {
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

fn select_retreat_intent(target: &CombatTargetOption) -> Option<CombatAiIntent> {
    target
        .retreat_goals
        .first()
        .copied()
        .map(|goal| CombatAiIntent::Retreat {
            target_actor: target.target_actor_id,
            goal,
        })
}

fn can_execute_direct_action(target: &CombatTargetOption) -> bool {
    target.can_basic_attack || !target.skill_options.is_empty()
}

fn best_skill_option(target: &CombatTargetOption) -> Option<&CombatSkillOption> {
    target
        .skill_options
        .iter()
        .max_by(|left, right| compare_skill_priority(left, right))
}

fn skill_priority(skill: &CombatSkillOption) -> i32 {
    (skill.hostile_hit_count as i32 * 12) + (skill.hit_actor_count as i32 * 2)
        - (skill.friendly_hit_count as i32 * 15)
}

fn compare_skill_priority(left: &CombatSkillOption, right: &CombatSkillOption) -> Ordering {
    skill_priority(left)
        .cmp(&skill_priority(right))
        .then_with(|| left.skill_id.cmp(&right.skill_id))
}

fn direct_action_priority(target: &CombatTargetOption) -> i32 {
    best_skill_option(target)
        .map(skill_priority)
        .unwrap_or_else(|| if target.can_basic_attack { 10 } else { 0 })
}

fn compare_neutral_target_priority(
    left: &CombatTargetOption,
    right: &CombatTargetOption,
) -> Ordering {
    (left.distance_score, left.target_actor_id.0)
        .cmp(&(right.distance_score, right.target_actor_id.0))
}

fn compare_threatened_target_priority(
    left: &CombatTargetOption,
    right: &CombatTargetOption,
) -> Ordering {
    left.threat_score
        .cmp(&right.threat_score)
        .then_with(|| direct_action_priority(left).cmp(&direct_action_priority(right)))
        .then_with(|| {
            left.target_hp_ratio
                .partial_cmp(&right.target_hp_ratio)
                .unwrap_or(Ordering::Equal)
        })
        .then_with(|| compare_neutral_target_priority(right, left))
}

fn compare_reactive_target_priority(
    left: &CombatTargetOption,
    right: &CombatTargetOption,
) -> Ordering {
    compare_threatened_target_priority(left, right)
}

fn compare_aggressive_target_priority(
    left: &CombatTargetOption,
    right: &CombatTargetOption,
) -> Ordering {
    left.target_hp_ratio
        .partial_cmp(&right.target_hp_ratio)
        .unwrap_or(Ordering::Equal)
        .then_with(|| direct_action_priority(right).cmp(&direct_action_priority(left)))
        .then_with(|| {
            left.approach_distance_steps
                .unwrap_or(u32::MAX)
                .cmp(&right.approach_distance_steps.unwrap_or(u32::MAX))
        })
        .then_with(|| right.threat_score.cmp(&left.threat_score))
        .then_with(|| compare_neutral_target_priority(left, right))
}

#[cfg(test)]
mod tests {
    use game_data::{ActorId, GridCoord};

    use super::{
        resolve_combat_tactic_profile_id, select_combat_ai_intent_for_profile,
        select_default_combat_ai_intent,
    };
    use crate::{CombatAiIntent, CombatAiSnapshot, CombatSkillOption, CombatTargetOption};

    #[test]
    fn default_profile_approaches_when_no_direct_action_exists() {
        let snapshot = CombatAiSnapshot {
            actor_id: ActorId(1),
            actor_ap: 1.0,
            attack_ap_cost: 1.0,
            actor_hp_ratio: 1.0,
            combat_origin_grid: None,
            target_options: vec![CombatTargetOption {
                target_actor_id: ActorId(2),
                distance_score: 4,
                threat_score: 1,
                guard_distance_score: None,
                target_hp_ratio: 1.0,
                can_basic_attack: false,
                approach_distance_steps: Some(1),
                skill_options: Vec::new(),
                approach_goals: vec![GridCoord::new(1, 0, 0)],
                retreat_goals: vec![GridCoord::new(-1, 0, 0)],
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
            combat_origin_grid: None,
            target_options: vec![CombatTargetOption {
                target_actor_id: ActorId(2),
                distance_score: 4,
                threat_score: 1,
                guard_distance_score: None,
                target_hp_ratio: 1.0,
                can_basic_attack: false,
                approach_distance_steps: Some(1),
                skill_options: Vec::new(),
                approach_goals: vec![GridCoord::new(1, 0, 0)],
                retreat_goals: vec![GridCoord::new(-1, 0, 0)],
            }],
        };

        assert_eq!(
            select_combat_ai_intent_for_profile("passive", &snapshot),
            None
        );
    }

    #[test]
    fn territorial_profile_only_closes_when_target_is_nearby_and_in_zone() {
        let far_snapshot = CombatAiSnapshot {
            actor_id: ActorId(1),
            actor_ap: 1.0,
            attack_ap_cost: 1.0,
            actor_hp_ratio: 1.0,
            combat_origin_grid: Some(GridCoord::new(0, 0, 0)),
            target_options: vec![CombatTargetOption {
                target_actor_id: ActorId(2),
                distance_score: 4,
                threat_score: 1,
                guard_distance_score: Some(4),
                target_hp_ratio: 1.0,
                can_basic_attack: false,
                approach_distance_steps: Some(3),
                skill_options: Vec::new(),
                approach_goals: vec![GridCoord::new(1, 0, 0)],
                retreat_goals: vec![GridCoord::new(-1, 0, 0)],
            }],
        };
        let nearby_snapshot = CombatAiSnapshot {
            actor_id: ActorId(1),
            actor_ap: 1.0,
            attack_ap_cost: 1.0,
            actor_hp_ratio: 1.0,
            combat_origin_grid: Some(GridCoord::new(0, 0, 0)),
            target_options: vec![CombatTargetOption {
                target_actor_id: ActorId(2),
                distance_score: 2,
                threat_score: 3,
                guard_distance_score: Some(2),
                target_hp_ratio: 1.0,
                can_basic_attack: false,
                approach_distance_steps: Some(2),
                skill_options: Vec::new(),
                approach_goals: vec![GridCoord::new(1, 0, 0)],
                retreat_goals: vec![GridCoord::new(-1, 0, 0)],
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
            combat_origin_grid: None,
            target_options: vec![CombatTargetOption {
                target_actor_id: ActorId(2),
                distance_score: 1,
                threat_score: 4,
                guard_distance_score: None,
                target_hp_ratio: 0.2,
                can_basic_attack: true,
                approach_distance_steps: None,
                skill_options: Vec::new(),
                approach_goals: Vec::new(),
                retreat_goals: vec![GridCoord::new(-1, 0, 0)],
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
            combat_origin_grid: None,
            target_options: vec![
                CombatTargetOption {
                    target_actor_id: ActorId(2),
                    distance_score: 1,
                    threat_score: 3,
                    guard_distance_score: None,
                    target_hp_ratio: 0.9,
                    can_basic_attack: true,
                    approach_distance_steps: None,
                    skill_options: Vec::new(),
                    approach_goals: Vec::new(),
                    retreat_goals: vec![GridCoord::new(-1, 0, 0)],
                },
                CombatTargetOption {
                    target_actor_id: ActorId(3),
                    distance_score: 2,
                    threat_score: 2,
                    guard_distance_score: None,
                    target_hp_ratio: 0.1,
                    can_basic_attack: true,
                    approach_distance_steps: None,
                    skill_options: Vec::new(),
                    approach_goals: Vec::new(),
                    retreat_goals: vec![GridCoord::new(-1, 0, 0)],
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
    fn territorial_profile_retreats_when_badly_hurt() {
        let snapshot = CombatAiSnapshot {
            actor_id: ActorId(1),
            actor_ap: 1.0,
            attack_ap_cost: 1.0,
            actor_hp_ratio: 0.2,
            combat_origin_grid: Some(GridCoord::new(0, 0, 0)),
            target_options: vec![CombatTargetOption {
                target_actor_id: ActorId(2),
                distance_score: 1,
                threat_score: 6,
                guard_distance_score: Some(1),
                target_hp_ratio: 1.0,
                can_basic_attack: false,
                approach_distance_steps: Some(1),
                skill_options: Vec::new(),
                approach_goals: vec![GridCoord::new(1, 0, 0)],
                retreat_goals: vec![GridCoord::new(-1, 0, 0)],
            }],
        };

        assert_eq!(
            select_combat_ai_intent_for_profile("territorial", &snapshot),
            Some(CombatAiIntent::Retreat {
                target_actor: ActorId(2),
                goal: GridCoord::new(-1, 0, 0),
            })
        );
    }

    #[test]
    fn aoe_skill_is_preferred_when_it_hits_more_hostiles() {
        let snapshot = CombatAiSnapshot {
            actor_id: ActorId(1),
            actor_ap: 1.0,
            attack_ap_cost: 1.0,
            actor_hp_ratio: 1.0,
            combat_origin_grid: None,
            target_options: vec![CombatTargetOption {
                target_actor_id: ActorId(2),
                distance_score: 1,
                threat_score: 5,
                guard_distance_score: None,
                target_hp_ratio: 0.8,
                can_basic_attack: true,
                approach_distance_steps: None,
                skill_options: vec![
                    CombatSkillOption {
                        skill_id: "single".to_string(),
                        hit_actor_count: 1,
                        hostile_hit_count: 1,
                        friendly_hit_count: 0,
                    },
                    CombatSkillOption {
                        skill_id: "aoe".to_string(),
                        hit_actor_count: 2,
                        hostile_hit_count: 2,
                        friendly_hit_count: 0,
                    },
                ],
                approach_goals: Vec::new(),
                retreat_goals: vec![GridCoord::new(-1, 0, 0)],
            }],
        };

        assert_eq!(
            select_default_combat_ai_intent(&snapshot),
            Some(CombatAiIntent::UseSkill {
                target_actor: ActorId(2),
                skill_id: "aoe".to_string(),
            })
        );
    }
}

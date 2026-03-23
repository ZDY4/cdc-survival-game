use std::collections::BTreeSet;

use super::{NpcFact, NpcFactInput};

pub fn rebuild_facts(input: &NpcFactInput) -> Vec<NpcFact> {
    let mut facts = BTreeSet::new();

    if input.hunger <= 50.0 {
        facts.insert(NpcFact::Hungry);
    }
    if input.hunger <= 25.0 {
        facts.insert(NpcFact::VeryHungry);
    }
    if input.energy <= 50.0 {
        facts.insert(NpcFact::Sleepy);
    }
    if input.energy <= 25.0 {
        facts.insert(NpcFact::Exhausted);
    }
    if input.morale <= 40.0 {
        facts.insert(NpcFact::NeedMorale);
    }
    if input.on_shift {
        facts.insert(NpcFact::OnShift);
    }
    if input.shift_starting_soon {
        facts.insert(NpcFact::ShiftStartingSoon);
    }
    if input.threat_detected {
        facts.insert(NpcFact::ThreatDetected);
    }
    if input.meal_window_open {
        facts.insert(NpcFact::MealWindowOpen);
    }
    if input.has_reserved_bed {
        facts.insert(NpcFact::HasReservedBed);
    }
    if input.has_reserved_meal_seat {
        facts.insert(NpcFact::HasReservedMealSeat);
    }
    if input.guard_coverage_insufficient {
        facts.insert(NpcFact::GuardCoverageInsufficient);
    }
    if input.current_anchor.is_some() && input.current_anchor == input.home_anchor {
        facts.insert(NpcFact::AtHome);
    }
    if input.current_anchor.is_some() && input.current_anchor == input.duty_anchor {
        facts.insert(NpcFact::AtDutyArea);
    }

    facts.into_iter().collect()
}

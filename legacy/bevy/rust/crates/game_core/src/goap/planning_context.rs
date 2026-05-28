//! GOAP 规划上下文模块。
//! 负责规划时的可达 anchor 和旅行时间视图，不负责目标打分或执行推进。

use std::collections::{BTreeMap, BTreeSet};

use super::NpcPlanRequest;

#[derive(Debug, Clone, PartialEq)]
pub struct NpcPlanningContext {
    pub request: NpcPlanRequest,
    pub current_anchor: Option<String>,
    reachable_anchors: BTreeSet<String>,
    travel_minutes_by_anchor: BTreeMap<String, u32>,
}

impl NpcPlanningContext {
    pub fn from_plan_request(request: &NpcPlanRequest) -> Self {
        let mut context = Self {
            request: request.clone(),
            current_anchor: None,
            reachable_anchors: BTreeSet::new(),
            travel_minutes_by_anchor: BTreeMap::new(),
        };

        for anchor in [
            request.home_anchor.as_ref(),
            request.duty_anchor.as_ref(),
            request.canteen_anchor.as_ref(),
            request.leisure_anchor.as_ref(),
            request.alarm_anchor.as_ref(),
        ]
        .into_iter()
        .flatten()
        {
            context.register_reachable_anchor(anchor.clone(), 15);
        }

        context
    }

    pub fn with_current_anchor(mut self, current_anchor: Option<String>) -> Self {
        self.current_anchor = current_anchor;
        self
    }

    pub fn register_reachable_anchor(&mut self, anchor: String, travel_minutes: u32) {
        self.reachable_anchors.insert(anchor.clone());
        self.travel_minutes_by_anchor.insert(anchor, travel_minutes);
    }

    pub fn is_anchor_reachable(&self, anchor: Option<&str>) -> bool {
        match anchor {
            None => true,
            Some(anchor) => self.reachable_anchors.contains(anchor),
        }
    }

    pub fn travel_minutes_to(&self, anchor: Option<&str>, fallback_minutes: u32) -> u32 {
        let Some(anchor) = anchor else {
            return fallback_minutes;
        };
        if self.current_anchor.as_deref() == Some(anchor) {
            return 0;
        }
        self.travel_minutes_by_anchor
            .get(anchor)
            .copied()
            .unwrap_or(fallback_minutes)
    }
}

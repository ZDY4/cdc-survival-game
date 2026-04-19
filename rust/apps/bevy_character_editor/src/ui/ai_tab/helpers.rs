use std::collections::BTreeSet;

use bevy_egui::egui;
use game_data::{
    AiActionAvailabilityPreview, AiActionBlockerKind, AiActionEvaluationPreview,
    CharacterAiPreview, ScheduleDay,
};

use crate::state::{schedule_day_label, EditorData};
use crate::ui::common::{negative_text, neutral_text, positive_text};

pub(super) fn best_goal(preview: &CharacterAiPreview) -> Option<&game_data::AiGoalScorePreview> {
    preview.goal_scores.iter().max_by(|left, right| {
        left.score
            .cmp(&right.score)
            .then_with(|| right.display_name.cmp(&left.display_name))
    })
}

pub(super) fn recommended_action(
    preview: &CharacterAiPreview,
) -> Option<&AiActionAvailabilityPreview> {
    preview
        .available_actions
        .iter()
        .find(|action| action.available)
}

pub(super) fn blocked_actions(preview: &CharacterAiPreview) -> Vec<&AiActionEvaluationPreview> {
    preview
        .diagnostics
        .action_evaluations
        .iter()
        .filter(|action| !action.available)
        .collect()
}

pub(super) fn blocker_summary(preview: &CharacterAiPreview) -> Vec<String> {
    let kinds = preview
        .diagnostics
        .action_evaluations
        .iter()
        .flat_map(|action| {
            action
                .blockers
                .iter()
                .map(|blocker| blocker_label(blocker.kind))
        })
        .collect::<BTreeSet<_>>();
    kinds.into_iter().map(str::to_string).collect()
}

pub(super) fn resolve_schedule_display_name(
    data: &EditorData,
    preview: &CharacterAiPreview,
) -> String {
    data.ai_library
        .as_ref()
        .and_then(|library| library.schedule_templates.get(&preview.schedule.profile_id))
        .map(|schedule| {
            if schedule.meta.display_name.trim().is_empty() {
                schedule.id.clone()
            } else {
                schedule.meta.display_name.clone()
            }
        })
        .unwrap_or_else(|| preview.schedule.profile_id.clone())
}

pub(super) fn preview_schedule_entry_label(preview: &CharacterAiPreview) -> &str {
    preview
        .diagnostics
        .active_schedule_entry
        .as_ref()
        .map(|entry| entry.label.as_str())
        .unwrap_or("-")
}

pub(super) fn goal_label(goal: &game_data::AiGoalScorePreview) -> egui::RichText {
    let text = format!("{} [{}]", goal.display_name, goal.goal_id);
    if goal.score > 0 {
        positive_text(text)
    } else if goal.score < 0 {
        negative_text(text)
    } else {
        neutral_text(text)
    }
}

pub(super) fn score_badge_fill(score: i32) -> egui::Color32 {
    if score > 0 {
        egui::Color32::from_rgb(44, 76, 56)
    } else if score < 0 {
        egui::Color32::from_rgb(110, 38, 38)
    } else {
        egui::Color32::from_rgb(58, 64, 78)
    }
}

pub(super) fn format_minute(minute_of_day: u16) -> String {
    format!("{:02}:{:02}", minute_of_day / 60, minute_of_day % 60)
}

pub(super) fn blocker_label(kind: AiActionBlockerKind) -> &'static str {
    match kind {
        AiActionBlockerKind::PreconditionMismatch => "前置条件不满足",
        AiActionBlockerKind::PreconditionUnresolved => "前置条件未解析",
        AiActionBlockerKind::MissingTargetAnchor => "缺少目标锚点",
        AiActionBlockerKind::ReservationUnavailable => "预占目标不可用",
    }
}

pub(super) fn ai_context_tooltip(label: &str) -> &'static str {
    match label {
        "星期" => "模拟当前是星期几。它会决定匹配哪一组日程块。",
        "分钟" => "模拟一天中的分钟数。AI 会用它定位当前日程时段。",
        "饥饿" => "模拟当前饥饿程度。该值会进入 need blackboard，影响进食相关目标评分。",
        "精力" => "模拟当前体力与疲劳程度。该值会进入 need blackboard，影响休息和工作类行为。",
        "士气" => "模拟当前情绪或士气状态。它会进入 blackboard，影响休闲、工作等行为倾向。",
        "世界警报" => "模拟当前是否处于全局警报。开启后 AI 会优先考虑警戒或应急目标。",
        "值班守卫" => "模拟当前据点已在岗的守卫人数。它会参与守卫缺口与巡逻相关判断。",
        "最低守卫" => "模拟据点要求的最低在岗守卫人数。AI 会用它判断是否需要补足守卫。",
        "当前锚点" => "模拟角色当前所在锚点。路径、目标选择和锚点相关 fact 会从这里出发。",
        "guard_post" => "模拟据点内是否存在可用的 guard post。它会写入 availability blackboard。",
        "meal_object" => "模拟是否存在可用进食对象。进食类 goal 和 action 会读取这个可用性输入。",
        "leisure_object" => "模拟是否存在可用休闲对象。娱乐或放松类行为会据此判断能否执行。",
        "medical_station" => "模拟是否存在可用医疗站对象。治疗或恢复类行为会读取这个输入。",
        "patrol_route" => "模拟是否存在可用巡逻路线。巡逻、值守等移动行为会据此判断可行性。",
        "bed" => "模拟是否存在可用床位对象。休息、睡眠类行为会读取这个可用性输入。",
        _ => "",
    }
}

pub(super) fn ai_relation_tooltip(label: &str) -> &'static str {
    match label {
        "据点" => "当前 AI 预览绑定的据点 ID。锚点、路线和服务规则都从这个据点解析。",
        "角色职责" => "当前角色在据点中的职责类型。它会影响默认日程、守卫要求和目标选择。",
        "家锚点" => "角色默认归属的 home 锚点。回家、休息或缺省定位时会优先使用它。",
        "执勤路线" => "角色绑定的 duty route ID。巡逻与值守类行为会用它解析移动路线。",
        _ => "",
    }
}

pub(super) fn ai_metric_tooltip(label: &str) -> &'static str {
    match label {
        "score_delta" => "单条 goal 规则提供的基础分值增量。命中后会在乘算前作为原始加分参与计算。",
        "multiplier_key" => {
            "该规则使用的 blackboard 乘数键。若存在，AI 会读取对应值对 score_delta 做缩放。"
        }
        "multiplier_value" => "本次预览实际读取到的乘数值。它与 score_delta 一起决定最终贡献分。",
        "contributed_score" => "这条规则最终贡献给 goal 的分数结果。它已经考虑命中状态和乘数。",
        "target_anchor" => "动作最终解析出的目标锚点。执行时会据此确定要前往或交互的位置。",
        "reservation_target" => {
            "动作尝试预占的对象或目标标识。AI 用它避免多个角色同时争抢同一资源。"
        }
        _ => "",
    }
}

pub(super) fn resolved_anchor_tooltip(key: &str) -> &'static str {
    match key {
        "anchor.home" => "从 blackboard 解析出的 home 锚点结果。回家、休息或缺省定位会优先使用它。",
        "anchor.duty" => {
            "从 blackboard 解析出的 duty 锚点结果。执勤、站岗等行为会把它当成目标定位。"
        }
        "anchor.canteen" => "从 blackboard 解析出的食堂或进食锚点结果。进食相关行为会用它寻址。",
        "anchor.leisure" => "从 blackboard 解析出的休闲锚点结果。娱乐或放松行为会用它寻址。",
        "anchor.alarm" => {
            "从 blackboard 解析出的警报集合点或警戒锚点结果。警报响应行为会用它寻址。"
        }
        _ => "",
    }
}

pub(super) fn blackboard_header_tooltip(label: &str) -> &'static str {
    match label {
        "key" => "blackboard 键名。用于标识这条输入在 AI 内部的读取路径。",
        "value" => "当前预览下解析出的 blackboard 值。goal、fact 和 action 会读取它参与判断。",
        "source" => "这条 blackboard 值的来源。可用来判断它来自需求、日程、据点还是手动上下文。",
        _ => "",
    }
}

pub(super) fn blackboard_group_tooltip(group: &str) -> &'static str {
    match group {
        "need" => "需求相关 blackboard 项，如饥饿和休息。goal 规则会读取这些值判断角色当前缺什么。",
        "personality" => "性格与偏好相关 blackboard 项。用于让不同角色在相同环境下做出不同倾向。",
        "schedule" => "日程相关 blackboard 项。表示当前命中的时间块和日程上下文。",
        "world" => "世界状态相关 blackboard 项。警报等全局条件会从这里进入 AI 计算。",
        "settlement" => "据点级别输入，如守卫人数或服务规则。AI 会用它判断据点运行状态。",
        "availability" => {
            "可用性输入，表示某类对象或路线当前是否可用。动作和目标会用它做前置筛选。"
        }
        "reservation" => "预占用状态输入，用于协调多个 AI 对对象的竞争。",
        "anchor" => "解析后的锚点输入。动作定位和部分 fact 会读取这些目标位置。",
        _ => "",
    }
}

pub(super) fn blackboard_key_tooltip(key: &str) -> Option<&'static str> {
    match key {
        "anchor.home" => Some("home 锚点键。角色回家、休息或默认归属位置会使用它。"),
        "anchor.duty" => Some("执勤目标锚点键。站岗、巡逻等行为会读取它确定 duty 位置。"),
        "anchor.canteen" => Some("进食目标锚点键。寻找食堂或餐食对象时会先读取它。"),
        "anchor.leisure" => Some("休闲目标锚点键。娱乐或放松类行为会用它定位去哪里。"),
        "anchor.alarm" => Some("警报目标锚点键。警报响应和集结行为会用它确定目标位置。"),
        _ => None,
    }
}

pub(super) fn schedule_day_options() -> [ScheduleDay; 7] {
    [
        ScheduleDay::Monday,
        ScheduleDay::Tuesday,
        ScheduleDay::Wednesday,
        ScheduleDay::Thursday,
        ScheduleDay::Friday,
        ScheduleDay::Saturday,
        ScheduleDay::Sunday,
    ]
}

pub(super) fn schedule_day_name(day: ScheduleDay) -> &'static str {
    schedule_day_label(day)
}

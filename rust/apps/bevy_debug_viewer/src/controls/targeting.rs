//! 目标选择子模块：负责攻击/技能选区进入、目标范围计算与悬停预览刷新。

use super::*;

pub(crate) fn cancel_targeting(viewer_state: &mut ViewerState, status: impl Into<String>) {
    viewer_state.targeting_state = None;
    viewer_state.status_line = status.into();
}

pub(crate) fn enter_attack_targeting(
    runtime_state: &ViewerRuntimeState,
    viewer_state: &mut ViewerState,
) -> Result<(), String> {
    let snapshot = runtime_state.runtime.snapshot();
    let actor_id = viewer_state
        .command_actor_id(&snapshot)
        .ok_or_else(|| "请选择可控制角色".to_string())?;
    if viewer_state.is_free_observe() {
        return Err("自由观察模式下无法攻击".to_string());
    }

    let query = runtime_state.runtime.query_attack_targeting(actor_id);
    let valid_grids = query
        .valid_grids
        .into_iter()
        .collect::<std::collections::BTreeSet<_>>();
    let valid_actor_ids = query
        .valid_actor_ids
        .into_iter()
        .collect::<std::collections::BTreeSet<_>>();
    if valid_actor_ids.is_empty() {
        return Err(query
            .invalid_reason
            .as_deref()
            .map(targeting_reason_text)
            .unwrap_or("范围内没有可攻击目标")
            .to_string());
    }

    viewer_state.targeting_state = Some(ViewerTargetingState {
        actor_id,
        action: ViewerTargetingAction::Attack,
        source: ViewerTargetingSource::AttackButton,
        shape: "single".to_string(),
        radius: 0,
        valid_grids,
        valid_actor_ids,
        hovered_grid: None,
        preview_target: None,
        preview_hit_grids: Vec::new(),
        preview_hit_actor_ids: Vec::new(),
        prompt_text: "普通攻击: 左键确认，右键/Esc 取消".to_string(),
    });
    viewer_state.status_line = "普通攻击: 选择目标".to_string();
    Ok(())
}

pub(crate) fn enter_skill_targeting(
    runtime_state: &ViewerRuntimeState,
    viewer_state: &mut ViewerState,
    skills: &SkillDefinitions,
    skill_id: &str,
    source: ViewerTargetingSource,
) -> Result<(), String> {
    let snapshot = runtime_state.runtime.snapshot();
    let actor_id = viewer_state
        .command_actor_id(&snapshot)
        .ok_or_else(|| "请选择可控制角色".to_string())?;
    let Some(skill) = skills.0.get(skill_id) else {
        return Err(format!("未知技能 {skill_id}"));
    };
    let query = runtime_state
        .runtime
        .query_skill_targeting(actor_id, skill_id);
    let valid_grids = query
        .valid_grids
        .into_iter()
        .collect::<std::collections::BTreeSet<_>>();
    if valid_grids.is_empty() {
        let reason = query
            .invalid_reason
            .as_deref()
            .map(targeting_reason_text)
            .unwrap_or("当前没有可选目标格");
        return Err(format!("{} {reason}", skill.name));
    }
    let valid_actor_ids = query
        .valid_actor_ids
        .into_iter()
        .collect::<std::collections::BTreeSet<_>>();

    viewer_state.targeting_state = Some(ViewerTargetingState {
        actor_id,
        action: ViewerTargetingAction::Skill {
            skill_id: skill_id.to_string(),
            skill_name: skill.name.clone(),
        },
        source,
        shape: query.shape,
        radius: query.radius,
        valid_grids,
        valid_actor_ids,
        hovered_grid: None,
        preview_target: None,
        preview_hit_grids: Vec::new(),
        preview_hit_actor_ids: Vec::new(),
        prompt_text: format!("{}: 左键确认，右键/Esc 取消", skill.name),
    });
    viewer_state.status_line = format!("{}: 选择目标", skill.name);
    Ok(())
}

pub(crate) fn refresh_targeting_preview(
    runtime_state: &ViewerRuntimeState,
    viewer_state: &mut ViewerState,
    hovered_grid: Option<GridCoord>,
) {
    let Some(targeting) = viewer_state.targeting_state.as_mut() else {
        return;
    };
    targeting.hovered_grid = hovered_grid;
    targeting.preview_target = None;
    targeting.preview_hit_grids.clear();
    targeting.preview_hit_actor_ids.clear();

    let Some(grid) = hovered_grid.filter(|grid| targeting.valid_grids.contains(grid)) else {
        return;
    };

    match &targeting.action {
        ViewerTargetingAction::Attack => {
            if let Some(actor) = actor_at_grid(&runtime_state.runtime.snapshot(), grid)
                .filter(|actor| targeting.valid_actor_ids.contains(&actor.actor_id))
            {
                targeting.preview_target = Some(SkillTargetRequest::Actor(actor.actor_id));
                targeting.preview_hit_grids = vec![grid];
                targeting.preview_hit_actor_ids = vec![actor.actor_id];
            }
        }
        ViewerTargetingAction::Skill { skill_id, .. } => {
            let preview = runtime_state.runtime.preview_skill_target(
                targeting.actor_id,
                skill_id,
                SkillTargetRequest::Grid(grid),
            );
            if preview.invalid_reason.is_none() {
                targeting.preview_target = preview.resolved_target;
                targeting.preview_hit_grids = preview.preview_hit_grids;
                targeting.preview_hit_actor_ids = preview.preview_hit_actor_ids;
            }
        }
    }
}

fn targeting_reason_text(reason: &str) -> &'static str {
    match reason {
        "unknown_actor" => "施法者不存在",
        "unknown_skill" => "技能不存在",
        "skill_targeting_disabled" => "不需要选择目标",
        "target_out_of_bounds" => "目标超出边界",
        "target_invalid_level" => "目标不在同一楼层",
        "target_out_of_range" => "目标超出范围",
        "target_blocked_by_los" => "目标被遮挡",
        "no_attack_targets" => "范围内没有可攻击目标",
        "no_skill_targets" => "当前没有可选目标格",
        _ => "当前没有可选目标",
    }
}

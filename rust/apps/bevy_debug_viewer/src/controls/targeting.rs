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

    let Some(actor_grid) = runtime_state.runtime.get_actor_grid_position(actor_id) else {
        return Err("攻击者不存在".to_string());
    };
    let attack_range = runtime_state.runtime.get_actor_attack_range(actor_id);
    let mut valid_grids = std::collections::BTreeSet::new();
    let mut valid_actor_ids = std::collections::BTreeSet::new();
    for actor in snapshot
        .actors
        .iter()
        .filter(|actor| actor.side == ActorSide::Hostile)
    {
        if actor.grid_position.y != actor_grid.y {
            continue;
        }
        if attack_target_in_range(
            &runtime_state.runtime,
            actor_grid,
            actor.grid_position,
            attack_range,
        ) {
            valid_grids.insert(actor.grid_position);
            valid_actor_ids.insert(actor.actor_id);
        }
    }
    if valid_actor_ids.is_empty() {
        return Err("范围内没有可攻击目标".to_string());
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
    let Some(actor_grid) = runtime_state.runtime.get_actor_grid_position(actor_id) else {
        return Err("施法者不存在".to_string());
    };
    let Some(skill) = skills.0.get(skill_id) else {
        return Err(format!("未知技能 {skill_id}"));
    };
    let Some(targeting) = skill
        .activation
        .as_ref()
        .and_then(|activation| activation.targeting.as_ref())
        .filter(|targeting| targeting.enabled)
    else {
        return Err(format!("{} 不需要选择目标", skill.name));
    };

    let valid_grids = collect_valid_target_grids(
        &runtime_state.runtime,
        &snapshot,
        actor_grid,
        targeting.range_cells,
    );
    if valid_grids.is_empty() {
        return Err(format!("{} 当前没有可选目标格", skill.name));
    }
    let valid_actor_ids = snapshot
        .actors
        .iter()
        .filter(|actor| valid_grids.contains(&actor.grid_position))
        .map(|actor| actor.actor_id)
        .collect();

    viewer_state.targeting_state = Some(ViewerTargetingState {
        actor_id,
        action: ViewerTargetingAction::Skill {
            skill_id: skill_id.to_string(),
            skill_name: skill.name.clone(),
        },
        source,
        shape: targeting.shape.trim().to_string(),
        radius: targeting.radius.max(0),
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

    targeting.preview_hit_grids = affected_grids_for_shape(
        &runtime_state.runtime,
        grid,
        targeting.shape.as_str(),
        targeting.radius,
    );
    targeting.preview_hit_actor_ids = runtime_state
        .runtime
        .snapshot()
        .actors
        .iter()
        .filter(|actor| targeting.preview_hit_grids.contains(&actor.grid_position))
        .map(|actor| actor.actor_id)
        .collect();

    if targeting.shape == "single" {
        if let Some(actor) = actor_at_grid(&runtime_state.runtime.snapshot(), grid)
            .filter(|actor| targeting.valid_actor_ids.contains(&actor.actor_id))
        {
            targeting.preview_target = Some(SkillTargetRequest::Actor(actor.actor_id));
        } else {
            targeting.preview_target = Some(SkillTargetRequest::Grid(grid));
        }
    } else {
        targeting.preview_target = Some(SkillTargetRequest::Grid(grid));
    }
}

fn collect_valid_target_grids(
    runtime: &game_core::SimulationRuntime,
    snapshot: &game_core::SimulationSnapshot,
    actor_grid: GridCoord,
    range_cells: i32,
) -> std::collections::BTreeSet<GridCoord> {
    let grids = snapshot
        .grid
        .map_cells
        .iter()
        .map(|cell| cell.grid)
        .filter(|grid| grid.y == actor_grid.y)
        .filter(|grid| runtime.is_grid_in_bounds(*grid))
        .filter(|grid| manhattan_distance(actor_grid, *grid) <= range_cells.max(0))
        .collect::<std::collections::BTreeSet<_>>();

    if grids.is_empty() {
        std::iter::once(actor_grid)
            .filter(|grid| runtime.is_grid_in_bounds(*grid))
            .collect()
    } else {
        grids
    }
}

fn affected_grids_for_shape(
    runtime: &game_core::SimulationRuntime,
    center: GridCoord,
    shape: &str,
    radius: i32,
) -> Vec<GridCoord> {
    let radius = radius.max(0);
    let mut grids = Vec::new();
    for dx in -radius..=radius {
        for dz in -radius..=radius {
            let include = match shape {
                "diamond" => dx.abs() + dz.abs() <= radius,
                "square" => true,
                _ => dx == 0 && dz == 0,
            };
            if !include {
                continue;
            }
            let grid = GridCoord::new(center.x + dx, center.y, center.z + dz);
            if runtime.is_grid_in_bounds(grid) {
                grids.push(grid);
            }
        }
    }
    if grids.is_empty() {
        grids.push(center);
    }
    grids
}

fn attack_target_in_range(
    runtime: &game_core::SimulationRuntime,
    actor_grid: GridCoord,
    target_grid: GridCoord,
    attack_range: f32,
) -> bool {
    let actor_world = runtime.grid_to_world(actor_grid);
    let target_world = runtime.grid_to_world(target_grid);
    let dx = actor_world.x - target_world.x;
    let dz = actor_world.z - target_world.z;
    (dx * dx + dz * dz).sqrt() <= attack_range + 0.05
}

fn manhattan_distance(left: GridCoord, right: GridCoord) -> i32 {
    (left.x - right.x).abs() + (left.z - right.z).abs()
}

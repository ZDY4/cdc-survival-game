use std::collections::{BTreeMap, BTreeSet, VecDeque};

use bevy_egui::egui;

const NODE_WIDTH: f32 = 232.0;
const NODE_HEIGHT: f32 = 96.0;
const GRAPH_MIN_ZOOM: f32 = 0.35;
const GRAPH_MAX_ZOOM: f32 = 2.0;
const LAYOUT_X_SPACING: f32 = 292.0;
const LAYOUT_Y_SPACING: f32 = 156.0;
const FIT_MARGIN: f32 = 56.0;

#[derive(Debug, Clone)]
pub struct FlowGraphNode {
    pub id: String,
    pub title: String,
    pub subtitle: Option<String>,
    pub badge: Option<String>,
    pub position: Option<egui::Pos2>,
}

#[derive(Debug, Clone)]
pub struct FlowGraphEdge {
    pub id: String,
    pub from: String,
    pub to: String,
    pub label: Option<String>,
}

#[derive(Debug, Clone)]
pub struct FlowGraphModel {
    pub graph_key: String,
    pub start_node_id: Option<String>,
    pub empty_message: String,
    pub nodes: Vec<FlowGraphNode>,
    pub edges: Vec<FlowGraphEdge>,
}

#[derive(Debug, Clone)]
pub struct FlowGraphCanvasState {
    zoom: f32,
    pan: egui::Vec2,
    pending_action: FlowGraphPendingAction,
    last_graph_key: Option<String>,
}

impl Default for FlowGraphCanvasState {
    fn default() -> Self {
        Self {
            zoom: 1.0,
            pan: egui::Vec2::ZERO,
            pending_action: FlowGraphPendingAction::FitGraph,
            last_graph_key: None,
        }
    }
}

impl FlowGraphCanvasState {
    pub fn request_fit(&mut self) {
        self.pending_action = FlowGraphPendingAction::FitGraph;
    }

    pub fn request_center_start(&mut self) {
        self.pending_action = FlowGraphPendingAction::CenterStart;
    }

    pub fn request_reset_zoom(&mut self) {
        self.pending_action = FlowGraphPendingAction::ResetZoom;
    }
}

#[derive(Debug, Clone, Default)]
pub struct FlowGraphResponse {
    pub clicked_node_id: Option<String>,
}

#[derive(Debug, Clone)]
enum FlowGraphPendingAction {
    None,
    FitGraph,
    CenterStart,
    ResetZoom,
}

impl Default for FlowGraphPendingAction {
    fn default() -> Self {
        Self::None
    }
}

#[derive(Debug, Clone)]
struct LaidOutNode<'a> {
    node: &'a FlowGraphNode,
    world_rect: egui::Rect,
}

pub fn render_read_only_flow_graph(
    ui: &mut egui::Ui,
    state: &mut FlowGraphCanvasState,
    model: &FlowGraphModel,
    selected_node_id: Option<&str>,
) -> FlowGraphResponse {
    let mut graph_response = FlowGraphResponse::default();

    ui.vertical(|ui| {
        render_graph_toolbar(ui, state);
        ui.add_space(4.0);

        let desired_size = ui
            .available_size_before_wrap()
            .max(egui::vec2(320.0, 280.0));
        let (canvas_rect, canvas_response) =
            ui.allocate_exact_size(desired_size, egui::Sense::click_and_drag());
        let painter = ui.painter_at(canvas_rect);
        painter.rect_filled(canvas_rect, 10.0, ui.visuals().extreme_bg_color);

        if model.nodes.is_empty() {
            painter.text(
                canvas_rect.center(),
                egui::Align2::CENTER_CENTER,
                model.empty_message.as_str(),
                egui::TextStyle::Body.resolve(ui.style()),
                ui.visuals().weak_text_color(),
            );
            return;
        }

        let layout = layout_flow_graph(model);
        let bounds = graph_bounds(&layout);

        if state.last_graph_key.as_deref() != Some(model.graph_key.as_str()) {
            state.last_graph_key = Some(model.graph_key.clone());
            state.pending_action = FlowGraphPendingAction::FitGraph;
        }

        if canvas_response.hovered() {
            let scroll_delta = ui.input(|input| input.raw_scroll_delta.y);
            if scroll_delta.abs() > f32::EPSILON {
                zoom_canvas_at_pointer(
                    state,
                    canvas_rect,
                    canvas_response.hover_pos(),
                    scroll_delta,
                );
            }
        }

        apply_pending_action(state, model, &layout, bounds, canvas_rect);
        render_background_grid(&painter, canvas_rect, state.zoom, state.pan, ui.visuals());

        let node_screen_rects = layout
            .iter()
            .map(|node| {
                (
                    node.node.id.as_str(),
                    world_rect_to_screen(canvas_rect, node.world_rect, state.zoom, state.pan),
                )
            })
            .collect::<BTreeMap<_, _>>();

        if canvas_response.dragged() {
            let drag_delta = ui.input(|input| input.pointer.delta());
            let hovered_node = canvas_response.hover_pos().and_then(|hover_pos| {
                node_screen_rects.iter().find_map(|(node_id, node_rect)| {
                    node_rect.contains(hover_pos).then_some(*node_id)
                })
            });
            if hovered_node.is_none() {
                state.pan += drag_delta;
            }
        }

        if canvas_response.clicked() {
            if let Some(pointer_pos) = canvas_response.interact_pointer_pos() {
                graph_response.clicked_node_id =
                    node_screen_rects.iter().find_map(|(node_id, node_rect)| {
                        node_rect
                            .contains(pointer_pos)
                            .then(|| (*node_id).to_string())
                    });
            }
        }

        render_edges(ui, &painter, model, &node_screen_rects, selected_node_id);
        render_nodes(
            ui,
            &painter,
            &layout,
            &node_screen_rects,
            model.start_node_id.as_deref(),
            selected_node_id,
        );
    });

    graph_response
}

fn render_graph_toolbar(ui: &mut egui::Ui, state: &mut FlowGraphCanvasState) {
    ui.horizontal(|ui| {
        if ui.button("适配").clicked() {
            state.request_fit();
        }
        if ui.button("起点").clicked() {
            state.request_center_start();
        }
        if ui.button("缩小").clicked() {
            state.zoom = (state.zoom * 0.9).clamp(GRAPH_MIN_ZOOM, GRAPH_MAX_ZOOM);
        }
        if ui.button("放大").clicked() {
            state.zoom = (state.zoom * 1.1).clamp(GRAPH_MIN_ZOOM, GRAPH_MAX_ZOOM);
        }
        if ui.button("100%").clicked() {
            state.request_reset_zoom();
        }
        ui.separator();
        ui.small(format!("缩放 {:.0}%", state.zoom * 100.0));
    });
}

fn render_background_grid(
    painter: &egui::Painter,
    canvas_rect: egui::Rect,
    zoom: f32,
    pan: egui::Vec2,
    visuals: &egui::Visuals,
) {
    let world_spacing = 96.0;
    let screen_spacing = world_spacing * zoom;
    if screen_spacing < 28.0 {
        return;
    }

    let stroke = egui::Stroke::new(
        1.0,
        visuals
            .widgets
            .noninteractive
            .bg_stroke
            .color
            .gamma_multiply(0.18),
    );
    let origin = canvas_rect.center() + pan;

    let first_x = origin.x.rem_euclid(screen_spacing);
    let first_y = origin.y.rem_euclid(screen_spacing);

    let mut x = canvas_rect.left() + first_x;
    while x <= canvas_rect.right() {
        painter.line_segment(
            [
                egui::pos2(x, canvas_rect.top()),
                egui::pos2(x, canvas_rect.bottom()),
            ],
            stroke,
        );
        x += screen_spacing;
    }

    let mut y = canvas_rect.top() + first_y;
    while y <= canvas_rect.bottom() {
        painter.line_segment(
            [
                egui::pos2(canvas_rect.left(), y),
                egui::pos2(canvas_rect.right(), y),
            ],
            stroke,
        );
        y += screen_spacing;
    }
}

fn render_edges(
    ui: &egui::Ui,
    painter: &egui::Painter,
    model: &FlowGraphModel,
    node_screen_rects: &BTreeMap<&str, egui::Rect>,
    selected_node_id: Option<&str>,
) {
    for edge in &model.edges {
        let Some(from_rect) = node_screen_rects.get(edge.from.as_str()) else {
            continue;
        };
        let Some(to_rect) = node_screen_rects.get(edge.to.as_str()) else {
            continue;
        };

        let selected_edge = selected_node_id
            .map(|selected| selected == edge.from || selected == edge.to)
            .unwrap_or(false);
        let stroke = egui::Stroke::new(
            if selected_edge { 2.4 } else { 1.4 },
            if selected_edge {
                ui.visuals().selection.stroke.color
            } else {
                ui.visuals().weak_text_color().gamma_multiply(0.55)
            },
        );

        let source = egui::pos2(from_rect.right(), from_rect.center().y);
        let target = egui::pos2(to_rect.left(), to_rect.center().y);
        let mid_x = if target.x >= source.x {
            (source.x + target.x) * 0.5
        } else {
            source.x + 48.0
        };
        let waypoints = [
            source,
            egui::pos2(mid_x, source.y),
            egui::pos2(mid_x, target.y),
            target,
        ];
        for segment in waypoints.windows(2) {
            painter.line_segment([segment[0], segment[1]], stroke);
        }

        let arrow_size = 6.0;
        painter.line_segment(
            [
                egui::pos2(target.x - arrow_size, target.y - arrow_size * 0.55),
                target,
            ],
            stroke,
        );
        painter.line_segment(
            [
                egui::pos2(target.x - arrow_size, target.y + arrow_size * 0.55),
                target,
            ],
            stroke,
        );

        if let Some(label) = edge
            .label
            .as_deref()
            .filter(|value| !value.trim().is_empty())
        {
            let label_pos = egui::pos2(mid_x, (source.y + target.y) * 0.5);
            let galley = painter.layout_no_wrap(
                truncate_label(label, 22),
                egui::TextStyle::Small.resolve(ui.style()),
                ui.visuals().text_color(),
            );
            let label_rect =
                egui::Rect::from_center_size(label_pos, galley.size() + egui::vec2(10.0, 6.0));
            painter.rect_filled(
                label_rect,
                5.0,
                ui.visuals().panel_fill.gamma_multiply(0.96),
            );
            painter.galley(
                label_rect.center() - galley.size() * 0.5,
                galley,
                ui.visuals().text_color(),
            );
        }
    }
}

fn render_nodes(
    ui: &egui::Ui,
    painter: &egui::Painter,
    layout: &[LaidOutNode<'_>],
    node_screen_rects: &BTreeMap<&str, egui::Rect>,
    start_node_id: Option<&str>,
    selected_node_id: Option<&str>,
) {
    for node in layout {
        let Some(rect) = node_screen_rects.get(node.node.id.as_str()) else {
            continue;
        };

        let is_selected = selected_node_id == Some(node.node.id.as_str());
        let is_start = start_node_id == Some(node.node.id.as_str());
        let fill = if is_selected {
            ui.visuals().selection.bg_fill
        } else if is_start {
            ui.visuals().faint_bg_color
        } else {
            ui.visuals().panel_fill
        };
        let stroke = if is_selected {
            ui.visuals().selection.stroke
        } else if is_start {
            egui::Stroke::new(1.8, ui.visuals().warn_fg_color)
        } else {
            egui::Stroke::new(1.0, ui.visuals().widgets.noninteractive.bg_stroke.color)
        };

        painter.rect(*rect, 10.0, fill, stroke, egui::StrokeKind::Middle);

        let mut cursor = rect.left_top() + egui::vec2(12.0, 10.0);
        if let Some(badge) = node.node.badge.as_deref() {
            let badge_galley = painter.layout_no_wrap(
                truncate_label(badge, 24),
                egui::TextStyle::Small.resolve(ui.style()),
                ui.visuals().strong_text_color(),
            );
            let badge_rect =
                egui::Rect::from_min_size(cursor, badge_galley.size() + egui::vec2(10.0, 6.0));
            painter.rect_filled(
                badge_rect,
                999.0,
                ui.visuals().extreme_bg_color.gamma_multiply(0.9),
            );
            painter.galley(
                badge_rect.min + egui::vec2(5.0, 3.0),
                badge_galley,
                ui.visuals().strong_text_color(),
            );
            cursor.y = badge_rect.bottom() + 6.0;
        }

        painter.text(
            cursor,
            egui::Align2::LEFT_TOP,
            truncate_label(&node.node.title, 30),
            egui::TextStyle::Button.resolve(ui.style()),
            ui.visuals().strong_text_color(),
        );
        cursor.y += 24.0;

        let subtitle = node
            .node
            .subtitle
            .as_deref()
            .filter(|value| !value.trim().is_empty())
            .unwrap_or(node.node.id.as_str());
        painter.text(
            cursor,
            egui::Align2::LEFT_TOP,
            truncate_label(subtitle, 44),
            egui::TextStyle::Small.resolve(ui.style()),
            ui.visuals().text_color(),
        );
    }
}

fn zoom_canvas_at_pointer(
    state: &mut FlowGraphCanvasState,
    canvas_rect: egui::Rect,
    hover_pos: Option<egui::Pos2>,
    scroll_delta: f32,
) {
    let Some(pointer_pos) = hover_pos else {
        return;
    };

    let old_zoom = state.zoom;
    let new_zoom = if scroll_delta > 0.0 {
        (state.zoom * 1.1).clamp(GRAPH_MIN_ZOOM, GRAPH_MAX_ZOOM)
    } else {
        (state.zoom * 0.9).clamp(GRAPH_MIN_ZOOM, GRAPH_MAX_ZOOM)
    };

    if (new_zoom - old_zoom).abs() <= f32::EPSILON {
        return;
    }

    let world_pos = screen_to_world(canvas_rect, pointer_pos, old_zoom, state.pan);
    state.zoom = new_zoom;
    state.pan = pointer_pos - canvas_rect.center() - world_pos.to_vec2() * new_zoom;
}

fn apply_pending_action(
    state: &mut FlowGraphCanvasState,
    model: &FlowGraphModel,
    layout: &[LaidOutNode<'_>],
    bounds: egui::Rect,
    canvas_rect: egui::Rect,
) {
    match state.pending_action {
        FlowGraphPendingAction::None => {}
        FlowGraphPendingAction::FitGraph => {
            fit_graph_to_canvas(state, bounds, canvas_rect);
            state.pending_action = FlowGraphPendingAction::None;
        }
        FlowGraphPendingAction::CenterStart => {
            let target = model
                .start_node_id
                .as_deref()
                .and_then(|start_id| layout.iter().find(|node| node.node.id == start_id))
                .map(|node| node.world_rect.center())
                .unwrap_or(bounds.center());
            center_world_point_on_canvas(state, target, canvas_rect);
            state.pending_action = FlowGraphPendingAction::None;
        }
        FlowGraphPendingAction::ResetZoom => {
            state.zoom = 1.0;
            let target = model
                .start_node_id
                .as_deref()
                .and_then(|start_id| layout.iter().find(|node| node.node.id == start_id))
                .map(|node| node.world_rect.center())
                .unwrap_or(bounds.center());
            center_world_point_on_canvas(state, target, canvas_rect);
            state.pending_action = FlowGraphPendingAction::None;
        }
    }
}

fn fit_graph_to_canvas(
    state: &mut FlowGraphCanvasState,
    bounds: egui::Rect,
    canvas_rect: egui::Rect,
) {
    let width = bounds.width().max(1.0);
    let height = bounds.height().max(1.0);
    let zoom_x = (canvas_rect.width() - FIT_MARGIN).max(120.0) / width;
    let zoom_y = (canvas_rect.height() - FIT_MARGIN).max(120.0) / height;
    state.zoom = zoom_x.min(zoom_y).clamp(GRAPH_MIN_ZOOM, GRAPH_MAX_ZOOM);
    center_world_point_on_canvas(state, bounds.center(), canvas_rect);
}

fn center_world_point_on_canvas(
    state: &mut FlowGraphCanvasState,
    world_center: egui::Pos2,
    canvas_rect: egui::Rect,
) {
    state.pan = canvas_rect.center() - canvas_rect.center() - world_center.to_vec2() * state.zoom;
}

fn world_rect_to_screen(
    canvas_rect: egui::Rect,
    world_rect: egui::Rect,
    zoom: f32,
    pan: egui::Vec2,
) -> egui::Rect {
    let min = canvas_rect.center() + pan + world_rect.min.to_vec2() * zoom;
    egui::Rect::from_min_size(min, world_rect.size() * zoom)
}

fn screen_to_world(
    canvas_rect: egui::Rect,
    screen_pos: egui::Pos2,
    zoom: f32,
    pan: egui::Vec2,
) -> egui::Pos2 {
    let world = (screen_pos - canvas_rect.center() - pan) / zoom.max(0.0001);
    egui::pos2(world.x, world.y)
}

fn graph_bounds(layout: &[LaidOutNode<'_>]) -> egui::Rect {
    let mut min = egui::pos2(f32::INFINITY, f32::INFINITY);
    let mut max = egui::pos2(f32::NEG_INFINITY, f32::NEG_INFINITY);

    for node in layout {
        min.x = min.x.min(node.world_rect.left());
        min.y = min.y.min(node.world_rect.top());
        max.x = max.x.max(node.world_rect.right());
        max.y = max.y.max(node.world_rect.bottom());
    }

    if !min.x.is_finite() || !min.y.is_finite() || !max.x.is_finite() || !max.y.is_finite() {
        egui::Rect::from_min_size(egui::Pos2::ZERO, egui::vec2(NODE_WIDTH, NODE_HEIGHT))
    } else {
        egui::Rect::from_min_max(min, max)
    }
}

fn layout_flow_graph(model: &FlowGraphModel) -> Vec<LaidOutNode<'_>> {
    let use_stored_positions = model.nodes.iter().all(|node| node.position.is_some());
    let positions = if use_stored_positions {
        model
            .nodes
            .iter()
            .map(|node| (node.id.as_str(), node.position.unwrap_or_default()))
            .collect::<BTreeMap<_, _>>()
    } else {
        fallback_positions(model)
    };

    model
        .nodes
        .iter()
        .map(|node| {
            let position = positions.get(node.id.as_str()).copied().unwrap_or_default();
            LaidOutNode {
                node,
                world_rect: egui::Rect::from_min_size(
                    position,
                    egui::vec2(NODE_WIDTH, NODE_HEIGHT),
                ),
            }
        })
        .collect()
}

fn fallback_positions(model: &FlowGraphModel) -> BTreeMap<&str, egui::Pos2> {
    let node_ids = model
        .nodes
        .iter()
        .map(|node| node.id.as_str())
        .collect::<BTreeSet<_>>();
    let mut outgoing = BTreeMap::<&str, Vec<&str>>::new();
    let mut incoming_counts = BTreeMap::<&str, usize>::new();

    for node_id in &node_ids {
        outgoing.insert(*node_id, Vec::new());
        incoming_counts.insert(*node_id, 0);
    }

    for edge in &model.edges {
        if node_ids.contains(edge.from.as_str()) && node_ids.contains(edge.to.as_str()) {
            outgoing
                .entry(edge.from.as_str())
                .or_default()
                .push(edge.to.as_str());
            *incoming_counts.entry(edge.to.as_str()).or_default() += 1;
        }
    }

    for targets in outgoing.values_mut() {
        targets.sort();
        targets.dedup();
    }

    let mut levels = BTreeMap::<&str, usize>::new();
    let mut queue = VecDeque::<&str>::new();

    if let Some(start_id) = model
        .start_node_id
        .as_deref()
        .filter(|id| node_ids.contains(id))
    {
        levels.insert(start_id, 0);
        queue.push_back(start_id);
    }

    for node_id in node_ids
        .iter()
        .copied()
        .filter(|node_id| incoming_counts.get(node_id).copied().unwrap_or_default() == 0)
    {
        if levels.insert(node_id, 0).is_none() {
            queue.push_back(node_id);
        }
    }

    while let Some(current) = queue.pop_front() {
        let current_level = levels.get(current).copied().unwrap_or_default();
        if let Some(targets) = outgoing.get(current) {
            for target in targets {
                let next_level = current_level + 1;
                let entry = levels.entry(target).or_insert(next_level);
                if next_level < *entry {
                    *entry = next_level;
                }
                if *entry == next_level {
                    queue.push_back(target);
                }
            }
        }
    }

    let mut next_free_level = levels.values().copied().max().unwrap_or_default() + 1;
    for node_id in node_ids.iter().copied() {
        if !levels.contains_key(node_id) {
            levels.insert(node_id, next_free_level);
            next_free_level += 1;
        }
    }

    let mut lanes = BTreeMap::<usize, usize>::new();
    let mut ordered_ids = model
        .nodes
        .iter()
        .map(|node| node.id.as_str())
        .collect::<Vec<_>>();
    ordered_ids.sort_by(|left, right| {
        let left_rank = usize::from(model.start_node_id.as_deref() != Some(left));
        let right_rank = usize::from(model.start_node_id.as_deref() != Some(right));
        levels
            .get(left)
            .copied()
            .unwrap_or_default()
            .cmp(&levels.get(right).copied().unwrap_or_default())
            .then(left_rank.cmp(&right_rank))
            .then(left.cmp(right))
    });

    ordered_ids
        .into_iter()
        .map(|node_id| {
            let level = levels.get(node_id).copied().unwrap_or_default();
            let lane = lanes.entry(level).or_default();
            let position = egui::pos2(
                level as f32 * LAYOUT_X_SPACING,
                *lane as f32 * LAYOUT_Y_SPACING,
            );
            *lane += 1;
            (node_id, position)
        })
        .collect()
}

fn truncate_label(label: &str, max_chars: usize) -> String {
    let mut chars = label.chars();
    let prefix = chars.by_ref().take(max_chars).collect::<String>();
    if chars.next().is_some() {
        format!("{prefix}...")
    } else {
        prefix
    }
}

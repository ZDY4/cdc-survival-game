use std::collections::BTreeMap;

use bevy_egui::egui;
use game_data::{QuestDefinition, QuestNode};
use game_editor::{FlowGraphEdge, FlowGraphModel, FlowGraphNode};
use serde_json::Value;

#[derive(Debug, Clone)]
pub(crate) struct QuestConnectionView {
    pub(crate) from: String,
    pub(crate) from_port: i32,
    pub(crate) to: String,
    pub(crate) to_port: i32,
    pub(crate) extra: BTreeMap<String, Value>,
}

#[derive(Debug, Clone)]
pub(crate) struct QuestFlowView {
    pub(crate) relative_path: String,
    pub(crate) connection_count: usize,
    pub(crate) node_type_counts: BTreeMap<String, usize>,
    pub(crate) connections: Vec<QuestConnectionView>,
    pub(crate) graph_model: FlowGraphModel,
}

pub(crate) fn build_quest_flow_view(quest: &QuestDefinition, relative_path: &str) -> QuestFlowView {
    let mut nodes = quest.flow.nodes.values().collect::<Vec<_>>();
    nodes.sort_by(|left, right| {
        let left_rank = usize::from(left.id != quest.flow.start_node_id);
        let right_rank = usize::from(right.id != quest.flow.start_node_id);
        left_rank.cmp(&right_rank).then(left.id.cmp(&right.id))
    });

    let graph_nodes = nodes
        .iter()
        .map(|node| FlowGraphNode {
            id: node.id.clone(),
            title: node.id.clone(),
            subtitle: Some(quest_graph_subtitle(node)),
            badge: non_empty(node.node_type.as_str()).map(str::to_string),
            position: node
                .position
                .map(|position| egui::pos2(position.x, position.y)),
        })
        .collect::<Vec<_>>();

    let mut connections = quest
        .flow
        .connections
        .iter()
        .map(|connection| QuestConnectionView {
            from: connection.from.clone(),
            from_port: connection.from_port,
            to: connection.to.clone(),
            to_port: connection.to_port,
            extra: connection.extra.clone(),
        })
        .collect::<Vec<_>>();
    connections.sort_by(|left, right| {
        left.from
            .cmp(&right.from)
            .then(left.from_port.cmp(&right.from_port))
            .then(left.to.cmp(&right.to))
            .then(left.to_port.cmp(&right.to_port))
    });

    let graph_edges = connections
        .iter()
        .map(|connection| FlowGraphEdge {
            id: format!(
                "{}:{}:{}:{}",
                connection.from, connection.from_port, connection.to, connection.to_port
            ),
            from: connection.from.clone(),
            to: connection.to.clone(),
            label: None,
        })
        .collect::<Vec<_>>();

    QuestFlowView {
        relative_path: relative_path.to_string(),
        connection_count: connections.len(),
        node_type_counts: quest.flow.nodes.values().fold(
            BTreeMap::<String, usize>::new(),
            |mut counts, node| {
                *counts.entry(node.node_type.clone()).or_default() += 1;
                counts
            },
        ),
        connections,
        graph_model: FlowGraphModel {
            graph_key: quest.quest_id.clone(),
            start_node_id: Some(quest.flow.start_node_id.clone()),
            empty_message: "当前任务没有可显示的节点。".to_string(),
            nodes: graph_nodes,
            edges: graph_edges,
        },
    }
}

fn quest_graph_subtitle(node: &QuestNode) -> String {
    let detail = non_empty(node.title.as_str())
        .or_else(|| non_empty(node.description.as_str()))
        .or_else(|| non_empty(node.target.as_str()))
        .map(|value| truncate_text(value, 40));
    match detail {
        Some(detail) if !node.node_type.trim().is_empty() => {
            format!("{} · {detail}", node.node_type)
        }
        Some(detail) => detail,
        None => node.node_type.clone(),
    }
}

fn truncate_text(value: &str, max_chars: usize) -> String {
    let mut chars = value.chars();
    let prefix = chars.by_ref().take(max_chars).collect::<String>();
    if chars.next().is_some() {
        format!("{prefix}...")
    } else {
        prefix
    }
}

fn non_empty(value: &str) -> Option<&str> {
    let trimmed = value.trim();
    (!trimmed.is_empty()).then_some(trimmed)
}

use std::collections::{BTreeMap, BTreeSet};

use bevy_egui::egui;
use game_data::{resolve_dialogue_start_node_id, DialogueConnection, DialogueData, DialogueNode};
use game_editor::{FlowGraphEdge, FlowGraphModel, FlowGraphNode};
use serde_json::Value;

#[derive(Debug, Clone)]
pub(crate) struct DialogueConnectionView {
    pub(crate) from: String,
    pub(crate) from_port: i32,
    pub(crate) to: String,
    pub(crate) to_port: i32,
    pub(crate) label: Option<String>,
    pub(crate) extra: BTreeMap<String, Value>,
}

#[derive(Debug, Clone)]
pub(crate) struct DialogueFlowView {
    pub(crate) relative_path: String,
    pub(crate) start_node_id: Option<String>,
    pub(crate) connection_count: usize,
    pub(crate) node_type_counts: BTreeMap<String, usize>,
    pub(crate) start_node_count: usize,
    pub(crate) end_node_count: usize,
    pub(crate) choice_branch_count: usize,
    pub(crate) condition_branch_count: usize,
    pub(crate) connections: Vec<DialogueConnectionView>,
    pub(crate) graph_model: FlowGraphModel,
}

pub(crate) fn build_dialogue_flow_view(
    dialogue: &DialogueData,
    relative_path: &str,
) -> DialogueFlowView {
    let start_node_id = resolve_dialogue_start_node_id(dialogue);
    let node_ids = dialogue
        .nodes
        .iter()
        .map(|node| node.id.as_str())
        .collect::<BTreeSet<_>>();
    let node_lookup = dialogue
        .nodes
        .iter()
        .map(|node| (node.id.as_str(), node))
        .collect::<BTreeMap<_, _>>();

    let mut connections = BTreeMap::<(String, i32, String, i32), DialogueConnectionView>::new();
    for connection in &dialogue.connections {
        insert_explicit_connection(&mut connections, &node_ids, &node_lookup, connection);
    }
    for node in &dialogue.nodes {
        insert_derived_connections(&mut connections, &node_ids, node);
    }

    let mut merged_connections = connections.into_values().collect::<Vec<_>>();
    merged_connections.sort_by(|left, right| {
        left.from
            .cmp(&right.from)
            .then(left.from_port.cmp(&right.from_port))
            .then(left.to.cmp(&right.to))
            .then(left.to_port.cmp(&right.to_port))
    });

    let mut nodes = dialogue.nodes.iter().collect::<Vec<_>>();
    nodes.sort_by(|left, right| {
        let left_rank = usize::from(start_node_id.as_deref() != Some(left.id.as_str()));
        let right_rank = usize::from(start_node_id.as_deref() != Some(right.id.as_str()));
        left_rank.cmp(&right_rank).then(left.id.cmp(&right.id))
    });

    let graph_nodes = nodes
        .iter()
        .map(|node| FlowGraphNode {
            id: node.id.clone(),
            title: node.id.clone(),
            subtitle: Some(dialogue_graph_subtitle(node)),
            badge: non_empty(node.speaker.as_str()).map(str::to_string),
            position: node
                .position
                .map(|position| egui::pos2(position.x, position.y)),
        })
        .collect::<Vec<_>>();

    let graph_edges = merged_connections
        .iter()
        .map(|connection| FlowGraphEdge {
            id: format!(
                "{}:{}:{}:{}",
                connection.from, connection.from_port, connection.to, connection.to_port
            ),
            from: connection.from.clone(),
            to: connection.to.clone(),
            label: connection.label.clone(),
        })
        .collect::<Vec<_>>();

    DialogueFlowView {
        relative_path: relative_path.to_string(),
        start_node_id: start_node_id.clone(),
        connection_count: merged_connections.len(),
        node_type_counts: dialogue.nodes.iter().fold(
            BTreeMap::<String, usize>::new(),
            |mut counts, node| {
                *counts.entry(node.node_type.clone()).or_default() += 1;
                counts
            },
        ),
        start_node_count: dialogue.nodes.iter().filter(|node| node.is_start).count(),
        end_node_count: dialogue
            .nodes
            .iter()
            .filter(|node| node.node_type == "end")
            .count(),
        choice_branch_count: dialogue
            .nodes
            .iter()
            .filter(|node| node.node_type == "choice")
            .map(|node| node.options.len())
            .sum(),
        condition_branch_count: dialogue
            .nodes
            .iter()
            .filter(|node| node.node_type == "condition")
            .map(|node| {
                usize::from(non_empty(node.true_next.as_str()).is_some())
                    + usize::from(non_empty(node.false_next.as_str()).is_some())
            })
            .sum(),
        connections: merged_connections,
        graph_model: FlowGraphModel {
            graph_key: dialogue.dialog_id.clone(),
            start_node_id,
            empty_message: "当前对话没有可显示的节点。".to_string(),
            nodes: graph_nodes,
            edges: graph_edges,
        },
    }
}

fn insert_explicit_connection(
    connections: &mut BTreeMap<(String, i32, String, i32), DialogueConnectionView>,
    node_ids: &BTreeSet<&str>,
    node_lookup: &BTreeMap<&str, &DialogueNode>,
    connection: &DialogueConnection,
) {
    let from = connection.from.trim();
    let to = connection.to.trim();
    if from.is_empty() || to.is_empty() || !node_ids.contains(from) || !node_ids.contains(to) {
        return;
    }

    let key = (
        from.to_string(),
        connection.from_port,
        to.to_string(),
        connection.to_port,
    );
    connections.insert(
        key,
        DialogueConnectionView {
            from: from.to_string(),
            from_port: connection.from_port,
            to: to.to_string(),
            to_port: connection.to_port,
            label: node_lookup
                .get(from)
                .and_then(|node| port_label_for_node(node, connection.from_port)),
            extra: connection.extra.clone(),
        },
    );
}

fn insert_derived_connections(
    connections: &mut BTreeMap<(String, i32, String, i32), DialogueConnectionView>,
    node_ids: &BTreeSet<&str>,
    node: &DialogueNode,
) {
    insert_derived_connection(
        connections,
        node_ids,
        node.id.as_str(),
        0,
        node.next.as_str(),
        0,
        None,
    );

    for (index, option) in node.options.iter().enumerate() {
        let fallback_label = if option.text.trim().is_empty() {
            Some(format!("option[{index}]"))
        } else {
            Some(option.text.trim().to_string())
        };
        insert_derived_connection(
            connections,
            node_ids,
            node.id.as_str(),
            index as i32,
            option.next.as_str(),
            0,
            fallback_label,
        );
    }

    insert_derived_connection(
        connections,
        node_ids,
        node.id.as_str(),
        1,
        node.true_next.as_str(),
        0,
        Some("true".to_string()),
    );
    insert_derived_connection(
        connections,
        node_ids,
        node.id.as_str(),
        2,
        node.false_next.as_str(),
        0,
        Some("false".to_string()),
    );
}

fn insert_derived_connection(
    connections: &mut BTreeMap<(String, i32, String, i32), DialogueConnectionView>,
    node_ids: &BTreeSet<&str>,
    from: &str,
    from_port: i32,
    to: &str,
    to_port: i32,
    label: Option<String>,
) {
    let from = from.trim();
    let to = to.trim();
    if from.is_empty() || to.is_empty() || !node_ids.contains(from) || !node_ids.contains(to) {
        return;
    }

    let key = (from.to_string(), from_port, to.to_string(), to_port);
    connections
        .entry(key)
        .or_insert_with(|| DialogueConnectionView {
            from: from.to_string(),
            from_port,
            to: to.to_string(),
            to_port,
            label,
            extra: BTreeMap::new(),
        });
}

fn port_label_for_node(node: &DialogueNode, from_port: i32) -> Option<String> {
    if node.node_type == "choice" {
        if let Some(option) = node.options.get(from_port.max(0) as usize) {
            return non_empty(option.text.as_str())
                .map(str::to_string)
                .or_else(|| Some(format!("option[{from_port}]")));
        }
    }
    if node.node_type == "condition" {
        return match from_port {
            1 => Some("true".to_string()),
            2 => Some("false".to_string()),
            _ => None,
        };
    }
    None
}

fn dialogue_graph_subtitle(node: &DialogueNode) -> String {
    let detail = non_empty(node.title.as_str())
        .or_else(|| non_empty(node.text.as_str()))
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

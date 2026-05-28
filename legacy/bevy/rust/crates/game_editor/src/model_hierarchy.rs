use std::collections::BTreeSet;
use std::fs;
use std::path::{Component, Path, PathBuf};

use bevy::prelude::Resource;
use bevy_egui::egui;
use serde_json::Value;

#[derive(Resource, Debug, Default)]
pub struct ModelHierarchyPanelState {
    pub visible: bool,
    loaded_key: String,
    documents: Vec<ModelHierarchyDocument>,
    status: Option<String>,
    selected_node: Option<ModelHierarchySelection>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ModelHierarchySelection {
    document_index: usize,
    node_index: usize,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ModelHierarchySource {
    pub label: String,
    pub asset_path: String,
}

impl ModelHierarchySource {
    pub fn new(label: impl Into<String>, asset_path: impl Into<String>) -> Self {
        Self {
            label: label.into(),
            asset_path: asset_path.into(),
        }
    }
}

#[derive(Debug, Clone, Copy, Default)]
pub struct ModelHierarchyPanelResponse {
    pub hovered: bool,
}

#[derive(Debug, Clone)]
struct ModelHierarchyDocument {
    source: ModelHierarchySource,
    nodes: Vec<ModelHierarchyNode>,
    roots: Vec<usize>,
    errors: Vec<String>,
}

#[derive(Debug, Clone)]
struct ModelHierarchyNode {
    index: usize,
    name: String,
    children: Vec<usize>,
    has_mesh: bool,
    is_socket: bool,
    is_joint: bool,
}

pub fn render_model_hierarchy_panel(
    ctx: &egui::Context,
    id: impl Into<egui::Id>,
    rect: egui::Rect,
    state: &mut ModelHierarchyPanelState,
    asset_root: &Path,
    sources: &[ModelHierarchySource],
) -> ModelHierarchyPanelResponse {
    if !state.visible {
        return ModelHierarchyPanelResponse::default();
    }

    state.sync(asset_root, sources);
    let area = egui::Area::new(id.into())
        .order(egui::Order::Foreground)
        .fixed_pos(rect.right_top() + egui::vec2(-370.0, 10.0))
        .show(ctx, |ui| {
            egui::Frame::NONE
                .fill(egui::Color32::from_rgba_unmultiplied(18, 21, 28, 210))
                .corner_radius(6.0)
                .inner_margin(egui::Margin::symmetric(10, 8))
                .show(ui, |ui| {
                    ui.set_width(350.0);
                    ui.set_max_height((rect.height() - 24.0).max(180.0));
                    render_panel_contents(ui, state);
                });
        });

    ModelHierarchyPanelResponse {
        hovered: area.response.hovered(),
    }
}

fn render_panel_contents(ui: &mut egui::Ui, state: &mut ModelHierarchyPanelState) {
    ui.horizontal(|ui| {
        ui.label(
            egui::RichText::new("模型层级")
                .size(13.0)
                .color(egui::Color32::from_rgb(228, 231, 238)),
        );
        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
            if ui.small_button("关闭").clicked() {
                state.visible = false;
            }
        });
    });
    if let Some(status) = state.status.as_deref() {
        ui.small(status);
    }
    ui.separator();

    egui::ScrollArea::vertical()
        .auto_shrink([false, false])
        .show(ui, |ui| {
            if state.documents.is_empty() {
                ui.label("当前预览没有可显示的 glTF 层级。");
                return;
            }
            for document_index in 0..state.documents.len() {
                let document = state.documents[document_index].clone();
                let header = format!(
                    "{}  ({})",
                    document.source.label, document.source.asset_path
                );
                egui::CollapsingHeader::new(header)
                    .id_salt(("model_hierarchy_doc", document_index))
                    .default_open(true)
                    .show(ui, |ui| {
                        for error in &document.errors {
                            ui.colored_label(egui::Color32::from_rgb(224, 170, 82), error);
                        }
                        for root in &document.roots {
                            render_node(ui, state, document_index, &document, *root, 0);
                        }
                    });
            }
        });
}

fn render_node(
    ui: &mut egui::Ui,
    state: &mut ModelHierarchyPanelState,
    document_index: usize,
    document: &ModelHierarchyDocument,
    node_index: usize,
    depth: usize,
) {
    let Some(node) = document.nodes.get(node_index) else {
        return;
    };
    let selected = state.selected_node.as_ref().is_some_and(|selection| {
        selection.document_index == document_index && selection.node_index == node.index
    });
    let label = node_label(node);
    if node.children.is_empty() {
        ui.horizontal(|ui| {
            ui.add_space(depth as f32 * 10.0);
            let response = ui.selectable_label(selected, label);
            if response.clicked() {
                state.selected_node = Some(ModelHierarchySelection {
                    document_index,
                    node_index: node.index,
                });
            }
        });
        return;
    }

    ui.horizontal(|ui| {
        ui.add_space(depth as f32 * 10.0);
        let response = egui::CollapsingHeader::new(label)
            .id_salt(("model_hierarchy_node", document_index, node.index))
            .default_open(depth < 2)
            .show(ui, |ui| {
                for child in &node.children {
                    render_node(ui, state, document_index, document, *child, depth + 1);
                }
            });
        if response.header_response.clicked() {
            state.selected_node = Some(ModelHierarchySelection {
                document_index,
                node_index: node.index,
            });
        }
    });
}

fn node_label(node: &ModelHierarchyNode) -> String {
    let mut tags = Vec::new();
    if node.has_mesh {
        tags.push("mesh");
    }
    if node.is_joint {
        tags.push("骨骼");
    }
    if node.is_socket {
        tags.push("socket");
    }
    if tags.is_empty() {
        format!("{}  #{}", node.name, node.index)
    } else {
        format!("{}  #{}  [{}]", node.name, node.index, tags.join(" · "))
    }
}

impl ModelHierarchyPanelState {
    fn sync(&mut self, asset_root: &Path, sources: &[ModelHierarchySource]) {
        let next_key = sources
            .iter()
            .map(|source| format!("{}={}", source.label, source.asset_path))
            .collect::<Vec<_>>()
            .join("\n");
        if self.loaded_key == next_key {
            return;
        }

        self.loaded_key = next_key;
        self.documents.clear();
        self.selected_node = None;
        self.status = None;

        let mut errors = Vec::new();
        for source in sources {
            match ModelHierarchyDocument::load(asset_root, source) {
                Ok(document) => self.documents.push(document),
                Err(error) => errors.push(format!("{}: {error}", source.asset_path)),
            }
        }
        if !errors.is_empty() {
            self.status = Some(errors.join("；"));
        }
    }
}

impl ModelHierarchyDocument {
    fn load(asset_root: &Path, source: &ModelHierarchySource) -> Result<Self, String> {
        let relative_path = normalize_relative_gltf_path(&source.asset_path)?;
        let absolute_path = resolve_asset_path(asset_root, &relative_path)?;
        let raw = fs::read_to_string(&absolute_path)
            .map_err(|error| format!("读取 glTF 失败 {}: {error}", absolute_path.display()))?;
        let json: Value = serde_json::from_str(&raw)
            .map_err(|error| format!("解析 glTF 失败 {}: {error}", absolute_path.display()))?;
        let nodes_json = json
            .get("nodes")
            .and_then(Value::as_array)
            .ok_or_else(|| "glTF 缺少 nodes 数组".to_string())?;
        let joint_indices = collect_joint_indices(&json);
        let mut nodes = Vec::with_capacity(nodes_json.len());
        for (index, node) in nodes_json.iter().enumerate() {
            let name = node
                .get("name")
                .and_then(Value::as_str)
                .map(str::to_string)
                .unwrap_or_else(|| format!("Node {index}"));
            let children = node
                .get("children")
                .and_then(Value::as_array)
                .map(|children| {
                    children
                        .iter()
                        .filter_map(Value::as_u64)
                        .filter_map(|value| usize::try_from(value).ok())
                        .filter(|child| *child < nodes_json.len())
                        .collect::<Vec<_>>()
                })
                .unwrap_or_default();
            nodes.push(ModelHierarchyNode {
                index,
                has_mesh: node.get("mesh").and_then(Value::as_u64).is_some(),
                is_socket: is_socket_node(node, name.as_str()),
                is_joint: joint_indices.contains(&index),
                name,
                children,
            });
        }
        let mut errors = Vec::new();
        let roots = scene_roots(&json, nodes.len(), &mut errors);
        Ok(Self {
            source: source.clone(),
            nodes,
            roots,
            errors,
        })
    }
}

fn collect_joint_indices(json: &Value) -> BTreeSet<usize> {
    let mut joints = BTreeSet::new();
    if let Some(skins) = json.get("skins").and_then(Value::as_array) {
        for skin in skins {
            let Some(values) = skin.get("joints").and_then(Value::as_array) else {
                continue;
            };
            for value in values {
                if let Some(index) = value.as_u64().and_then(|value| usize::try_from(value).ok()) {
                    joints.insert(index);
                }
            }
        }
    }
    joints
}

fn scene_roots(json: &Value, node_count: usize, errors: &mut Vec<String>) -> Vec<usize> {
    let scenes = json
        .get("scenes")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();
    let scene_index = json
        .get("scene")
        .and_then(Value::as_u64)
        .and_then(|value| usize::try_from(value).ok())
        .unwrap_or(0);
    let roots = scenes
        .get(scene_index)
        .and_then(|scene| scene.get("nodes"))
        .and_then(Value::as_array)
        .map(|nodes| {
            nodes
                .iter()
                .filter_map(Value::as_u64)
                .filter_map(|value| usize::try_from(value).ok())
                .filter(|index| *index < node_count)
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();
    if !roots.is_empty() {
        return roots;
    }

    errors.push("glTF scene 未声明 root nodes，已按无父节点推断。".to_string());
    parentless_nodes(json, node_count)
}

fn parentless_nodes(json: &Value, node_count: usize) -> Vec<usize> {
    let mut has_parent = vec![false; node_count];
    if let Some(nodes) = json.get("nodes").and_then(Value::as_array) {
        for node in nodes {
            let Some(children) = node.get("children").and_then(Value::as_array) else {
                continue;
            };
            for child in children {
                if let Some(index) = child.as_u64().and_then(|value| usize::try_from(value).ok()) {
                    if index < node_count {
                        has_parent[index] = true;
                    }
                }
            }
        }
    }
    has_parent
        .into_iter()
        .enumerate()
        .filter_map(|(index, value)| (!value).then_some(index))
        .collect()
}

fn is_socket_node(node: &Value, name: &str) -> bool {
    name.ends_with("_socket")
        || matches!(name, "hand_l" | "hand_r")
        || node
            .get("extras")
            .and_then(|extras| extras.get("cdc_socket"))
            .and_then(Value::as_bool)
            .unwrap_or(false)
}

fn normalize_relative_gltf_path(path: &str) -> Result<String, String> {
    let trimmed = path.trim().replace('\\', "/");
    if trimmed.is_empty() {
        return Err("路径不能为空".to_string());
    }
    let path = Path::new(&trimmed);
    if path.is_absolute() {
        return Err(format!("路径必须是资产根相对路径: {trimmed}"));
    }
    for component in path.components() {
        if matches!(
            component,
            Component::ParentDir | Component::RootDir | Component::Prefix(_)
        ) {
            return Err(format!("路径不能越过资产根: {trimmed}"));
        }
    }
    if path
        .extension()
        .and_then(|value| value.to_str())
        .is_none_or(|value| !value.eq_ignore_ascii_case("gltf"))
    {
        return Err(format!("层级树仅支持 .gltf: {trimmed}"));
    }
    Ok(path.to_string_lossy().replace('\\', "/"))
}

fn resolve_asset_path(asset_root: &Path, relative_path: &str) -> Result<PathBuf, String> {
    let root = asset_root
        .canonicalize()
        .map_err(|error| format!("资产根无效 {}: {error}", asset_root.display()))?;
    let absolute_path = root.join(relative_path);
    let absolute_path = absolute_path
        .canonicalize()
        .map_err(|error| format!("资产文件不存在 {}: {error}", absolute_path.display()))?;
    if !absolute_path.starts_with(&root) {
        return Err(format!("资产路径越过资产根: {}", absolute_path.display()));
    }
    Ok(absolute_path)
}

use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use bevy::gltf::GltfAssetLabel;
use bevy::prelude::*;
use bevy_egui::{egui, EguiContexts};
use serde_json::{Map, Number, Value};

use crate::state::{PreviewState, ViewerAssetRoot, ViewerUiState};

pub(crate) const SOCKET_PRESETS: &[&str] = &[
    "body_socket",
    "hands_socket",
    "head_socket",
    "back_socket",
    "accessory_socket",
    "legs_socket",
    "feet_socket",
    "hand_l",
    "hand_r",
];

#[derive(Message, Debug, Clone, PartialEq, Eq)]
pub(crate) enum SocketEditorCommand {
    Save,
    Reload,
}

#[derive(Resource, Debug, Default)]
pub(crate) struct SocketEditorState {
    loaded_model_path: Option<String>,
    document: Option<GltfSocketDocument>,
    selected_socket: Option<usize>,
    draft: SocketDraft,
    pub(crate) status: Option<String>,
    pub(crate) dirty: bool,
}

#[derive(Debug, Clone)]
struct GltfSocketDocument {
    absolute_path: PathBuf,
    relative_path: String,
    json: Value,
    sockets: Vec<SocketNode>,
    node_labels: Vec<NodeLabel>,
    default_parent_index: Option<usize>,
}

#[derive(Debug, Clone)]
struct NodeLabel {
    index: usize,
    label: String,
}

#[derive(Debug, Clone)]
struct SocketNode {
    node_index: usize,
    name: String,
    parent_index: Option<usize>,
    local_transform: SocketTransform,
    world_transform: SocketTransform,
}

#[derive(Debug, Clone)]
struct SocketDraft {
    name: String,
    parent_index: Option<usize>,
    transform: SocketTransform,
}

impl Default for SocketDraft {
    fn default() -> Self {
        Self {
            name: "new_socket".to_string(),
            parent_index: None,
            transform: SocketTransform::default(),
        }
    }
}

#[derive(Debug, Clone, Copy)]
struct SocketTransform {
    translation: Vec3,
    rotation_degrees: Vec3,
    scale: Vec3,
}

impl Default for SocketTransform {
    fn default() -> Self {
        Self {
            translation: Vec3::ZERO,
            rotation_degrees: Vec3::ZERO,
            scale: Vec3::ONE,
        }
    }
}

pub(crate) fn sync_socket_editor_document_system(
    asset_root: Res<ViewerAssetRoot>,
    ui_state: Res<ViewerUiState>,
    mut editor: ResMut<SocketEditorState>,
) {
    if editor.loaded_model_path == ui_state.selected_model_path {
        return;
    }

    editor.loaded_model_path = ui_state.selected_model_path.clone();
    editor.document = None;
    editor.selected_socket = None;
    editor.dirty = false;

    let Some(path) = ui_state.selected_model_path.as_deref() else {
        editor.status = Some("未选择 glTF 模型".to_string());
        return;
    };
    match GltfSocketDocument::load(&asset_root.0, path) {
        Ok(document) => {
            let socket_count = document.sockets.len();
            editor.draft.parent_index = document.default_parent_index;
            editor.status = Some(format!("已加载 socket: {socket_count}"));
            editor.document = Some(document);
        }
        Err(error) => {
            editor.status = Some(error);
        }
    }
}

pub(crate) fn handle_socket_editor_commands_system(
    mut requests: MessageReader<SocketEditorCommand>,
    asset_root: Res<ViewerAssetRoot>,
    asset_server: Res<AssetServer>,
    mut editor: ResMut<SocketEditorState>,
    mut preview_state: ResMut<PreviewState>,
) {
    for request in requests.read() {
        match request {
            SocketEditorCommand::Reload => {
                let Some(path) = editor.loaded_model_path.clone() else {
                    editor.status = Some("未选择 glTF 模型".to_string());
                    continue;
                };
                match GltfSocketDocument::load(&asset_root.0, &path) {
                    Ok(document) => {
                        editor.selected_socket = None;
                        editor.draft.parent_index = document.default_parent_index;
                        editor.dirty = false;
                        editor.status = Some("已重新加载 socket 文档".to_string());
                        editor.document = Some(document);
                    }
                    Err(error) => editor.status = Some(error),
                }
            }
            SocketEditorCommand::Save => {
                let Some(document) = editor.document.as_mut() else {
                    editor.status = Some("当前没有可保存的 glTF socket 文档".to_string());
                    continue;
                };
                match document.save_with_backup() {
                    Ok(backup_dir) => {
                        let asset_path = document.relative_path.clone();
                        asset_server
                            .reload(GltfAssetLabel::Scene(0).from_asset(asset_path.clone()));
                        preview_state.applied_model_path = None;
                        preview_state.framed_model_path = None;
                        preview_state.requested_model_path = Some(asset_path);
                        preview_state.load_status = crate::state::PreviewLoadStatus::Loading;
                        editor.dirty = false;
                        editor.status =
                            Some(format!("已保存 socket，备份: {}", backup_dir.display()));
                    }
                    Err(error) => editor.status = Some(error),
                }
            }
        }
    }
}

pub(crate) fn socket_editor_ui_system(
    mut contexts: EguiContexts,
    ui_state: Res<ViewerUiState>,
    mut editor: ResMut<SocketEditorState>,
    mut requests: MessageWriter<SocketEditorCommand>,
) {
    if !ui_state.show_socket_editor {
        return;
    }
    let Ok(ctx) = contexts.ctx_mut() else {
        return;
    };

    egui::SidePanel::right("socket_editor_panel")
        .resizable(false)
        .exact_width(340.0)
        .show(ctx, |ui| {
            ui.heading("Socket 编辑");
            ui.small(
                ui_state
                    .selected_model_path
                    .as_deref()
                    .unwrap_or("未选择模型"),
            );
            if let Some(status) = editor.status.as_deref() {
                ui.small(status);
            }
            ui.separator();

            if editor.document.is_none() {
                ui.label("当前模型不是可编辑 .gltf。");
                return;
            }
            let mut document = editor.document.take().expect("document exists");

            render_socket_list(ui, &mut editor, &mut document);
            ui.separator();
            render_socket_form(ui, &mut editor, &mut document);
            ui.separator();
            ui.horizontal(|ui| {
                if ui.button("保存").clicked() {
                    requests.write(SocketEditorCommand::Save);
                }
                if ui.button("重新从文件加载").clicked() {
                    requests.write(SocketEditorCommand::Reload);
                }
            });
            if editor.dirty {
                ui.small("有未保存 socket 修改。");
            }
            editor.document = Some(document);
        });
}

pub(crate) fn draw_socket_gizmos_system(
    ui_state: Res<ViewerUiState>,
    editor: Res<SocketEditorState>,
    mut gizmos: Gizmos,
) {
    if !ui_state.show_socket_editor {
        return;
    }
    let Some(document) = editor.document.as_ref() else {
        return;
    };
    for (socket_index, socket) in document.sockets.iter().enumerate() {
        let selected = editor.selected_socket == Some(socket_index);
        draw_socket_gizmo(
            &mut gizmos,
            socket.world_transform.translation,
            socket.world_transform.rotation_degrees,
            selected,
        );
    }
}

fn render_socket_list(
    ui: &mut egui::Ui,
    editor: &mut SocketEditorState,
    document: &mut GltfSocketDocument,
) {
    ui.horizontal(|ui| {
        ui.label(format!("Sockets: {}", document.sockets.len()));
        if ui.button("新增").clicked() {
            match document.create_socket(&editor.draft) {
                Ok(index) => {
                    editor.selected_socket = Some(index);
                    editor.draft = document.draft_for_socket(index);
                    editor.dirty = true;
                    editor.status = Some("已新增 socket，尚未保存".to_string());
                }
                Err(error) => editor.status = Some(error),
            }
        }
        if ui
            .add_enabled(editor.selected_socket.is_some(), egui::Button::new("删除"))
            .clicked()
        {
            if let Some(index) = editor.selected_socket.take() {
                match document.delete_socket(index) {
                    Ok(()) => {
                        editor.draft = SocketDraft {
                            parent_index: document.default_parent_index,
                            ..SocketDraft::default()
                        };
                        editor.dirty = true;
                        editor.status = Some("已删除 socket，尚未保存".to_string());
                    }
                    Err(error) => editor.status = Some(error),
                }
            }
        }
    });

    egui::ScrollArea::vertical()
        .max_height(180.0)
        .show(ui, |ui| {
            let entries = document
                .sockets
                .iter()
                .enumerate()
                .map(|(index, socket)| (index, socket.name.clone()))
                .collect::<Vec<_>>();
            for (index, name) in entries {
                let selected = editor.selected_socket == Some(index);
                if ui.selectable_label(selected, name).clicked() && !selected {
                    editor.selected_socket = Some(index);
                    editor.draft = document.draft_for_socket(index);
                }
            }
        });
}

fn render_socket_form(
    ui: &mut egui::Ui,
    editor: &mut SocketEditorState,
    document: &mut GltfSocketDocument,
) {
    ui.label("名称");
    egui::ComboBox::from_id_salt("socket_preset")
        .selected_text("选择预设")
        .show_ui(ui, |ui| {
            for preset in SOCKET_PRESETS {
                if ui.button(*preset).clicked() {
                    editor.draft.name = (*preset).to_string();
                }
            }
        });
    ui.text_edit_singleline(&mut editor.draft.name);

    ui.add_space(6.0);
    ui.label("父节点");
    let parent_label = editor
        .draft
        .parent_index
        .and_then(|index| document.node_label(index))
        .unwrap_or("Scene Root");
    egui::ComboBox::from_id_salt("socket_parent")
        .selected_text(parent_label)
        .show_ui(ui, |ui| {
            if ui
                .selectable_label(editor.draft.parent_index.is_none(), "Scene Root")
                .clicked()
            {
                editor.draft.parent_index = document.default_parent_index;
            }
            for label in &document.node_labels {
                if ui
                    .selectable_label(
                        editor.draft.parent_index == Some(label.index),
                        label.label.as_str(),
                    )
                    .clicked()
                {
                    editor.draft.parent_index = Some(label.index);
                }
            }
        });

    ui.add_space(6.0);
    let mut transform_changed = false;
    transform_changed |= render_vec3(ui, "位置", &mut editor.draft.transform.translation, 0.01);
    transform_changed |= render_vec3(
        ui,
        "旋转",
        &mut editor.draft.transform.rotation_degrees,
        1.0,
    );
    transform_changed |= render_vec3(ui, "缩放", &mut editor.draft.transform.scale, 0.01);
    if transform_changed {
        if let Some(index) = editor.selected_socket {
            match document.update_socket(index, &editor.draft) {
                Ok(()) => {
                    editor.dirty = true;
                    editor.status = Some("已更新 socket 变换，尚未保存".to_string());
                }
                Err(error) => editor.status = Some(error),
            }
        }
    }

    let selected = editor.selected_socket.is_some();
    if ui
        .add_enabled(selected, egui::Button::new("应用到选中 Socket"))
        .clicked()
    {
        if let Some(index) = editor.selected_socket {
            match document.update_socket(index, &editor.draft) {
                Ok(()) => {
                    editor.dirty = true;
                    editor.status = Some("已应用 socket 修改，尚未保存".to_string());
                }
                Err(error) => editor.status = Some(error),
            }
        }
    }
    if !editor.draft.name.trim().ends_with("_socket")
        && !SOCKET_PRESETS.contains(&editor.draft.name.trim())
    {
        ui.small("建议自定义名称以 _socket 结尾。");
    }
}

fn render_vec3(ui: &mut egui::Ui, label: &str, value: &mut Vec3, speed: f32) -> bool {
    let mut changed = false;
    ui.horizontal(|ui| {
        ui.label(label);
        changed |= ui
            .add(egui::DragValue::new(&mut value.x).speed(speed).prefix("X "))
            .changed();
        changed |= ui
            .add(egui::DragValue::new(&mut value.y).speed(speed).prefix("Y "))
            .changed();
        changed |= ui
            .add(egui::DragValue::new(&mut value.z).speed(speed).prefix("Z "))
            .changed();
    });
    changed
}

impl GltfSocketDocument {
    fn load(asset_root: &Path, relative_path: &str) -> Result<Self, String> {
        if !relative_path.ends_with(".gltf") {
            return Err("Socket 编辑仅支持 .gltf".to_string());
        }
        let absolute_path = asset_root.join(relative_path);
        let raw = fs::read_to_string(&absolute_path)
            .map_err(|error| format!("读取 glTF 失败 {}: {error}", absolute_path.display()))?;
        let json: Value = serde_json::from_str(&raw)
            .map_err(|error| format!("解析 glTF JSON 失败 {}: {error}", absolute_path.display()))?;
        let mut document = Self {
            absolute_path,
            relative_path: relative_path.to_string(),
            json,
            sockets: Vec::new(),
            node_labels: Vec::new(),
            default_parent_index: None,
        };
        document.refresh();
        Ok(document)
    }

    fn refresh(&mut self) {
        self.node_labels = self.collect_node_labels();
        self.default_parent_index = self.first_scene_root();
        self.sockets = self.collect_socket_nodes();
    }

    fn draft_for_socket(&self, socket_index: usize) -> SocketDraft {
        let Some(socket) = self.sockets.get(socket_index) else {
            return SocketDraft::default();
        };
        SocketDraft {
            name: socket.name.clone(),
            parent_index: socket.parent_index,
            transform: socket.local_transform,
        }
    }

    fn node_label(&self, node_index: usize) -> Option<&str> {
        self.node_labels
            .iter()
            .find(|label| label.index == node_index)
            .map(|label| label.label.as_str())
    }

    fn create_socket(&mut self, draft: &SocketDraft) -> Result<usize, String> {
        self.validate_draft(draft, None)?;
        let parent_index = draft.parent_index.or(self.default_parent_index);
        let node_index = self.nodes()?.len();
        let mut node = Map::new();
        node.insert(
            "name".to_string(),
            Value::String(draft.name.trim().to_string()),
        );
        write_transform_fields(&mut node, draft.transform);
        write_socket_extras(&mut node);
        self.nodes_mut()?.push(Value::Object(node));
        if let Some(parent_index) = parent_index {
            add_child_index(self.node_mut(parent_index)?, node_index)?;
        }
        self.refresh();
        self.sockets
            .iter()
            .position(|socket| socket.node_index == node_index)
            .ok_or_else(|| "新增 socket 后无法定位节点".to_string())
    }

    fn update_socket(&mut self, socket_index: usize, draft: &SocketDraft) -> Result<(), String> {
        let Some(socket) = self.sockets.get(socket_index).cloned() else {
            return Err("未选择有效 socket".to_string());
        };
        self.validate_draft(draft, Some(socket.node_index))?;
        let parent_index = draft.parent_index.or(self.default_parent_index);
        if parent_index == Some(socket.node_index) {
            return Err("socket 不能把自己设为父节点".to_string());
        }
        if let Some(parent_index) = parent_index {
            if self.is_descendant(parent_index, socket.node_index) {
                return Err("socket 不能挂到自己的子节点下".to_string());
            }
        }

        if socket.parent_index != parent_index {
            if let Some(old_parent) = socket.parent_index {
                remove_child_index(self.node_mut(old_parent)?, socket.node_index);
            }
            if let Some(new_parent) = parent_index {
                add_child_index(self.node_mut(new_parent)?, socket.node_index)?;
            }
        }

        let node = self.node_mut(socket.node_index)?;
        let object = node
            .as_object_mut()
            .ok_or_else(|| "glTF node 不是对象".to_string())?;
        object.insert(
            "name".to_string(),
            Value::String(draft.name.trim().to_string()),
        );
        object.remove("matrix");
        write_transform_fields(object, draft.transform);
        write_socket_extras(object);
        self.refresh();
        Ok(())
    }

    fn delete_socket(&mut self, socket_index: usize) -> Result<(), String> {
        let Some(socket) = self.sockets.get(socket_index).cloned() else {
            return Err("未选择有效 socket".to_string());
        };
        for node in self.nodes_mut()? {
            if let Some(object) = node.as_object_mut() {
                remove_child_index_from_object(object, socket.node_index);
            }
        }
        let node = self.node_mut(socket.node_index)?;
        let object = node
            .as_object_mut()
            .ok_or_else(|| "glTF node 不是对象".to_string())?;
        object.insert(
            "name".to_string(),
            Value::String(format!("{}_deleted", socket.name)),
        );
        object.remove("extras");
        self.refresh();
        Ok(())
    }

    fn save_with_backup(&self) -> Result<PathBuf, String> {
        let backup_dir = backup_dir_for(&self.absolute_path)?;
        fs::create_dir_all(&backup_dir)
            .map_err(|error| format!("创建备份目录失败 {}: {error}", backup_dir.display()))?;
        let backup_path = backup_dir.join(
            self.absolute_path
                .file_name()
                .unwrap_or_else(|| std::ffi::OsStr::new("asset.gltf")),
        );
        fs::copy(&self.absolute_path, &backup_path).map_err(|error| {
            format!(
                "备份 glTF 失败 {} -> {}: {error}",
                self.absolute_path.display(),
                backup_path.display()
            )
        })?;
        let raw = serde_json::to_string_pretty(&self.json)
            .map_err(|error| format!("序列化 glTF 失败: {error}"))?;
        fs::write(&self.absolute_path, format!("{raw}\n"))
            .map_err(|error| format!("写入 glTF 失败 {}: {error}", self.absolute_path.display()))?;
        Ok(backup_dir)
    }

    fn validate_draft(
        &self,
        draft: &SocketDraft,
        existing_node: Option<usize>,
    ) -> Result<(), String> {
        let name = draft.name.trim();
        if name.is_empty() {
            return Err("socket 名称不能为空".to_string());
        }
        if self.sockets.iter().any(|socket| {
            socket.node_index != existing_node.unwrap_or(usize::MAX) && socket.name == name
        }) {
            return Err(format!("socket 名称已存在: {name}"));
        }
        if draft.transform.scale.x <= 0.0
            || draft.transform.scale.y <= 0.0
            || draft.transform.scale.z <= 0.0
        {
            return Err("socket 缩放必须大于 0".to_string());
        }
        Ok(())
    }

    fn collect_node_labels(&self) -> Vec<NodeLabel> {
        self.nodes()
            .unwrap_or(&[])
            .iter()
            .enumerate()
            .map(|(index, node)| {
                let name = node
                    .get("name")
                    .and_then(Value::as_str)
                    .filter(|name| !name.trim().is_empty())
                    .unwrap_or("<unnamed>");
                NodeLabel {
                    index,
                    label: format!("{index}: {name}"),
                }
            })
            .collect()
    }

    fn collect_socket_nodes(&self) -> Vec<SocketNode> {
        let parents = self.parent_indices();
        let world_transforms = self.world_transforms(&parents);
        self.nodes()
            .unwrap_or(&[])
            .iter()
            .enumerate()
            .filter_map(|(node_index, node)| {
                let name = node.get("name").and_then(Value::as_str)?.trim().to_string();
                if !is_socket_node(node, name.as_str()) {
                    return None;
                }
                Some(SocketNode {
                    node_index,
                    name,
                    parent_index: parents.get(node_index).copied().flatten(),
                    local_transform: read_node_transform(node),
                    world_transform: world_transforms
                        .get(node_index)
                        .copied()
                        .unwrap_or_else(|| read_node_transform(node)),
                })
            })
            .collect()
    }

    fn parent_indices(&self) -> Vec<Option<usize>> {
        let nodes = self.nodes().unwrap_or(&[]);
        let mut parents = vec![None; nodes.len()];
        for (parent_index, node) in nodes.iter().enumerate() {
            if let Some(children) = node.get("children").and_then(Value::as_array) {
                for child in children {
                    if let Some(child_index) = child.as_u64().map(|value| value as usize) {
                        if child_index < parents.len() {
                            parents[child_index] = Some(parent_index);
                        }
                    }
                }
            }
        }
        parents
    }

    fn world_transforms(&self, parents: &[Option<usize>]) -> Vec<SocketTransform> {
        let nodes = self.nodes().unwrap_or(&[]);
        let locals = nodes
            .iter()
            .map(read_node_transform)
            .map(socket_transform_to_mat4)
            .collect::<Vec<_>>();
        let mut worlds = vec![None; nodes.len()];
        for index in 0..nodes.len() {
            compute_world_matrix(index, parents, &locals, &mut worlds);
        }
        worlds
            .into_iter()
            .map(|matrix| mat4_to_socket_transform(matrix.unwrap_or(Mat4::IDENTITY)))
            .collect()
    }

    fn is_descendant(&self, node_index: usize, possible_ancestor: usize) -> bool {
        let Some(node) = self.nodes().ok().and_then(|nodes| nodes.get(node_index)) else {
            return false;
        };
        let Some(children) = node.get("children").and_then(Value::as_array) else {
            return false;
        };
        for child in children {
            let Some(child_index) = child.as_u64().map(|value| value as usize) else {
                continue;
            };
            if child_index == possible_ancestor
                || self.is_descendant(child_index, possible_ancestor)
            {
                return true;
            }
        }
        false
    }

    fn first_scene_root(&self) -> Option<usize> {
        let scene_index = self.json.get("scene").and_then(Value::as_u64).unwrap_or(0) as usize;
        self.json
            .get("scenes")
            .and_then(Value::as_array)
            .and_then(|scenes| scenes.get(scene_index))
            .and_then(|scene| scene.get("nodes"))
            .and_then(Value::as_array)
            .and_then(|nodes| nodes.first())
            .and_then(Value::as_u64)
            .map(|value| value as usize)
    }

    fn nodes(&self) -> Result<&[Value], String> {
        self.json
            .get("nodes")
            .and_then(Value::as_array)
            .map(Vec::as_slice)
            .ok_or_else(|| "glTF 缺少 nodes 数组".to_string())
    }

    fn nodes_mut(&mut self) -> Result<&mut Vec<Value>, String> {
        self.json
            .get_mut("nodes")
            .and_then(Value::as_array_mut)
            .ok_or_else(|| "glTF 缺少 nodes 数组".to_string())
    }

    fn node_mut(&mut self, index: usize) -> Result<&mut Value, String> {
        self.nodes_mut()?
            .get_mut(index)
            .ok_or_else(|| format!("glTF node index 不存在: {index}"))
    }
}

fn is_socket_node(node: &Value, name: &str) -> bool {
    SOCKET_PRESETS.contains(&name)
        || name.ends_with("_socket")
        || node
            .get("extras")
            .and_then(|extras| extras.get("cdc_socket"))
            .and_then(Value::as_bool)
            .unwrap_or(false)
}

fn read_node_transform(node: &Value) -> SocketTransform {
    if let Some(matrix) = node.get("matrix").and_then(read_f32_array::<16>) {
        return mat4_to_socket_transform(Mat4::from_cols_array(&matrix));
    }
    let translation = node
        .get("translation")
        .and_then(read_f32_array::<3>)
        .map(|value| Vec3::new(value[0], value[1], value[2]))
        .unwrap_or(Vec3::ZERO);
    let rotation = node
        .get("rotation")
        .and_then(read_f32_array::<4>)
        .map(|value| Quat::from_xyzw(value[0], value[1], value[2], value[3]))
        .unwrap_or(Quat::IDENTITY);
    let scale = node
        .get("scale")
        .and_then(read_f32_array::<3>)
        .map(|value| Vec3::new(value[0], value[1], value[2]))
        .unwrap_or(Vec3::ONE);
    let (x, y, z) = rotation.to_euler(EulerRot::XYZ);
    SocketTransform {
        translation,
        rotation_degrees: Vec3::new(x.to_degrees(), y.to_degrees(), z.to_degrees()),
        scale,
    }
}

fn read_f32_array<const N: usize>(value: &Value) -> Option<[f32; N]> {
    let array = value.as_array()?;
    if array.len() != N {
        return None;
    }
    let mut output = [0.0; N];
    for (index, value) in array.iter().enumerate() {
        output[index] = value.as_f64()? as f32;
    }
    Some(output)
}

fn write_transform_fields(object: &mut Map<String, Value>, transform: SocketTransform) {
    object.insert("translation".to_string(), value_vec3(transform.translation));
    object.insert(
        "rotation".to_string(),
        value_quat(Quat::from_euler(
            EulerRot::XYZ,
            transform.rotation_degrees.x.to_radians(),
            transform.rotation_degrees.y.to_radians(),
            transform.rotation_degrees.z.to_radians(),
        )),
    );
    object.insert("scale".to_string(), value_vec3(transform.scale));
}

fn write_socket_extras(object: &mut Map<String, Value>) {
    let extras = object
        .entry("extras".to_string())
        .or_insert_with(|| Value::Object(Map::new()));
    if !extras.is_object() {
        *extras = Value::Object(Map::new());
    }
    if let Some(extras) = extras.as_object_mut() {
        extras.insert("cdc_socket".to_string(), Value::Bool(true));
    }
}

fn value_vec3(value: Vec3) -> Value {
    Value::Array(vec![
        value_number(value.x),
        value_number(value.y),
        value_number(value.z),
    ])
}

fn value_quat(value: Quat) -> Value {
    Value::Array(vec![
        value_number(value.x),
        value_number(value.y),
        value_number(value.z),
        value_number(value.w),
    ])
}

fn value_number(value: f32) -> Value {
    Value::Number(Number::from_f64(value as f64).unwrap_or_else(|| Number::from(0)))
}

fn add_child_index(parent_node: &mut Value, child_index: usize) -> Result<(), String> {
    let object = parent_node
        .as_object_mut()
        .ok_or_else(|| "父 glTF node 不是对象".to_string())?;
    let children = object
        .entry("children".to_string())
        .or_insert_with(|| Value::Array(Vec::new()));
    if !children.is_array() {
        *children = Value::Array(Vec::new());
    }
    let Some(children) = children.as_array_mut() else {
        return Err("父 glTF node children 不是数组".to_string());
    };
    if !children
        .iter()
        .any(|value| value.as_u64() == Some(child_index as u64))
    {
        children.push(Value::Number(Number::from(child_index)));
    }
    Ok(())
}

fn remove_child_index(node: &mut Value, child_index: usize) {
    if let Some(object) = node.as_object_mut() {
        remove_child_index_from_object(object, child_index);
    }
}

fn remove_child_index_from_object(object: &mut Map<String, Value>, child_index: usize) {
    if let Some(children) = object.get_mut("children").and_then(Value::as_array_mut) {
        children.retain(|value| value.as_u64() != Some(child_index as u64));
    }
}

fn socket_transform_to_mat4(transform: SocketTransform) -> Mat4 {
    Mat4::from_scale_rotation_translation(
        transform.scale,
        Quat::from_euler(
            EulerRot::XYZ,
            transform.rotation_degrees.x.to_radians(),
            transform.rotation_degrees.y.to_radians(),
            transform.rotation_degrees.z.to_radians(),
        ),
        transform.translation,
    )
}

fn mat4_to_socket_transform(matrix: Mat4) -> SocketTransform {
    let (scale, rotation, translation) = matrix.to_scale_rotation_translation();
    let (x, y, z) = rotation.to_euler(EulerRot::XYZ);
    SocketTransform {
        translation,
        rotation_degrees: Vec3::new(x.to_degrees(), y.to_degrees(), z.to_degrees()),
        scale,
    }
}

fn compute_world_matrix(
    index: usize,
    parents: &[Option<usize>],
    locals: &[Mat4],
    worlds: &mut [Option<Mat4>],
) -> Mat4 {
    if let Some(world) = worlds.get(index).and_then(|world| *world) {
        return world;
    }
    let local = locals.get(index).copied().unwrap_or(Mat4::IDENTITY);
    let world = parents
        .get(index)
        .copied()
        .flatten()
        .map(|parent| compute_world_matrix(parent, parents, locals, worlds) * local)
        .unwrap_or(local);
    if let Some(slot) = worlds.get_mut(index) {
        *slot = Some(world);
    }
    world
}

fn draw_socket_gizmo(gizmos: &mut Gizmos, origin: Vec3, rotation_degrees: Vec3, selected: bool) {
    let rotation = Quat::from_euler(
        EulerRot::XYZ,
        rotation_degrees.x.to_radians(),
        rotation_degrees.y.to_radians(),
        rotation_degrees.z.to_radians(),
    );
    let axis_length = if selected { 0.44 } else { 0.28 };
    let marker_radius = if selected { 0.07 } else { 0.045 };
    let marker_color = if selected {
        Color::srgb(1.0, 0.82, 0.18)
    } else {
        Color::srgba(0.88, 0.92, 1.0, 0.78)
    };
    for axis in [Vec3::X, Vec3::Y, Vec3::Z] {
        let axis = rotation * axis;
        gizmos.line(
            origin - axis * marker_radius,
            origin + axis * marker_radius,
            marker_color,
        );
    }
    gizmos.line(
        origin,
        origin + rotation * Vec3::X * axis_length,
        Color::srgb(1.0, 0.16, 0.12),
    );
    gizmos.line(
        origin,
        origin + rotation * Vec3::Y * axis_length,
        Color::srgb(0.16, 0.9, 0.24),
    );
    gizmos.line(
        origin,
        origin + rotation * Vec3::Z * axis_length,
        Color::srgb(0.16, 0.36, 1.0),
    );
}

fn backup_dir_for(path: &Path) -> Result<PathBuf, String> {
    let parent = path
        .parent()
        .ok_or_else(|| format!("无法解析 glTF 目录: {}", path.display()))?;
    let stem = path
        .file_stem()
        .and_then(|value| value.to_str())
        .unwrap_or("asset");
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|error| format!("系统时间无效: {error}"))?
        .as_secs();
    Ok(parent
        .join(".cdc_gltf_backups")
        .join(format!("{stem}-{timestamp}")))
}

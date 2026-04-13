mod ai_provider;
mod ai_settings;
mod editor_menu;
mod narrative_agent_actions;
mod narrative_app_settings;
mod narrative_context;
mod narrative_exports;
mod narrative_provider;
mod narrative_review;
mod narrative_sync;
mod narrative_templates;
mod narrative_workspace;

use std::path::Path;

use serde::{Deserialize, Serialize};
use tauri::Manager;

use crate::ai_provider::test_ai_provider;
use crate::ai_settings::{load_ai_settings, save_ai_settings};
use crate::narrative_agent_actions::execute_narrative_agent_action;
use crate::narrative_app_settings::{load_narrative_app_settings, save_narrative_app_settings};
use crate::narrative_exports::{
    export_narrative_chat_regression_report, export_narrative_session_summary,
};
use crate::narrative_provider::{
    cancel_narrative_request, generate_narrative_draft, resolve_narrative_action_intent,
    revise_narrative_draft, NarrativeRequestRegistry,
};
use crate::narrative_sync::{
    create_cloud_workspace, export_project_context_snapshot, list_cloud_workspaces,
    load_narrative_sync_settings, save_narrative_sync_settings, sync_narrative_workspace,
    upload_project_context_snapshot,
};
use crate::narrative_workspace::{
    create_narrative_document, delete_narrative_document, load_narrative_document,
    load_narrative_workspace, open_narrative_document_folder, prepare_structuring_bundle,
    save_narrative_document, summarize_narrative_document,
};

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct MigrationStage {
    pub(crate) id: &'static str,
    pub(crate) title: &'static str,
    pub(crate) description: &'static str,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct EditorBootstrap {
    pub(crate) app_name: &'static str,
    pub(crate) workspace_root: String,
    pub(crate) shared_rust_path: String,
    pub(crate) active_stage: &'static str,
    pub(crate) stages: Vec<MigrationStage>,
    pub(crate) editor_domains: Vec<&'static str>,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct EditorRuntimeFlags {
    menu_self_test_scenario: Option<String>,
    chat_regression_mode: Option<String>,
    auto_close_after_self_test: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct ValidationIssue {
    pub(crate) severity: String,
    pub(crate) field: String,
    pub(crate) message: String,
    pub(crate) scope: Option<String>,
    pub(crate) node_id: Option<String>,
    pub(crate) edge_key: Option<String>,
    pub(crate) path: Option<String>,
}

pub(crate) fn document_error(
    field: impl Into<String>,
    message: impl Into<String>,
) -> ValidationIssue {
    ValidationIssue {
        severity: "error".to_string(),
        field: field.into(),
        message: message.into(),
        scope: None,
        node_id: None,
        edge_key: None,
        path: None,
    }
}

#[allow(dead_code)]
pub(crate) fn node_error(
    field: impl Into<String>,
    node_id: impl Into<String>,
    message: impl Into<String>,
) -> ValidationIssue {
    ValidationIssue {
        severity: "error".to_string(),
        field: field.into(),
        message: message.into(),
        scope: Some("node".to_string()),
        node_id: Some(node_id.into()),
        edge_key: None,
        path: None,
    }
}

#[allow(dead_code)]
pub(crate) fn edge_error(
    field: impl Into<String>,
    edge_key: impl Into<String>,
    message: impl Into<String>,
) -> ValidationIssue {
    ValidationIssue {
        severity: "error".to_string(),
        field: field.into(),
        message: message.into(),
        scope: Some("edge".to_string()),
        node_id: None,
        edge_key: Some(edge_key.into()),
        path: None,
    }
}

#[tauri::command]
fn get_editor_runtime_flags() -> Result<EditorRuntimeFlags, String> {
    let menu_self_test_scenario = std::env::var("CDC_EDITOR_SELF_TEST")
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty());
    let chat_regression_mode = std::env::var("CDC_NARRATIVE_CHAT_REGRESSION_MODE")
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty());
    let auto_close_after_self_test = std::env::var("CDC_EDITOR_SELF_TEST_AUTOCLOSE")
        .ok()
        .map(|value| matches!(value.trim(), "1" | "true" | "TRUE" | "yes" | "YES"))
        .unwrap_or(false);

    if let Some(scenario) = &menu_self_test_scenario {
        eprintln!(
            "[editor-self-test] runtime self-test scenario requested: {}",
            scenario
        );
    }

    Ok(EditorRuntimeFlags {
        menu_self_test_scenario,
        chat_regression_mode,
        auto_close_after_self_test,
    })
}

#[tauri::command]
fn log_editor_frontend_debug(
    level: String,
    message: String,
    payload: Option<String>,
) -> Result<(), String> {
    match payload {
        Some(payload) if !payload.is_empty() => {
            eprintln!("[editor-menu][frontend][{}] {} {}", level, message, payload);
        }
        _ => {
            eprintln!("[editor-menu][frontend][{}] {}", level, message);
        }
    }
    Ok(())
}

pub(crate) fn to_forward_slashes(path: impl AsRef<Path>) -> String {
    let raw = path.as_ref().to_string_lossy().replace('\\', "/");
    if let Some(stripped) = raw.strip_prefix("//?/UNC/") {
        return format!("//{stripped}");
    }
    if let Some(stripped) = raw.strip_prefix("//?/") {
        return stripped.to_string();
    }
    raw
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .setup(|app| {
            eprintln!("[editor-menu] setup start");
            app.manage(editor_menu::EditorMenuState::default());
            app.manage(NarrativeRequestRegistry::default());
            editor_menu::apply_window_menu(&app.handle(), "main")?;
            if let Some(window) = app.get_webview_window("main") {
                editor_menu::attach_window_menu_listener(window);
                editor_menu::remember_focused_editor_window(&app.handle(), "main", true);
            } else {
                eprintln!("[editor-menu] main window not available during setup");
            }
            eprintln!("[editor-menu] setup complete");
            Ok(())
        })
        .on_page_load(|webview, _payload| {
            eprintln!(
                "[editor-menu] page load window={} url={:?}",
                webview.label(),
                webview.url()
            );
            let _ = editor_menu::apply_window_menu(&webview.app_handle(), webview.label());
            if let Some(window) = webview.app_handle().get_webview_window(webview.label()) {
                editor_menu::attach_window_menu_listener(window);
            } else {
                eprintln!(
                    "[editor-menu] page load could not resolve window handle for {}",
                    webview.label()
                );
            }
        })
        .on_window_event(|window, event| {
            match event {
                tauri::WindowEvent::Focused(focused) => {
                    eprintln!(
                        "[editor-menu] window focus event window={} focused={}",
                        window.label(),
                        focused
                    );
                    editor_menu::remember_focused_editor_window(
                        &window.app_handle(),
                        window.label(),
                        *focused,
                    );
                }
                tauri::WindowEvent::CloseRequested { .. } | tauri::WindowEvent::Destroyed => {
                    if window.label() == "main" {
                        if let Some(settings_window) =
                            window.app_handle().get_webview_window("settings")
                        {
                            if let Err(error) = settings_window.close() {
                                eprintln!(
                                    "[editor-menu] failed to close settings window when main closed: {}",
                                    error
                                );
                            }
                        }
                    }
                }
                _ => {}
            }
        })
        .invoke_handler(tauri::generate_handler![
            get_editor_runtime_flags,
            log_editor_frontend_debug,
            load_narrative_workspace,
            load_narrative_document,
            save_narrative_document,
            create_narrative_document,
            delete_narrative_document,
            open_narrative_document_folder,
            summarize_narrative_document,
            prepare_structuring_bundle,
            load_narrative_sync_settings,
            save_narrative_sync_settings,
            list_cloud_workspaces,
            create_cloud_workspace,
            sync_narrative_workspace,
            export_project_context_snapshot,
            upload_project_context_snapshot,
            load_ai_settings,
            save_ai_settings,
            load_narrative_app_settings,
            save_narrative_app_settings,
            export_narrative_session_summary,
            export_narrative_chat_regression_report,
            test_ai_provider,
            execute_narrative_agent_action,
            resolve_narrative_action_intent,
            cancel_narrative_request,
            generate_narrative_draft,
            revise_narrative_draft
        ])
        .run(tauri::generate_context!())
        .expect("error while running CDC content editor");
}

use std::path::Path;
use std::process::Command;
use std::time::Duration;

use game_editor::{
    item_editor_session_is_recent, read_item_editor_session, write_item_editor_selection_request,
};

const ITEM_EDITOR_ACTIVE_MAX_AGE: Duration = Duration::from_secs(5);

pub(crate) fn open_item_in_editor(repo_root: &Path, item_id: u32) -> Result<String, String> {
    write_item_editor_selection_request(repo_root, item_id)?;

    if item_editor_session_is_recent(repo_root, ITEM_EDITOR_ACTIVE_MAX_AGE)? {
        let focused = focus_existing_item_editor(repo_root);
        return Ok(if focused {
            format!("Requested item editor to select item {item_id}.")
        } else {
            format!("Updated item editor selection to item {item_id}.")
        });
    }

    launch_item_editor(repo_root, item_id)?;
    Ok(format!(
        "Launched item editor and requested selection for item {item_id}."
    ))
}

fn launch_item_editor(repo_root: &Path, item_id: u32) -> Result<(), String> {
    let script_path = repo_root.join("run_bevy_item_editor.bat");
    if !script_path.exists() {
        return Err(format!(
            "item editor launcher is missing: {}",
            script_path.display()
        ));
    }

    let script = script_path.display().to_string();
    let item_id = item_id.to_string();
    let status = Command::new("cmd")
        .args(["/C", "start", "", &script, "--select-item", &item_id])
        .current_dir(repo_root)
        .status()
        .map_err(|error| format!("failed to launch item editor: {error}"))?;

    if status.success() {
        Ok(())
    } else {
        Err(format!(
            "item editor launcher exited with status {:?}",
            status.code()
        ))
    }
}

fn focus_existing_item_editor(repo_root: &Path) -> bool {
    let Ok(Some(session)) = read_item_editor_session(repo_root) else {
        return false;
    };

    for shell in ["pwsh", "powershell"] {
        let command = format!(
            "$wshell = New-Object -ComObject WScript.Shell; if ($wshell.AppActivate({})) {{ exit 0 }} else {{ exit 1 }}",
            session.pid
        );
        let Ok(status) = Command::new(shell)
            .args(["-NoProfile", "-Command", &command])
            .status()
        else {
            continue;
        };
        if status.success() {
            return true;
        }
    }

    false
}

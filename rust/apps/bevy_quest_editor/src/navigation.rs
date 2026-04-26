use std::path::Path;
use std::process::Command;
use std::time::Duration;

use game_editor::{
    editor_session_is_recent, read_editor_session, write_editor_navigation_request, EditorKind,
    EditorNavigationAction,
};

const DIALOGUE_EDITOR_ACTIVE_MAX_AGE: Duration = Duration::from_secs(5);

pub(crate) fn open_dialogue_in_editor(
    repo_root: &Path,
    dialogue_id: &str,
) -> Result<String, String> {
    write_editor_navigation_request(
        repo_root,
        EditorKind::Dialogue,
        EditorNavigationAction::SelectRecord,
        "dialogue",
        dialogue_id,
    )?;

    if editor_session_is_recent(
        repo_root,
        EditorKind::Dialogue,
        DIALOGUE_EDITOR_ACTIVE_MAX_AGE,
    )? {
        let focused = focus_existing_editor(repo_root, EditorKind::Dialogue);
        return Ok(if focused {
            format!("Requested dialogue editor to select dialogue {dialogue_id}.")
        } else {
            format!("Updated dialogue editor selection to dialogue {dialogue_id}.")
        });
    }

    launch_dialogue_editor(repo_root, dialogue_id)?;
    Ok(format!(
        "Launched dialogue editor and requested selection for dialogue {dialogue_id}."
    ))
}

fn launch_dialogue_editor(repo_root: &Path, dialogue_id: &str) -> Result<(), String> {
    let script_path = repo_root.join("run_bevy_dialogue_editor.bat");
    if !script_path.exists() {
        return Err(format!(
            "dialogue editor launcher is missing: {}",
            script_path.display()
        ));
    }

    let script = script_path.display().to_string();
    let status = Command::new("cmd")
        .args(["/C", "start", "", &script, "--select-dialogue", dialogue_id])
        .current_dir(repo_root)
        .status()
        .map_err(|error| format!("failed to launch dialogue editor: {error}"))?;

    if status.success() {
        Ok(())
    } else {
        Err(format!(
            "dialogue editor launcher exited with status {:?}",
            status.code()
        ))
    }
}

fn focus_existing_editor(repo_root: &Path, editor: EditorKind) -> bool {
    let Ok(Some(session)) = read_editor_session(repo_root, editor) else {
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

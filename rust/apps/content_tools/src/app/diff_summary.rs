use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

pub(super) fn print_diff_summary(repo_root: &Path, input_path: &str) -> Result<i32, String> {
    let relative_path = normalize_input_path(repo_root, input_path)?;
    let status_output = git_output(
        repo_root,
        &[
            "status",
            "--short",
            "--untracked-files=all",
            "--",
            &relative_path,
        ],
    )?;
    let status_line = status_output
        .lines()
        .next()
        .unwrap_or_default()
        .trim()
        .to_string();

    println!("mode: diff_summary");
    println!("path: {relative_path}");

    if status_line.is_empty() {
        println!("status: clean");
        println!("added_lines: 0");
        println!("removed_lines: 0");
        println!("changed_hunks: 0");
        return Ok(0);
    }

    if status_line.starts_with("??") {
        let line_count = fs::read_to_string(repo_root.join(&relative_path))
            .map(|raw| raw.lines().count())
            .unwrap_or(0);
        println!("status: untracked");
        println!("added_lines: {line_count}");
        println!("removed_lines: 0");
        println!("changed_hunks: 1");
        return Ok(0);
    }

    let numstat = git_output(
        repo_root,
        &["diff", "--numstat", "HEAD", "--", &relative_path],
    )?;
    let (added_lines, removed_lines) = parse_numstat(&numstat);
    let diff = git_output(
        repo_root,
        &[
            "diff",
            "--no-ext-diff",
            "--unified=0",
            "HEAD",
            "--",
            &relative_path,
        ],
    )?;
    let changed_hunks = diff.lines().filter(|line| line.starts_with("@@")).count();

    println!("status: {}", normalize_status_code(&status_line));
    println!("added_lines: {added_lines}");
    println!("removed_lines: {removed_lines}");
    println!("changed_hunks: {changed_hunks}");
    Ok(0)
}

fn normalize_input_path(repo_root: &Path, input_path: &str) -> Result<String, String> {
    let path = PathBuf::from(input_path);
    let absolute = if path.is_absolute() {
        path
    } else {
        repo_root.join(path)
    };
    let relative = absolute
        .strip_prefix(repo_root)
        .map_err(|_| format!("path is outside repo root: {}", absolute.display()))?;
    Ok(relative.to_string_lossy().replace('\\', "/"))
}

fn git_output(repo_root: &Path, args: &[&str]) -> Result<String, String> {
    let output = Command::new("git")
        .arg("-C")
        .arg(repo_root)
        .args(args)
        .output()
        .map_err(|error| format!("failed to run git {}: {error}", args.join(" ")))?;
    if !output.status.success() {
        return Err(format!(
            "git {} failed: {}",
            args.join(" "),
            String::from_utf8_lossy(&output.stderr).trim()
        ));
    }
    Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
}

fn parse_numstat(raw: &str) -> (usize, usize) {
    let Some(first_line) = raw.lines().next() else {
        return (0, 0);
    };
    let parts = first_line.split_whitespace().collect::<Vec<_>>();
    if parts.len() < 2 {
        return (0, 0);
    }
    let added = parts[0].parse::<usize>().unwrap_or(0);
    let removed = parts[1].parse::<usize>().unwrap_or(0);
    (added, removed)
}

fn normalize_status_code(status_line: &str) -> String {
    let code = status_line.chars().take(2).collect::<String>();
    match code.as_str() {
        " M" | "M " | "MM" => "modified".to_string(),
        "A " | "AM" => "added".to_string(),
        "R " | "RM" => "renamed".to_string(),
        " D" | "D " => "deleted".to_string(),
        other => format!("changed({})", other.trim()),
    }
}

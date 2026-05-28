//! UI 设置模块：负责读取、保存与应用 viewer 的界面缩放和按键绑定配置。

use super::*;

pub(crate) const VIEWER_RESOLUTION_PRESETS: [ViewerWindowResolution; 5] = [
    ViewerWindowResolution::new(1280, 720),
    ViewerWindowResolution::new(1440, 900),
    ViewerWindowResolution::new(1600, 900),
    ViewerWindowResolution::new(1920, 1080),
    ViewerWindowResolution::new(2560, 1440),
];

pub(crate) fn next_resolution_preset(current: ViewerWindowResolution) -> ViewerWindowResolution {
    let current_index = VIEWER_RESOLUTION_PRESETS
        .iter()
        .position(|preset| *preset == current)
        .unwrap_or_default();
    VIEWER_RESOLUTION_PRESETS[(current_index + 1) % VIEWER_RESOLUTION_PRESETS.len()]
}

pub(crate) fn load_ui_settings_on_startup(
    path: Res<ViewerUiSettingsPath>,
    mut settings: ResMut<ViewerUiSettings>,
) {
    if let Ok(raw) = fs::read_to_string(&path.0) {
        if let Ok(parsed) = serde_json::from_str::<ViewerUiSettings>(&raw) {
            *settings = parsed;
        }
    }
}

pub(crate) fn apply_ui_settings_system(
    settings: Res<ViewerUiSettings>,
    mut render_config: ResMut<ViewerRenderConfig>,
    mut ui_scale: ResMut<UiScale>,
    mut window: Single<&mut Window>,
) {
    if !settings.is_changed() {
        return;
    }
    apply_ui_settings(&settings, &mut render_config, &mut ui_scale, &mut window);
}

pub(crate) fn save_ui_settings_system(
    settings: Res<ViewerUiSettings>,
    path: Res<ViewerUiSettingsPath>,
) {
    if !settings.is_changed() {
        return;
    }
    if let Some(parent) = path.0.parent() {
        let _ = fs::create_dir_all(parent);
    }
    if let Ok(raw) = serde_json::to_string_pretty(&*settings) {
        let _ = fs::write(&path.0, raw);
    }
}

pub(super) fn apply_ui_settings(
    _settings: &ViewerUiSettings,
    _render_config: &mut ViewerRenderConfig,
    ui_scale: &mut UiScale,
    window: &mut Window,
) {
    ui_scale.0 = _settings.ui_scale.max(0.5);
    window.mode = match _settings.window_mode.as_str() {
        "fullscreen" => {
            WindowMode::Fullscreen(MonitorSelection::Primary, VideoModeSelection::Current)
        }
        "borderless_fullscreen" => WindowMode::BorderlessFullscreen(MonitorSelection::Primary),
        _ => {
            window.resolution.set(
                _settings.window_resolution.width as f32,
                _settings.window_resolution.height as f32,
            );
            WindowMode::Windowed
        }
    };
    window.present_mode = if _settings.vsync {
        PresentMode::AutoVsync
    } else {
        PresentMode::AutoNoVsync
    };
}

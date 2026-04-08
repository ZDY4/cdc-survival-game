//! 渲染常量：集中定义交互菜单、对话面板、网格和墙体相关的共享尺寸参数。

pub(crate) const INTERACTION_MENU_WIDTH_PX: f32 = 70.0;
pub(crate) const INTERACTION_MENU_PADDING_PX: f32 = 6.0;
pub(crate) const INTERACTION_MENU_BORDER_WIDTH_PX: f32 = 1.0;
pub(crate) const INTERACTION_MENU_ITEM_HEIGHT_PX: f32 = 20.0;
pub(crate) const INTERACTION_MENU_ITEM_GAP_PX: f32 = 2.0;
pub(crate) const INTERACTION_MENU_ITEM_MIN_FONT_SIZE_PX: f32 = 5.5;
pub(crate) const DIALOGUE_CHOICE_BUTTON_HEIGHT_PX: f32 = 34.0;
pub(crate) const DIALOGUE_CHOICE_BUTTON_GAP_PX: f32 = 8.0;
pub(crate) const DIALOGUE_CHOICE_BUTTON_PADDING_X_PX: f32 = 12.0;
pub(crate) const DIALOGUE_CHOICE_BUTTON_PADDING_Y_PX: f32 = 8.0;
pub(crate) const DIALOGUE_CHOICE_BUTTON_FONT_SIZE_PX: f32 = 13.2;
pub(crate) const DIALOGUE_PANEL_BOTTOM_PX: f32 = 24.0;
pub(crate) const DIALOGUE_PANEL_MIN_WIDTH_PX: f32 = 360.0;
pub(crate) const DIALOGUE_PANEL_MAX_WIDTH_PX: f32 = 920.0;
pub(crate) const GRID_LINE_ELEVATION: f32 = 0.002;
pub(crate) const OVERLAY_ELEVATION: f32 = 0.03;
pub(crate) const HOVER_MESH_OUTLINE_WIDTH_PX: f32 = 4.0;
pub(crate) const HOVER_MESH_OUTLINE_INTENSITY: f32 = 1.0;
pub(crate) const HOVER_MESH_OUTLINE_PRIORITY: f32 = 8.0;
pub(crate) const TRIGGER_ARROW_TEXTURE_SIZE: u32 = 64;
pub(crate) const CAMERA_FOLLOW_SMOOTHING_TAU_SEC: f32 = 0.075;
pub(crate) const CAMERA_FOLLOW_RESET_DISTANCE_CELLS: f32 = 2.0;
pub(crate) const GENERATED_DOOR_ROTATION_SPEED_RAD_PER_SEC: f32 = 7.5;
pub(crate) const MISSING_GEO_BUILDING_PLACEHOLDER_ALPHA: f32 = 0.96;

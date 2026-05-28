//! 详情文本构建辅助：记录每行文本并计算估算高度，用于物品/技能面板。

use super::*;

#[derive(Debug, Clone)]
pub(in crate::game_ui) struct DetailTextLine {
    pub(in crate::game_ui) text: String,
    pub(in crate::game_ui) size: f32,
    pub(in crate::game_ui) color: Color,
}

#[derive(Debug, Clone, Default)]
pub(in crate::game_ui) struct DetailTextContent {
    pub(in crate::game_ui) lines: Vec<DetailTextLine>,
}

impl DetailTextContent {
    pub(in crate::game_ui) fn push(&mut self, text: impl Into<String>, size: f32, color: Color) {
        self.lines.push(DetailTextLine {
            text: text.into(),
            size,
            color,
        });
    }

    pub(in crate::game_ui) fn estimated_height(&self) -> f32 {
        self.lines.iter().map(|line| line.size + 6.0).sum::<f32>() + 26.0
    }
}

pub(in crate::game_ui) fn spawn_detail_text_content(
    parent: &mut ChildSpawnerCommands,
    font: &ViewerUiFont,
    content: &DetailTextContent,
) {
    for line in &content.lines {
        parent.spawn(wrapped_text_bundle(font, &line.text, line.size, line.color));
    }
}

//! GOAP 黑板模块。
//! 负责 blackboard 数据存取，不负责条件求值、目标打分或规划执行。

use std::collections::BTreeMap;

#[derive(Debug, Clone, PartialEq, Default)]
pub struct AiBlackboard {
    numbers: BTreeMap<String, f32>,
    booleans: BTreeMap<String, bool>,
    texts: BTreeMap<String, String>,
}

impl AiBlackboard {
    pub fn set_number(&mut self, key: impl Into<String>, value: f32) {
        self.numbers.insert(key.into(), value);
    }

    pub fn set_bool(&mut self, key: impl Into<String>, value: bool) {
        self.booleans.insert(key.into(), value);
    }

    pub fn set_text(&mut self, key: impl Into<String>, value: impl Into<String>) {
        self.texts.insert(key.into(), value.into());
    }

    pub fn set_optional_text(&mut self, key: impl Into<String>, value: Option<String>) {
        if let Some(value) = value {
            self.set_text(key, value);
        }
    }

    pub fn number(&self, key: &str) -> Option<f32> {
        self.numbers.get(key).copied()
    }

    pub fn boolean(&self, key: &str) -> Option<bool> {
        self.booleans.get(key).copied()
    }

    pub fn text(&self, key: &str) -> Option<&str> {
        self.texts.get(key).map(String::as_str)
    }
}

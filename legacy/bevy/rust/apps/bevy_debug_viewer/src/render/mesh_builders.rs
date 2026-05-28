//! viewer 局部 mesh helper。

#[allow(clippy::too_many_arguments)]
pub(super) fn move_toward_f32(current: f32, target: f32, max_delta: f32) -> f32 {
    if (target - current).abs() <= max_delta {
        target
    } else {
        current + (target - current).signum() * max_delta
    }
}

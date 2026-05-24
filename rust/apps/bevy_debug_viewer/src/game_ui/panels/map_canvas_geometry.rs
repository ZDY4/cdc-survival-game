//! 地图画布几何 helper：把格子 footprint 合并成更接近建筑轮廓的矩形块。

use std::collections::BTreeMap;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) struct GridRect {
    pub(super) x: i32,
    pub(super) z: i32,
    pub(super) width: u32,
    pub(super) height: u32,
}

pub(super) fn object_occupied_rects(
    object: &game_core::MapObjectDebugState,
    current_level: i32,
) -> Vec<GridRect> {
    let mut by_z = BTreeMap::<i32, Vec<i32>>::new();
    for cell in object
        .occupied_cells
        .iter()
        .filter(|cell| cell.y == current_level)
    {
        by_z.entry(cell.z).or_default().push(cell.x);
    }

    // 先合并同一行的连续格子，再把相邻行中横向范围相同的条带合并成块。
    let mut rects = Vec::<GridRect>::new();
    for (z, mut xs) in by_z {
        xs.sort_unstable();
        xs.dedup();
        for (start, end) in contiguous_x_runs(xs) {
            let width = (end - start + 1) as u32;
            if let Some(rect) = rects.iter_mut().find(|rect| {
                rect.x == start && rect.width == width && rect.z + rect.height as i32 == z
            }) {
                rect.height += 1;
            } else {
                rects.push(GridRect {
                    x: start,
                    z,
                    width,
                    height: 1,
                });
            }
        }
    }
    rects
}

fn contiguous_x_runs(xs: Vec<i32>) -> Vec<(i32, i32)> {
    let mut runs = Vec::new();
    let mut iter = xs.into_iter();
    let Some(mut start) = iter.next() else {
        return runs;
    };
    let mut end = start;
    for x in iter {
        if x == end + 1 {
            end = x;
        } else {
            runs.push((start, end));
            start = x;
            end = x;
        }
    }
    runs.push((start, end));
    runs
}

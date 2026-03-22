#include "native_jps_planner.h"

#include <godot_cpp/core/error_macros.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <cmath>

using namespace godot;

NativeJpsPlanner::NativeJpsPlanner() {
	_map_util = std::make_shared<JPS::MapUtil<2>>();
	_planner = std::make_unique<JPSPlanner2D>(false);
	_planner->setMapUtil(_map_util);
}

void NativeJpsPlanner::_bind_methods() {
	ClassDB::bind_method(D_METHOD("rebuild_static_map", "bounds", "blocked_cells"), &NativeJpsPlanner::rebuild_static_map);
	ClassDB::bind_method(D_METHOD("set_runtime_blocked_cells", "blocked_cells"), &NativeJpsPlanner::set_runtime_blocked_cells);
	ClassDB::bind_method(D_METHOD("find_path", "start_grid", "goal_grid", "use_jps"), &NativeJpsPlanner::find_path, DEFVAL(true));
	ClassDB::bind_method(D_METHOD("clear_runtime_state"), &NativeJpsPlanner::clear_runtime_state);
}

void NativeJpsPlanner::rebuild_static_map(const Dictionary &p_bounds, const Array &p_blocked_cells) {
	_static_blocked.clear();
	_runtime_blocked.clear();
	_has_bounds = _apply_bounds(p_bounds);
	_set_blocked_set(_static_blocked, p_blocked_cells);
	_map_dirty = true;
}

void NativeJpsPlanner::set_runtime_blocked_cells(const Array &p_blocked_cells) {
	_runtime_blocked.clear();
	_set_blocked_set(_runtime_blocked, p_blocked_cells);
	_map_dirty = true;
}

Array NativeJpsPlanner::find_path(const Vector3i &p_start_grid, const Vector3i &p_goal_grid, bool p_use_jps) {
	Array path;
	if (!_ensure_planner_ready()) {
		return path;
	}
	if (!_is_inside_bounds(p_start_grid) || !_is_inside_bounds(p_goal_grid)) {
		return path;
	}

	const Vec2f start = _to_local_world_point(p_start_grid);
	const Vec2f goal = _to_local_world_point(p_goal_grid);
	if (!_planner->plan(start, goal, 1.0, p_use_jps)) {
		return path;
	}

	const vec_Vec2f planner_path = _planner->getPath();
	for (const Vec2f &point : planner_path) {
		path.append(_to_world_grid(point));
	}
	return path;
}

void NativeJpsPlanner::clear_runtime_state() {
	_runtime_blocked.clear();
	_map_dirty = true;
}

bool NativeJpsPlanner::_apply_bounds(const Dictionary &p_bounds) {
	if (!p_bounds.has("min") || !p_bounds.has("max")) {
		return false;
	}
	const Variant min_variant = p_bounds.get("min");
	const Variant max_variant = p_bounds.get("max");
	if (min_variant.get_type() != Variant::VECTOR3I || max_variant.get_type() != Variant::VECTOR3I) {
		return false;
	}

	_min_grid = min_variant;
	_max_grid = max_variant;
	_dims = Vector2i(_max_grid.x - _min_grid.x + 1, _max_grid.z - _min_grid.z + 1);
	return _dims.x > 0 && _dims.y > 0;
}

void NativeJpsPlanner::_set_blocked_set(std::unordered_set<int64_t> &r_target, const Array &p_blocked_cells) {
	for (int64_t i = 0; i < p_blocked_cells.size(); i++) {
		const Variant value = p_blocked_cells[i];
		if (value.get_type() != Variant::VECTOR3I) {
			continue;
		}
		const Vector3i grid = value;
		if (!_is_inside_bounds(grid)) {
			continue;
		}
		r_target.insert(_cell_key(grid));
	}
}

void NativeJpsPlanner::_rebuild_occupancy() {
	_occupancy.assign(static_cast<size_t>(_dims.x * _dims.y), CELL_FREE);
	for (int z = _min_grid.z; z <= _max_grid.z; z++) {
		for (int x = _min_grid.x; x <= _max_grid.x; x++) {
			const Vector3i grid(x, 0, z);
			const int index = _flatten_local_cell(_to_local_cell(grid));
			const int64_t key = _cell_key(grid);
			if (_static_blocked.find(key) != _static_blocked.end() || _runtime_blocked.find(key) != _runtime_blocked.end()) {
				_occupancy[static_cast<size_t>(index)] = CELL_BLOCKED;
			}
		}
	}

	Vec2f origin;
	origin << static_cast<decimal_t>(_min_grid.x), static_cast<decimal_t>(_min_grid.z);
	Vec2i dim;
	dim << _dims.x, _dims.y;
	_map_util->setMap(origin, dim, _occupancy, 1.0);
	_planner->updateMap();
	_map_dirty = false;
}

bool NativeJpsPlanner::_ensure_planner_ready() {
	if (!_has_bounds) {
		return false;
	}
	if (_map_dirty) {
		_rebuild_occupancy();
	}
	return true;
}

bool NativeJpsPlanner::_is_inside_bounds(const Vector3i &p_grid) const {
	if (!_has_bounds) {
		return false;
	}
	return p_grid.x >= _min_grid.x && p_grid.x <= _max_grid.x && p_grid.z >= _min_grid.z && p_grid.z <= _max_grid.z;
}

Vector2i NativeJpsPlanner::_to_local_cell(const Vector3i &p_grid) const {
	return Vector2i(p_grid.x - _min_grid.x, p_grid.z - _min_grid.z);
}

Vec2f NativeJpsPlanner::_to_local_world_point(const Vector3i &p_grid) const {
	Vec2f point;
	point << static_cast<decimal_t>(p_grid.x) + 0.5, static_cast<decimal_t>(p_grid.z) + 0.5;
	return point;
}

Vector3i NativeJpsPlanner::_to_world_grid(const Vec2f &p_point) const {
	const int x = static_cast<int>(std::round(p_point(0) - 0.5));
	const int z = static_cast<int>(std::round(p_point(1) - 0.5));
	return Vector3i(x, 0, z);
}

int NativeJpsPlanner::_flatten_local_cell(const Vector2i &p_cell) const {
	return p_cell.x + p_cell.y * _dims.x;
}

int64_t NativeJpsPlanner::_cell_key(const Vector3i &p_grid) const {
	const int64_t x = static_cast<int64_t>(p_grid.x) & 0x1FFFFF;
	const int64_t y = static_cast<int64_t>(p_grid.y) & 0x1FFFFF;
	const int64_t z = static_cast<int64_t>(p_grid.z) & 0x1FFFFF;
	return (x << 42) | (y << 21) | z;
}

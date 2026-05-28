use std::collections::HashMap;

use bevy::mesh::{Indices, VertexAttributeValues};
use bevy::prelude::*;

#[derive(Resource, Debug, Clone)]
pub struct MeshPickIndex<T> {
    // Gameplay/editor object picking should share this CPU-side path. Prototype geometry is
    // cached once per mesh handle, while each semantic object keeps its own transform and data.
    prototypes: HashMap<MeshPickPrototypeKey, MeshPickPrototype>,
    instances: Vec<MeshPickInstance<T>>,
    pending_mesh_instances: Vec<PendingMeshPickInstance<T>>,
}

impl<T> Default for MeshPickIndex<T> {
    fn default() -> Self {
        Self {
            prototypes: HashMap::default(),
            instances: Vec::new(),
            pending_mesh_instances: Vec::new(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct MeshPickPrototypeKey(String);

impl MeshPickPrototypeKey {
    pub fn mesh(handle: &Handle<Mesh>) -> Self {
        Self(format!("mesh::{:?}", handle.id()))
    }

    pub fn cuboid(size: Vec3) -> Self {
        Self(format!(
            "cuboid::{:08x}:{:08x}:{:08x}",
            size.x.to_bits(),
            size.y.to_bits(),
            size.z.to_bits()
        ))
    }
}

#[derive(Debug, Clone)]
pub struct MeshPickHit<T> {
    pub entity: Entity,
    pub data: T,
    pub depth: f32,
    pub position: Vec3,
}

#[derive(Debug, Clone)]
struct MeshPickPrototype {
    triangles: Vec<[Vec3; 3]>,
    local_aabb: MeshPickAabb,
}

#[derive(Debug, Clone)]
struct MeshPickInstance<T> {
    entity: Entity,
    prototype_key: MeshPickPrototypeKey,
    world_from_local: Mat4,
    local_from_world: Mat4,
    world_aabb: MeshPickAabb,
    data: T,
    source: MeshPickInstanceSource,
}

#[derive(Debug, Clone)]
struct PendingMeshPickInstance<T> {
    entity: Entity,
    mesh: Handle<Mesh>,
    prototype_key: MeshPickPrototypeKey,
    world_from_local: Transform,
    data: T,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum MeshPickInstanceSource {
    Precise,
    Fallback,
}

#[derive(Debug, Clone, Copy, PartialEq)]
struct MeshPickAabb {
    min: Vec3,
    max: Vec3,
}

#[derive(Debug, Clone)]
struct MeshPickCandidate<T> {
    entity: Entity,
    data: T,
    depth: f32,
    position: Vec3,
}

impl<T: Clone> MeshPickIndex<T> {
    pub fn clear(&mut self) {
        self.instances.clear();
        self.pending_mesh_instances.clear();
    }

    pub fn clear_entity(&mut self, entity: Entity) {
        self.instances.retain(|instance| instance.entity != entity);
        self.pending_mesh_instances
            .retain(|instance| instance.entity != entity);
    }

    pub fn clear_precise_entity(&mut self, entity: Entity) {
        // Actor previews refresh their loaded child meshes every frame while keeping a coarse
        // fallback proxy. This removes only triangle/pending entries for that semantic entity.
        self.instances.retain(|instance| {
            instance.entity != entity || instance.source != MeshPickInstanceSource::Precise
        });
        self.pending_mesh_instances
            .retain(|instance| instance.entity != entity);
    }

    pub fn register_mesh_instance(
        &mut self,
        entity: Entity,
        mesh: &Mesh,
        prototype_key: MeshPickPrototypeKey,
        world_from_local: Transform,
        data: impl Into<T>,
    ) -> bool {
        self.register_mesh_instance_internal(
            entity,
            mesh,
            prototype_key,
            world_from_local,
            data,
            true,
        )
    }

    pub fn register_mesh_instance_preserving_fallback(
        &mut self,
        entity: Entity,
        mesh: &Mesh,
        prototype_key: MeshPickPrototypeKey,
        world_from_local: Transform,
        data: impl Into<T>,
    ) -> bool {
        self.register_mesh_instance_internal(
            entity,
            mesh,
            prototype_key,
            world_from_local,
            data,
            false,
        )
    }

    fn register_mesh_instance_internal(
        &mut self,
        entity: Entity,
        mesh: &Mesh,
        prototype_key: MeshPickPrototypeKey,
        world_from_local: Transform,
        data: impl Into<T>,
        remove_fallback: bool,
    ) -> bool {
        if !self.prototypes.contains_key(&prototype_key) {
            let Some(prototype) = MeshPickPrototype::from_mesh(mesh) else {
                return false;
            };
            self.prototypes.insert(prototype_key.clone(), prototype);
        }
        if remove_fallback {
            self.remove_fallback_instances(entity);
        }
        self.register_instance(
            entity,
            prototype_key,
            world_from_local,
            data.into(),
            MeshPickInstanceSource::Precise,
        );
        true
    }

    pub fn register_mesh_handle_instance(
        &mut self,
        entity: Entity,
        mesh_handle: Handle<Mesh>,
        meshes: &Assets<Mesh>,
        prototype_key: MeshPickPrototypeKey,
        world_from_local: Transform,
        data: impl Into<T>,
    ) -> bool {
        let data = data.into();
        if let Some(mesh) = meshes.get(&mesh_handle) {
            return self.register_mesh_instance(
                entity,
                mesh,
                prototype_key,
                world_from_local,
                data,
            );
        }
        // glTF primitive meshes are often loaded after scene rebuild. Keep the request pending so
        // the temporary cuboid fallback is replaced by triangle picking later.
        self.pending_mesh_instances.push(PendingMeshPickInstance {
            entity,
            mesh: mesh_handle,
            prototype_key,
            world_from_local,
            data,
        });
        false
    }

    pub fn register_cuboid_instance(
        &mut self,
        entity: Entity,
        size: Vec3,
        world_from_local: Transform,
        data: impl Into<T>,
    ) {
        let prototype_key = MeshPickPrototypeKey::cuboid(size);
        self.prototypes
            .entry(prototype_key.clone())
            .or_insert_with(|| MeshPickPrototype::cuboid(size));
        self.register_instance(
            entity,
            prototype_key,
            world_from_local,
            data.into(),
            MeshPickInstanceSource::Fallback,
        );
    }

    pub fn sync_pending_mesh_instances(&mut self, meshes: &Assets<Mesh>) {
        let pending = std::mem::take(&mut self.pending_mesh_instances);
        for pending_instance in pending {
            let Some(mesh) = meshes.get(&pending_instance.mesh) else {
                self.pending_mesh_instances.push(pending_instance);
                continue;
            };
            self.register_mesh_instance(
                pending_instance.entity,
                mesh,
                pending_instance.prototype_key,
                pending_instance.world_from_local,
                pending_instance.data,
            );
        }
    }

    pub fn query_by(
        &self,
        ray: Ray3d,
        should_replace: impl Fn(Option<&MeshPickHit<T>>, &MeshPickHit<T>) -> bool,
    ) -> Option<MeshPickHit<T>> {
        let ray_origin = ray.origin;
        let ray_direction = ray.direction.as_vec3();
        let mut best: Option<MeshPickHit<T>> = None;
        for instance in &self.instances {
            // Linear broad phase is intentional for the first implementation; callers depend only
            // on query_by(ray), so a spatial index can replace this without changing app code.
            if !instance
                .world_aabb
                .intersects_ray(ray_origin, ray_direction)
            {
                continue;
            }
            let Some(prototype) = self.prototypes.get(&instance.prototype_key) else {
                continue;
            };
            let local_origin = instance.local_from_world.transform_point3(ray_origin);
            let local_end = instance
                .local_from_world
                .transform_point3(ray_origin + ray_direction);
            let local_direction = (local_end - local_origin).normalize_or_zero();
            if local_direction.length_squared() <= f32::EPSILON {
                continue;
            }
            let Some(candidate) = prototype.hit_candidate(instance, local_origin, local_direction)
            else {
                continue;
            };
            let resolved = MeshPickHit {
                entity: candidate.entity,
                data: candidate.data,
                depth: candidate.depth,
                position: candidate.position,
            };
            if should_replace(best.as_ref(), &resolved) {
                best = Some(resolved);
            }
        }
        best
    }

    pub fn query_nearest(&self, ray: Ray3d) -> Option<MeshPickHit<T>> {
        self.query_by(ray, |current, candidate| match current {
            None => true,
            Some(current) => candidate.depth < current.depth,
        })
    }

    #[cfg(test)]
    pub fn prototype_count(&self) -> usize {
        self.prototypes.len()
    }

    #[cfg(test)]
    pub fn instance_count(&self) -> usize {
        self.instances.len()
    }

    fn register_instance(
        &mut self,
        entity: Entity,
        prototype_key: MeshPickPrototypeKey,
        world_from_local: Transform,
        data: T,
        source: MeshPickInstanceSource,
    ) {
        let world_from_local_matrix = world_from_local.to_matrix();
        let local_from_world = world_from_local_matrix.inverse();
        let Some(prototype) = self.prototypes.get(&prototype_key) else {
            return;
        };
        let world_aabb = prototype.local_aabb.transformed(world_from_local_matrix);
        self.instances.push(MeshPickInstance {
            entity,
            prototype_key,
            world_from_local: world_from_local_matrix,
            local_from_world,
            world_aabb,
            data,
            source,
        });
    }

    fn remove_fallback_instances(&mut self, entity: Entity) {
        self.instances.retain(|instance| {
            instance.entity != entity || instance.source != MeshPickInstanceSource::Fallback
        });
    }
}

impl MeshPickPrototype {
    fn from_mesh(mesh: &Mesh) -> Option<Self> {
        let positions = mesh.attribute(Mesh::ATTRIBUTE_POSITION)?;
        let positions = match positions {
            VertexAttributeValues::Float32x3(values) => values
                .iter()
                .map(|position| Vec3::from_array(*position))
                .collect::<Vec<_>>(),
            _ => return None,
        };
        let triangles = mesh_triangles(mesh, &positions)?;
        (!triangles.is_empty()).then(|| Self {
            local_aabb: MeshPickAabb::from_points(positions.iter().copied()),
            triangles,
        })
    }

    fn cuboid(size: Vec3) -> Self {
        let half = size * 0.5;
        let p = [
            Vec3::new(-half.x, -half.y, -half.z),
            Vec3::new(half.x, -half.y, -half.z),
            Vec3::new(half.x, half.y, -half.z),
            Vec3::new(-half.x, half.y, -half.z),
            Vec3::new(-half.x, -half.y, half.z),
            Vec3::new(half.x, -half.y, half.z),
            Vec3::new(half.x, half.y, half.z),
            Vec3::new(-half.x, half.y, half.z),
        ];
        let triangles = vec![
            [p[0], p[2], p[1]],
            [p[0], p[3], p[2]],
            [p[4], p[5], p[6]],
            [p[4], p[6], p[7]],
            [p[0], p[1], p[5]],
            [p[0], p[5], p[4]],
            [p[3], p[6], p[2]],
            [p[3], p[7], p[6]],
            [p[1], p[2], p[6]],
            [p[1], p[6], p[5]],
            [p[0], p[4], p[7]],
            [p[0], p[7], p[3]],
        ];
        Self {
            local_aabb: MeshPickAabb::new(-half, half),
            triangles,
        }
    }

    fn hit_candidate<T: Clone>(
        &self,
        instance: &MeshPickInstance<T>,
        local_origin: Vec3,
        local_direction: Vec3,
    ) -> Option<MeshPickCandidate<T>> {
        let mut best_t = f32::INFINITY;
        let mut best_local_position = None;
        for triangle in &self.triangles {
            let Some(t) = ray_triangle_intersection(local_origin, local_direction, *triangle)
            else {
                continue;
            };
            if t >= 0.0 && t < best_t {
                best_t = t;
                best_local_position = Some(local_origin + local_direction * t);
            }
        }
        let local_position = best_local_position?;
        let world_position = instance.world_from_local.transform_point3(local_position);
        Some(MeshPickCandidate {
            entity: instance.entity,
            data: instance.data.clone(),
            depth: (world_position - instance.world_from_local.transform_point3(local_origin))
                .length(),
            position: world_position,
        })
    }
}

impl MeshPickAabb {
    fn new(min: Vec3, max: Vec3) -> Self {
        Self { min, max }
    }

    fn from_points(points: impl IntoIterator<Item = Vec3>) -> Self {
        let mut min = Vec3::splat(f32::INFINITY);
        let mut max = Vec3::splat(f32::NEG_INFINITY);
        for point in points {
            min = min.min(point);
            max = max.max(point);
        }
        Self { min, max }
    }

    fn transformed(self, transform: Mat4) -> Self {
        let corners = [
            Vec3::new(self.min.x, self.min.y, self.min.z),
            Vec3::new(self.max.x, self.min.y, self.min.z),
            Vec3::new(self.min.x, self.max.y, self.min.z),
            Vec3::new(self.max.x, self.max.y, self.min.z),
            Vec3::new(self.min.x, self.min.y, self.max.z),
            Vec3::new(self.max.x, self.min.y, self.max.z),
            Vec3::new(self.min.x, self.max.y, self.max.z),
            Vec3::new(self.max.x, self.max.y, self.max.z),
        ];
        Self::from_points(
            corners
                .into_iter()
                .map(|corner| transform.transform_point3(corner)),
        )
    }

    fn intersects_ray(self, origin: Vec3, direction: Vec3) -> bool {
        let inv_direction = Vec3::new(
            reciprocal_or_infinity(direction.x),
            reciprocal_or_infinity(direction.y),
            reciprocal_or_infinity(direction.z),
        );
        let t1 = (self.min - origin) * inv_direction;
        let t2 = (self.max - origin) * inv_direction;
        let t_min = t1.min(t2).max_element();
        let t_max = t1.max(t2).min_element();
        t_max >= t_min.max(0.0)
    }
}

fn mesh_triangles(mesh: &Mesh, positions: &[Vec3]) -> Option<Vec<[Vec3; 3]>> {
    match mesh.indices() {
        Some(Indices::U16(indices)) => Some(
            indices
                .chunks_exact(3)
                .filter_map(|triangle| {
                    Some([
                        *positions.get(triangle[0] as usize)?,
                        *positions.get(triangle[1] as usize)?,
                        *positions.get(triangle[2] as usize)?,
                    ])
                })
                .collect(),
        ),
        Some(Indices::U32(indices)) => Some(
            indices
                .chunks_exact(3)
                .filter_map(|triangle| {
                    Some([
                        *positions.get(triangle[0] as usize)?,
                        *positions.get(triangle[1] as usize)?,
                        *positions.get(triangle[2] as usize)?,
                    ])
                })
                .collect(),
        ),
        None => Some(
            positions
                .chunks_exact(3)
                .map(|triangle| [triangle[0], triangle[1], triangle[2]])
                .collect(),
        ),
    }
}

fn ray_triangle_intersection(origin: Vec3, direction: Vec3, triangle: [Vec3; 3]) -> Option<f32> {
    const EPSILON: f32 = 1.0e-6;
    let edge1 = triangle[1] - triangle[0];
    let edge2 = triangle[2] - triangle[0];
    let h = direction.cross(edge2);
    let a = edge1.dot(h);
    if a.abs() < EPSILON {
        return None;
    }
    let f = 1.0 / a;
    let s = origin - triangle[0];
    let u = f * s.dot(h);
    if !(0.0..=1.0).contains(&u) {
        return None;
    }
    let q = s.cross(edge1);
    let v = f * direction.dot(q);
    if v < 0.0 || u + v > 1.0 {
        return None;
    }
    let t = f * edge2.dot(q);
    (t > EPSILON).then_some(t)
}

fn reciprocal_or_infinity(value: f32) -> f32 {
    if value.abs() <= f32::EPSILON {
        f32::INFINITY.copysign(value)
    } else {
        1.0 / value
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn shared_prototype_handles_multiple_instances() {
        let mut index = MeshPickIndex::<String>::default();
        let key = MeshPickPrototypeKey("triangle".into());
        index.prototypes.insert(
            key.clone(),
            MeshPickPrototype {
                local_aabb: MeshPickAabb::new(Vec3::ZERO, Vec3::ONE),
                triangles: vec![[Vec3::ZERO, Vec3::X, Vec3::Y]],
            },
        );
        index.register_instance(
            Entity::from_bits(1),
            key.clone(),
            Transform::IDENTITY,
            "a".into(),
            MeshPickInstanceSource::Precise,
        );
        index.register_instance(
            Entity::from_bits(2),
            key,
            Transform::from_xyz(2.0, 0.0, 0.0),
            "b".into(),
            MeshPickInstanceSource::Precise,
        );

        assert_eq!(index.prototype_count(), 1);
        assert_eq!(index.instance_count(), 2);
    }

    #[test]
    fn query_returns_transformed_instance_data() {
        let mut index = MeshPickIndex::<String>::default();
        index.register_cuboid_instance(
            Entity::from_bits(7),
            Vec3::ONE,
            Transform::from_xyz(2.0, 0.0, 0.0),
            "actor_7",
        );

        let pick = index
            .query_nearest(Ray3d::new(
                Vec3::new(2.0, 0.0, -4.0),
                Dir3::new(Vec3::Z).expect("valid ray"),
            ))
            .expect("ray should hit cuboid");

        assert_eq!(pick.data, "actor_7");
    }

    #[test]
    fn pending_mesh_replaces_fallback_for_entity() {
        let mut index = MeshPickIndex::<String>::default();
        let mut meshes = Assets::<Mesh>::default();
        let mesh_handle = meshes.add(Triangle3d::new(Vec3::ZERO, Vec3::X, Vec3::Y));
        let entity = Entity::from_bits(9);
        index.register_cuboid_instance(entity, Vec3::splat(10.0), Transform::IDENTITY, "fallback");

        assert!(index.register_mesh_handle_instance(
            entity,
            mesh_handle.clone(),
            &meshes,
            MeshPickPrototypeKey::mesh(&mesh_handle),
            Transform::IDENTITY,
            "precise",
        ));

        let pick = index
            .query_nearest(Ray3d::new(
                Vec3::new(0.2, 0.2, -1.0),
                Dir3::new(Vec3::Z).expect("valid ray"),
            ))
            .expect("ray should hit triangle");

        assert_eq!(pick.data, "precise");
        assert_eq!(index.instance_count(), 1);
    }

    #[test]
    fn precise_mesh_can_preserve_fallback_for_actor_like_targets() {
        let mut index = MeshPickIndex::<String>::default();
        let mut meshes = Assets::<Mesh>::default();
        let mesh_handle = meshes.add(Triangle3d::new(Vec3::ZERO, Vec3::X, Vec3::Y));
        let mesh = meshes.get(&mesh_handle).expect("mesh should exist");
        let entity = Entity::from_bits(12);
        index.register_cuboid_instance(entity, Vec3::splat(10.0), Transform::IDENTITY, "fallback");

        assert!(index.register_mesh_instance_preserving_fallback(
            entity,
            mesh,
            MeshPickPrototypeKey::mesh(&mesh_handle),
            Transform::IDENTITY,
            "precise",
        ));

        assert_eq!(index.instance_count(), 2);
    }

    #[test]
    fn clear_precise_entity_keeps_fallback_proxy() {
        let mut index = MeshPickIndex::<String>::default();
        let mut meshes = Assets::<Mesh>::default();
        let mesh_handle = meshes.add(Triangle3d::new(Vec3::ZERO, Vec3::X, Vec3::Y));
        let mesh = meshes.get(&mesh_handle).expect("mesh should exist");
        let entity = Entity::from_bits(13);
        index.register_cuboid_instance(entity, Vec3::splat(10.0), Transform::IDENTITY, "fallback");
        assert!(index.register_mesh_instance_preserving_fallback(
            entity,
            mesh,
            MeshPickPrototypeKey::mesh(&mesh_handle),
            Transform::IDENTITY,
            "precise",
        ));

        index.clear_precise_entity(entity);

        assert_eq!(index.instance_count(), 1);
        let pick = index
            .query_nearest(Ray3d::new(
                Vec3::new(0.0, 0.0, -4.0),
                Dir3::new(Vec3::Z).expect("valid ray"),
            ))
            .expect("fallback proxy should remain pickable");
        assert_eq!(pick.data, "fallback");
    }

    #[test]
    fn query_by_uses_caller_replacement_rule() {
        let mut index = MeshPickIndex::<i32>::default();
        index.register_cuboid_instance(
            Entity::from_bits(1),
            Vec3::splat(1.0),
            Transform::from_xyz(0.0, 0.0, -1.0),
            1,
        );
        index.register_cuboid_instance(
            Entity::from_bits(2),
            Vec3::splat(1.0),
            Transform::from_xyz(0.0, 0.0, 0.0),
            2,
        );

        let pick = index
            .query_by(
                Ray3d::new(
                    Vec3::new(0.0, 0.0, -4.0),
                    Dir3::new(Vec3::Z).expect("valid ray"),
                ),
                |current, candidate| match current {
                    None => true,
                    Some(current) => candidate.data > current.data,
                },
            )
            .expect("ray should hit both cuboids");

        assert_eq!(pick.data, 2);
    }
}

import base64
import json
import math
import struct
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets" / "bevy_preview" / "characters" / "humanoid_mannequin.gltf"


def cube_geometry():
    positions = [
        # +X
        (0.5, -0.5, -0.5),
        (0.5, -0.5, 0.5),
        (0.5, 0.5, 0.5),
        (0.5, 0.5, -0.5),
        # -X
        (-0.5, -0.5, 0.5),
        (-0.5, -0.5, -0.5),
        (-0.5, 0.5, -0.5),
        (-0.5, 0.5, 0.5),
        # +Y
        (-0.5, 0.5, -0.5),
        (0.5, 0.5, -0.5),
        (0.5, 0.5, 0.5),
        (-0.5, 0.5, 0.5),
        # -Y
        (-0.5, -0.5, 0.5),
        (0.5, -0.5, 0.5),
        (0.5, -0.5, -0.5),
        (-0.5, -0.5, -0.5),
        # +Z
        (-0.5, -0.5, 0.5),
        (-0.5, 0.5, 0.5),
        (0.5, 0.5, 0.5),
        (0.5, -0.5, 0.5),
        # -Z
        (0.5, -0.5, -0.5),
        (0.5, 0.5, -0.5),
        (-0.5, 0.5, -0.5),
        (-0.5, -0.5, -0.5),
    ]
    normals = [
        (1.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (1.0, 0.0, 0.0),
        (-1.0, 0.0, 0.0),
        (-1.0, 0.0, 0.0),
        (-1.0, 0.0, 0.0),
        (-1.0, 0.0, 0.0),
        (0.0, 1.0, 0.0),
        (0.0, 1.0, 0.0),
        (0.0, 1.0, 0.0),
        (0.0, 1.0, 0.0),
        (0.0, -1.0, 0.0),
        (0.0, -1.0, 0.0),
        (0.0, -1.0, 0.0),
        (0.0, -1.0, 0.0),
        (0.0, 0.0, 1.0),
        (0.0, 0.0, 1.0),
        (0.0, 0.0, 1.0),
        (0.0, 0.0, 1.0),
        (0.0, 0.0, -1.0),
        (0.0, 0.0, -1.0),
        (0.0, 0.0, -1.0),
        (0.0, 0.0, -1.0),
    ]
    indices = [
        0,
        2,
        1,
        0,
        3,
        2,
        4,
        6,
        5,
        4,
        7,
        6,
        8,
        10,
        9,
        8,
        11,
        10,
        12,
        14,
        13,
        12,
        15,
        14,
        16,
        18,
        17,
        16,
        19,
        18,
        20,
        22,
        21,
        20,
        23,
        22,
    ]
    return {"positions": positions, "normals": normals, "indices": indices}


def uv_sphere_geometry(latitude_segments=12, longitude_segments=24):
    positions = []
    normals = []
    indices = []

    for lat in range(latitude_segments + 1):
        theta = math.pi * lat / latitude_segments
        sin_theta = math.sin(theta)
        cos_theta = math.cos(theta)
        for lon in range(longitude_segments + 1):
            phi = 2.0 * math.pi * lon / longitude_segments
            sin_phi = math.sin(phi)
            cos_phi = math.cos(phi)
            normal = (cos_phi * sin_theta, cos_theta, sin_phi * sin_theta)
            positions.append(tuple(0.5 * value for value in normal))
            normals.append(normal)

    columns = longitude_segments + 1
    for lat in range(latitude_segments):
        for lon in range(longitude_segments):
            a = lat * columns + lon
            b = a + columns
            c = a + 1
            d = b + 1
            if lat != 0:
                indices.extend([a, c, b])
            if lat != latitude_segments - 1:
                indices.extend([c, d, b])

    return {"positions": positions, "normals": normals, "indices": indices}


def pack_f32_triplets(values):
    return b"".join(struct.pack("<fff", *value) for value in values)


def pack_u16(values):
    return b"".join(struct.pack("<H", value) for value in values)


def append_aligned(binary, payload):
    while len(binary) % 4:
        binary.append(0)
    offset = len(binary)
    binary.extend(payload)
    return offset


def component_bounds(values):
    return [min(axis) for axis in zip(*values)], [max(axis) for axis in zip(*values)]


def append_vec3_accessor(binary, buffer_views, accessors, values):
    payload = pack_f32_triplets(values)
    offset = append_aligned(binary, payload)
    buffer_view_index = len(buffer_views)
    buffer_views.append(
        {
            "buffer": 0,
            "byteOffset": offset,
            "byteLength": len(payload),
            "target": 34962,
        }
    )
    minimum, maximum = component_bounds(values)
    accessor_index = len(accessors)
    accessors.append(
        {
            "bufferView": buffer_view_index,
            "componentType": 5126,
            "count": len(values),
            "type": "VEC3",
            "min": minimum,
            "max": maximum,
        }
    )
    return accessor_index


def append_index_accessor(binary, buffer_views, accessors, values):
    payload = pack_u16(values)
    offset = append_aligned(binary, payload)
    buffer_view_index = len(buffer_views)
    buffer_views.append(
        {
            "buffer": 0,
            "byteOffset": offset,
            "byteLength": len(payload),
            "target": 34963,
        }
    )
    accessor_index = len(accessors)
    accessors.append(
        {
            "bufferView": buffer_view_index,
            "componentType": 5123,
            "count": len(values),
            "type": "SCALAR",
        }
    )
    return accessor_index


def build_mesh(binary, buffer_views, accessors, geometry, name, material_index):
    position_accessor = append_vec3_accessor(binary, buffer_views, accessors, geometry["positions"])
    normal_accessor = append_vec3_accessor(binary, buffer_views, accessors, geometry["normals"])
    index_accessor = append_index_accessor(binary, buffer_views, accessors, geometry["indices"])
    return {
        "name": name,
        "primitives": [
            {
                "attributes": {"POSITION": position_accessor, "NORMAL": normal_accessor},
                "indices": index_accessor,
                "material": material_index,
                "mode": 4,
            }
        ],
    }


def euler_xyz_deg_to_quat(x_deg, y_deg, z_deg):
    x = math.radians(x_deg) * 0.5
    y = math.radians(y_deg) * 0.5
    z = math.radians(z_deg) * 0.5
    cx, sx = math.cos(x), math.sin(x)
    cy, sy = math.cos(y), math.sin(y)
    cz, sz = math.cos(z), math.sin(z)
    return [
        sx * cy * cz + cx * sy * sz,
        cx * sy * cz - sx * cy * sz,
        cx * cy * sz + sx * sy * cz,
        cx * cy * cz - sx * sy * sz,
    ]


class NodeBuilder:
    def __init__(self):
        self.nodes = []

    def add(
        self,
        name,
        *,
        translation=None,
        rotation_deg=None,
        scale=None,
        mesh=None,
        children=None,
    ):
        node = {"name": name}
        if translation is not None:
            node["translation"] = [round(value, 5) for value in translation]
        if rotation_deg is not None:
            node["rotation"] = [round(value, 6) for value in euler_xyz_deg_to_quat(*rotation_deg)]
        if scale is not None:
            node["scale"] = [round(value, 5) for value in scale]
        if mesh is not None:
            node["mesh"] = mesh
        if children:
            node["children"] = children
        self.nodes.append(node)
        return len(self.nodes) - 1


def mannequin_nodes():
    cube_mesh_index = 0
    sphere_mesh_index = 1
    nodes = NodeBuilder()

    body_mesh = nodes.add("body_mesh", mesh=cube_mesh_index, scale=(0.78, 0.70, 0.28))
    head_mesh = nodes.add("head_mesh", mesh=sphere_mesh_index, scale=(0.48, 0.48, 0.48))
    upper_leg_l_mesh = nodes.add("upper_leg_l_mesh", mesh=cube_mesh_index, scale=(0.20, 0.72, 0.22))
    upper_leg_r_mesh = nodes.add("upper_leg_r_mesh", mesh=cube_mesh_index, scale=(0.20, 0.72, 0.22))
    foot_l_mesh = nodes.add(
        "foot_l_mesh",
        translation=(0.0, 0.0, 0.03),
        mesh=cube_mesh_index,
        scale=(0.42, 0.10, 0.28),
    )
    foot_r_mesh = nodes.add(
        "foot_r_mesh",
        translation=(0.0, 0.0, 0.03),
        mesh=cube_mesh_index,
        scale=(0.42, 0.10, 0.28),
    )

    body_socket = nodes.add("body_socket", translation=(0.0, 0.0, 0.02))
    hands_socket = nodes.add("hands_socket", translation=(0.0, 0.0, 0.04))
    head_socket = nodes.add("head_socket", translation=(0.0, 0.24, 0.02))
    head = nodes.add("head", translation=(0.0, 0.60, 0.0), children=[head_mesh, head_socket])
    hand_l = nodes.add("hand_l", translation=(-0.62, -0.04, 0.02))
    hand_r = nodes.add("hand_r", translation=(0.62, -0.04, 0.02))
    back_socket = nodes.add(
        "back_socket", translation=(0.0, 0.02, -0.20), rotation_deg=(12.0, 0.0, 0.0)
    )
    accessory_socket = nodes.add("accessory_socket", translation=(0.24, 0.12, 0.14))
    body = nodes.add(
        "body",
        translation=(0.0, 1.02, 0.0),
        children=[
            body_mesh,
            head,
            body_socket,
            hands_socket,
            hand_l,
            hand_r,
            back_socket,
            accessory_socket,
        ],
    )

    upper_leg_l = nodes.add("upper_leg_l", translation=(-0.12, 0.50, 0.0), children=[upper_leg_l_mesh])
    upper_leg_r = nodes.add("upper_leg_r", translation=(0.12, 0.50, 0.0), children=[upper_leg_r_mesh])
    foot_l = nodes.add("foot_l", translation=(-0.12, 0.08, 0.0), children=[foot_l_mesh])
    foot_r = nodes.add("foot_r", translation=(0.12, 0.08, 0.0), children=[foot_r_mesh])

    legs_socket = nodes.add("legs_socket", translation=(0.0, 0.50, 0.02))
    feet_socket = nodes.add("feet_socket", translation=(0.0, 0.08, 0.08))
    root = nodes.add(
        "humanoid_root",
        children=[body, upper_leg_l, upper_leg_r, foot_l, foot_r, legs_socket, feet_socket],
    )
    return nodes.nodes, root


def build_gltf():
    binary = bytearray()
    buffer_views = []
    accessors = []
    material_index = 0

    meshes = [
        build_mesh(binary, buffer_views, accessors, cube_geometry(), "unit_cube", material_index),
        build_mesh(binary, buffer_views, accessors, uv_sphere_geometry(), "unit_sphere", material_index),
    ]

    nodes, root = mannequin_nodes()
    while len(binary) % 4:
        binary.append(0)

    return {
        "asset": {"version": "2.0", "generator": "codex-humanoid-mannequin-generator"},
        "scene": 0,
        "scenes": [{"nodes": [root]}],
        "nodes": nodes,
        "materials": [
            {
                "name": "mannequin_default",
                "pbrMetallicRoughness": {
                    "baseColorFactor": [0.82, 0.84, 0.88, 1.0],
                    "metallicFactor": 0.02,
                    "roughnessFactor": 0.9,
                },
            }
        ],
        "meshes": meshes,
        "buffers": [
            {
                "byteLength": len(binary),
                "uri": "data:application/octet-stream;base64,"
                + base64.b64encode(binary).decode("ascii"),
            }
        ],
        "bufferViews": buffer_views,
        "accessors": accessors,
    }


def main():
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(build_gltf(), indent=2) + "\n", encoding="utf-8")
    print(f"wrote {OUTPUT}")


if __name__ == "__main__":
    main()

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
        1,
        2,
        0,
        2,
        3,
        4,
        5,
        6,
        4,
        6,
        7,
        8,
        9,
        10,
        8,
        10,
        11,
        12,
        13,
        14,
        12,
        14,
        15,
        16,
        17,
        18,
        16,
        18,
        19,
        20,
        21,
        22,
        20,
        22,
        23,
    ]
    return positions, normals, indices


def pack_f32_triplets(values):
    return b"".join(struct.pack("<fff", *value) for value in values)


def pack_u16(values):
    return b"".join(struct.pack("<H", value) for value in values)


def align_four(data):
    padding = (-len(data)) % 4
    if padding:
        data += b"\x00" * padding
    return data


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
    mesh_index = 0
    nodes = NodeBuilder()

    body_mesh = nodes.add("body_mesh", mesh=mesh_index, scale=(0.66, 0.82, 0.38))
    head_mesh = nodes.add("head_mesh", mesh=mesh_index, scale=(0.48, 0.48, 0.48))
    upper_arm_l_mesh = nodes.add(
        "upper_arm_l_mesh", translation=(0.0, -0.14, 0.02), mesh=mesh_index, scale=(0.16, 0.34, 0.16)
    )
    lower_arm_l_mesh = nodes.add(
        "lower_arm_l_mesh", translation=(0.0, -0.14, 0.02), mesh=mesh_index, scale=(0.14, 0.32, 0.14)
    )
    hand_l_mesh = nodes.add("hand_l_mesh", mesh=mesh_index, scale=(0.12, 0.12, 0.18))
    upper_arm_r_mesh = nodes.add(
        "upper_arm_r_mesh", translation=(0.0, -0.14, 0.02), mesh=mesh_index, scale=(0.16, 0.34, 0.16)
    )
    lower_arm_r_mesh = nodes.add(
        "lower_arm_r_mesh", translation=(0.0, -0.14, 0.02), mesh=mesh_index, scale=(0.14, 0.32, 0.14)
    )
    hand_r_mesh = nodes.add("hand_r_mesh", mesh=mesh_index, scale=(0.12, 0.12, 0.18))
    upper_leg_l_mesh = nodes.add(
        "upper_leg_l_mesh", translation=(0.0, -0.18, 0.0), mesh=mesh_index, scale=(0.20, 0.46, 0.22)
    )
    lower_leg_l_mesh = nodes.add(
        "lower_leg_l_mesh", translation=(0.0, -0.16, 0.0), mesh=mesh_index, scale=(0.18, 0.42, 0.20)
    )
    foot_l_mesh = nodes.add("foot_l_mesh", mesh=mesh_index, scale=(0.24, 0.10, 0.34))
    upper_leg_r_mesh = nodes.add(
        "upper_leg_r_mesh", translation=(0.0, -0.18, 0.0), mesh=mesh_index, scale=(0.20, 0.46, 0.22)
    )
    lower_leg_r_mesh = nodes.add(
        "lower_leg_r_mesh", translation=(0.0, -0.16, 0.0), mesh=mesh_index, scale=(0.18, 0.42, 0.20)
    )
    foot_r_mesh = nodes.add("foot_r_mesh", mesh=mesh_index, scale=(0.24, 0.10, 0.34))

    body_socket = nodes.add("body_socket", translation=(0.0, -0.02, 0.02))
    hands_socket = nodes.add("hands_socket", translation=(0.0, 0.03, 0.04))
    head_socket = nodes.add("head_socket", translation=(0.0, 0.24, 0.02))
    head = nodes.add("head", translation=(0.0, 0.12, 0.0), children=[head_mesh, head_socket])
    neck = nodes.add("neck", translation=(0.0, 0.36, 0.0), children=[head])
    back_socket = nodes.add(
        "back_socket", translation=(0.0, -0.10, -0.28), rotation_deg=(12.0, 0.0, 0.0)
    )
    accessory_socket = nodes.add("accessory_socket", translation=(0.18, 0.08, 0.14))
    spine = nodes.add(
        "spine",
        translation=(0.0, 0.14, 0.0),
        children=[body_mesh, neck, body_socket, hands_socket, back_socket, accessory_socket],
    )

    hand_l = nodes.add("hand_l", translation=(0.0, -0.28, 0.04), children=[hand_l_mesh])
    lower_arm_l = nodes.add(
        "lower_arm_l",
        translation=(0.0, -0.28, 0.06),
        rotation_deg=(0.0, 0.0, 10.0),
        children=[lower_arm_l_mesh, hand_l],
    )
    upper_arm_l = nodes.add(
        "upper_arm_l",
        translation=(-0.38, 0.16, 0.02),
        rotation_deg=(0.0, 0.0, 22.0),
        children=[upper_arm_l_mesh, lower_arm_l],
    )

    hand_r = nodes.add("hand_r", translation=(0.0, -0.28, 0.04), children=[hand_r_mesh])
    lower_arm_r = nodes.add(
        "lower_arm_r",
        translation=(0.0, -0.28, 0.06),
        rotation_deg=(0.0, 0.0, -10.0),
        children=[lower_arm_r_mesh, hand_r],
    )
    upper_arm_r = nodes.add(
        "upper_arm_r",
        translation=(0.38, 0.16, 0.02),
        rotation_deg=(0.0, 0.0, -22.0),
        children=[upper_arm_r_mesh, lower_arm_r],
    )

    foot_l = nodes.add("foot_l", translation=(0.02, -0.34, 0.10), children=[foot_l_mesh])
    lower_leg_l = nodes.add(
        "lower_leg_l", translation=(0.0, -0.36, 0.0), children=[lower_leg_l_mesh, foot_l]
    )
    upper_leg_l = nodes.add(
        "upper_leg_l", translation=(-0.16, -0.18, 0.0), children=[upper_leg_l_mesh, lower_leg_l]
    )

    foot_r = nodes.add("foot_r", translation=(-0.02, -0.34, 0.10), children=[foot_r_mesh])
    lower_leg_r = nodes.add(
        "lower_leg_r", translation=(0.0, -0.36, 0.0), children=[lower_leg_r_mesh, foot_r]
    )
    upper_leg_r = nodes.add(
        "upper_leg_r", translation=(0.16, -0.18, 0.0), children=[upper_leg_r_mesh, lower_leg_r]
    )

    legs_socket = nodes.add("legs_socket", translation=(0.0, -0.50, 0.02))
    feet_socket = nodes.add("feet_socket", translation=(0.0, -0.88, 0.08))
    pelvis = nodes.add(
        "pelvis",
        translation=(0.0, 0.94, 0.0),
        children=[spine, upper_arm_l, upper_arm_r, upper_leg_l, upper_leg_r, legs_socket, feet_socket],
    )
    root = nodes.add("humanoid_root", children=[pelvis])
    return nodes.nodes, root


def build_gltf():
    positions, normals, indices = cube_geometry()
    position_bytes = pack_f32_triplets(positions)
    normal_bytes = pack_f32_triplets(normals)
    index_bytes = pack_u16(indices)

    binary = align_four(position_bytes)
    normal_offset = len(binary)
    binary += align_four(normal_bytes)
    index_offset = len(binary)
    binary += align_four(index_bytes)

    nodes, root = mannequin_nodes()

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
        "meshes": [
            {
                "name": "unit_cube",
                "primitives": [
                    {
                        "attributes": {"POSITION": 0, "NORMAL": 1},
                        "indices": 2,
                        "material": 0,
                        "mode": 4,
                    }
                ],
            }
        ],
        "buffers": [
            {
                "byteLength": len(binary),
                "uri": "data:application/octet-stream;base64,"
                + base64.b64encode(binary).decode("ascii"),
            }
        ],
        "bufferViews": [
            {"buffer": 0, "byteOffset": 0, "byteLength": len(position_bytes), "target": 34962},
            {
                "buffer": 0,
                "byteOffset": normal_offset,
                "byteLength": len(normal_bytes),
                "target": 34962,
            },
            {
                "buffer": 0,
                "byteOffset": index_offset,
                "byteLength": len(index_bytes),
                "target": 34963,
            },
        ],
        "accessors": [
            {
                "bufferView": 0,
                "componentType": 5126,
                "count": len(positions),
                "type": "VEC3",
                "min": [-0.5, -0.5, -0.5],
                "max": [0.5, 0.5, 0.5],
            },
            {
                "bufferView": 1,
                "componentType": 5126,
                "count": len(normals),
                "type": "VEC3",
            },
            {
                "bufferView": 2,
                "componentType": 5123,
                "count": len(indices),
                "type": "SCALAR",
            },
        ],
    }


def main():
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(build_gltf(), indent=2) + "\n", encoding="utf-8")
    print(f"wrote {OUTPUT}")


if __name__ == "__main__":
    main()

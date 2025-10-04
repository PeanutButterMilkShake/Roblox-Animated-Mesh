import bpy
import json

obj = bpy.context.active_object

if obj is None:
    print("No active object selected.")
else:
    if obj.data.shape_keys:
        shape_key_data = {}

        basis = obj.data.shape_keys.key_blocks.get("Basis")

        for key_block in obj.data.shape_keys.key_blocks:
            key_info = {
                "value": key_block.value,
                "vertices": []
            }

            for i, v in enumerate(key_block.data):
                if basis and key_block != basis:
                    delta = (
                        v.co.x - basis.data[i].co.x,
                        v.co.z - basis.data[i].co.z,
                        v.co.y - basis.data[i].co.y,
                    )
                    key_info["vertices"].append(delta)
                else:
                    key_info["vertices"].append((v.co.x, v.co.y, v.co.z))

            shape_key_data[key_block.name] = key_info

        json_data = json.dumps(shape_key_data, indent=2)

        bpy.context.window_manager.clipboard = json_data

        print("Shape key values and vertex data copied to clipboard.")
    else:
        print(f"Object '{obj.name}' has no shape keys.")

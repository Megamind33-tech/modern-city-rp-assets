#!/usr/bin/env python3
"""Generate game/assets/palette.png (256x256, 8x8 cells of 32 px) and palette.json
exactly from the ART_BIBLE palette table. Index = row*8 + col.
Run: python3 tools/blender/palette.py   (needs Pillow) -- also importable (PALETTE list)."""
import json, os, sys

PALETTE = [
    # row 0 brand/station
    ("navy", "1D2A3A"), ("signal_red", "E24B3B"), ("red_dark", "B8352A"), ("amber", "F2A93B"),
    ("cream", "F6EBD9"), ("teal", "2E9C9A"), ("steel", "B8BCC4"), ("tyre", "1F2023"),
    # row 1 walls
    ("butter", "F3DFB5"), ("sage", "CFE0D6"), ("peach", "F0C8A8"), ("lavender", "DCD6EA"),
    ("sand", "E6D3B3"), ("brick", "B5503E"), ("plaster", "EDE8DE"), ("pale_blue", "CFDDE8"),
    # row 2 roof/structure
    ("slate", "5B5F6B"), ("roof_brown", "5C4B4B"), ("terracotta", "B8654A"), ("dark_wood", "6B4A30"),
    ("light_wood", "C49E6B"), ("glass", "9FD0E0"), ("door_navy", "2B3A55"), ("door_green", "3E6B4F"),
    # row 3 nature
    ("grass", "6B9E5B"), ("grass_dark", "557F48"), ("leaf", "4E8541"), ("leaf_light", "7FAE5C"),
    ("bark", "66472E"), ("soil", "7A5C40"), ("flower_pink", "D96C8C"), ("flower_yellow", "E8C547"),
    # row 4 ground
    ("asphalt", "3E4047"), ("asphalt_light", "5A5D66"), ("kerb", "B3AEA2"), ("pavement", "CFC9BC"),
    ("line_white", "F2EAD3"), ("line_yellow", "E8B83A"), ("concrete", "A9A69E"), ("gravel", "8E8A80"),
    # row 5 skin/hair
    ("skin1", "F1C9A5"), ("skin2", "D9A27C"), ("skin3", "A86F4C"), ("skin4", "6E4630"),
    ("hair_dark", "2E2420"), ("hair_brown", "6A4428"), ("hair_blonde", "D8B46A"), ("hair_grey", "A8A39C"),
    # row 6 clothing
    ("hi_vis", "D9E04A"), ("uniform_navy", "273449"), ("denim", "4D6A8F"), ("knit_red", "A8443C"),
    ("cardigan_green", "5E7F5A"), ("shirt_white", "EEE9E0"), ("mustard", "C99A3A"), ("plum", "6E4A6A"),
    # row 7 hazard/fx/damage
    ("tarp_blue", "3368C4"), ("cone_orange", "F26B1D"), ("warning_red", "D93A2B"), ("emissive_amber", "FFB547"),
    ("emissive_blue", "4A7BFF"), ("spark", "FFE38A"), ("char", "2B2725"), ("water", "5F9FBF"),
]
NAME_TO_INDEX = {n: i for i, (n, _) in enumerate(PALETTE)}
EMISSIVE = {59, 60, 61}  # emissive amber, emissive blue, spark


def rgb(i):
    h = PALETTE[i][1]
    return tuple(int(h[k:k + 2], 16) for k in (0, 2, 4))


def uv(i):
    r, c = divmod(i, 8)
    # glTF/Godot UV origin is top-left; Blender's is bottom-left (exporter flips v).
    return ((c + 0.5) / 8.0, 1.0 - (r + 0.5) / 8.0)


def main():
    from PIL import Image
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    out = os.path.join(root, "game", "assets")
    os.makedirs(out, exist_ok=True)
    img = Image.new("RGB", (256, 256))
    px = img.load()
    for i in range(64):
        r, c = divmod(i, 8)
        col = rgb(i)
        for y in range(32):
            for x in range(32):
                px[c * 32 + x, r * 32 + y] = col
    img.save(os.path.join(out, "palette.png"))
    with open(os.path.join(out, "palette.json"), "w") as f:
        json.dump({"cell_px": 32, "grid": 8,
                   "colors": {str(i): {"name": n, "hex": "#" + h} for i, (n, h) in enumerate(PALETTE)},
                   "emissive": sorted(EMISSIVE)}, f, indent=1)
    print("palette written", out)


if __name__ == "__main__":
    main()

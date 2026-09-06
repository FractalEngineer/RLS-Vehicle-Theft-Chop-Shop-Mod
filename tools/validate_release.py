"""Validate source and optionally build the explicit release manifest.

Requires Pillow and lupa (Lua runtime); --lua-deps can point at a temp install.
Run from the repository root. Research, tests and imported originals never ship.
"""
import argparse
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument("--lua-deps", type=Path)
parser.add_argument("--package", action="store_true")
args = parser.parse_args()
if args.lua_deps:
    sys.path.insert(0, str(args.lua_deps))
from PIL import Image
from lupa.luajit21 import LuaRuntime

FILES = [
    "README.md",
    "lua/ge/extensions/career/modules/carjacking.lua",
    "mod_info/M3Z1BLS58/icon.jpg",
    "mod_info/M3Z1BLS58/info.json",
    "ui/modModules/rlsCarjacking/rlsCarjacking.js",
    "ui/modModules/rlsCarjacking/icons/hotwire.svg",
    "ui/modModules/rlsCarjacking/icons/strip_for_parts.svg",
]
metadata = json.loads(Path(FILES[3]).read_text(encoding="utf-8"))
assert metadata["tagid"] == "M3Z1BLS58"
version = metadata["version_string"]
assert metadata["filename"] == f"rls_carjacking_v{version}.zip"
assert "resource_id" not in metadata and "resource_version_id" not in metadata
with Image.open(FILES[2]) as icon:
    assert icon.size == (96, 96) and icon.mode == "RGB"
for name in FILES:
    assert Path(name).is_file() and "_archived" not in name
    if name.endswith((".lua", ".js", ".md", ".json")):
        assert "abandon" not in Path(name).read_text(encoding="utf-8").lower()
for name in FILES[-2:]:
    assert ET.parse(name).getroot().tag == "{http://www.w3.org/2000/svg}svg"
    assert Path(name).read_bytes() == (Path("Import") / Path(name).name).read_bytes()
assert f"-- Version {version}." in Path(FILES[1]).read_text(encoding="utf-8")
runtime = LuaRuntime()
runtime.execute("local f,e = loadfile(...) assert(f,e)", FILES[1])
runtime.execute("assert(loadfile(...))()", "tests/test_carjacking.lua")
print(f"PASS: {runtime.lua_implementation} loadfile, metadata, RGB icon, SVGs, manifest")
if args.package:
    output = Path("releases") / metadata["filename"]
    output.parent.mkdir(exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as package:
        for name in FILES:
            package.write(name, name)
    with zipfile.ZipFile(output) as package:
        assert package.namelist() == FILES
        assert package.testzip() is None
        for name in FILES:
            assert package.read(name) == Path(name).read_bytes()
    print(f"PASS: {output} ({output.stat().st_size:,} bytes, {len(FILES)} files)")

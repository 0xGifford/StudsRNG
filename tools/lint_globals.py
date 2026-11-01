#!/usr/bin/env python3
"""Flags unknown globals in every Luau file (typos, locals used before
they're defined, missing requires). Roblox's own globals are allowed.

    python3 tools/lint_globals.py [path/to/luau-analyze]

Needs luau-analyze (https://github.com/luau-lang/luau/releases); the
default path is /tmp/luau/luau-analyze."""
import re, subprocess, sys, pathlib

ROBLOX = set("""
game workspace script plugin shared Instance Enum Vector2 Vector3 Vector2int16 Vector3int16 CFrame Color3 ColorSequence
ColorSequenceKeypoint NumberSequence NumberSequenceKeypoint NumberRange UDim UDim2 Rect Region3 Region3int16 Ray
RaycastParams OverlapParams TweenInfo BrickColor PhysicalProperties Random Font Faces Axes DateTime PathWaypoint
CatalogSearchParams FloatCurveKey RotationCurveKey SharedTable Path2DControlPoint Content buffer vector
task warn tick time wait delay spawn elapsedTime settings UserSettings typeof require debug utf8 bit32 os
""".split())

analyzer = sys.argv[1] if len(sys.argv) > 1 else "/tmp/luau/luau-analyze"
files = [str(p) for p in pathlib.Path(".").glob("src/**/*.lua")] + [str(p) for p in pathlib.Path(".").glob("src/**/*.luau")]
problems = []
for i in range(0, len(files), 40):
    out = subprocess.run([analyzer, "--mode=nonstrict", *files[i:i + 40]], capture_output=True, text=True)
    out = out.stdout + out.stderr
    for line in out.splitlines():
        m = re.search(r"^(.*?)\((\d+),\d+\).*Unknown global '([^']+)'", line)
        if m and m.group(3) not in ROBLOX:
            problems.append(f"{m.group(1)}:{m.group(2)}: unknown global {m.group(3)}")
for p in problems:
    print(p)
print(f"{len(files)} files, {len(problems)} unknown global(s)")
sys.exit(1 if problems else 0)

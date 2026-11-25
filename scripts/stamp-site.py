#!/usr/bin/env python3
"""Write the latest release's version, size and SHA-256, and the total download count, into the site before it's deployed.

    scripts/stamp-site.py docs/index.html latest.json releases.json

latest.json is `gh api repos/{owner}/{repo}/releases/latest`; releases.json is `gh api --paginate --slurp repos/{owner}/{repo}/releases`.
"""
import json
import re
import sys

page, latest_file, all_file = sys.argv[1:]
release = json.load(open(latest_file))
releases = [r for page in json.load(open(all_file)) for r in page]
dmg = next(a for a in release["assets"] if a["name"].endswith(".dmg"))

version = release["tag_name"].removeprefix("v")
size = f'{dmg["size"] / 1048576:.1f} MB'
sha = (dmg.get("digest") or "").removeprefix("sha256:")
# the DMG and the zip the install command fetches; not the checksum file
downloads = sum(a["download_count"] for r in releases for a in r["assets"] if a["name"].endswith((".dmg", ".zip")))

html = open(page).read()

def fill(key, value):
    global html
    html = re.sub(rf'(<(\w+)[^>]*data-v="{key}"[^>]*>).*?(</\2>)', lambda m: m[1] + value + m[3], html)

fill("version", version)
fill("size", size)
fill("downloads", f"{downloads:,}")
if sha:
    fill("sha", sha)
html = re.sub(r'"softwareVersion": "[^"]*"', f'"softwareVersion": "{version}"', html)
html = re.sub(r'"fileSize": "[^"]*"', f'"fileSize": "{size}"', html)

open(page, "w").write(html)
print(f"site: v{version} · {size} · {sha[:12] or 'no checksum'} · {downloads:,} downloads")

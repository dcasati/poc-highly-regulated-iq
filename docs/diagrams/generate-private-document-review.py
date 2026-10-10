#!/usr/bin/env python3
"""Render the canonical architecture offline, with unchanged official SVG icons."""

import argparse
import base64
import hashlib
import html
import json
from pathlib import Path
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parent
WIDTH, HEIGHT = 1800, 1500
NAVY, BLUE, GREEN, AMBER, GRAY = "#203747", "#6D9FD1", "#71B381", "#DF9C22", "#9FAABA"
COLORS = {
    "service": (BLUE, "#FFFFFF"),
    "data": (GREEN, "#F4FAF5"),
    "human": (AMBER, "#FFF8E8"),
    "logic": (GRAY, "#F4F5F7"),
}
FONT = "Helvetica, Arial, sans-serif"
elements, files, parts, text_bounds, cards = [], {}, [], [], []


def measured_font(size, bold=False):
    from PIL import ImageFont
    candidates = [
        ("/System/Library/Fonts/Helvetica.ttc", 1 if bold else 0),
        ("/usr/share/fonts/truetype/liberation2/LiberationSans-Bold.ttf" if bold
         else "/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf", 0),
        ("/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf" if bold
         else "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf", 0),
    ]
    for path, index in candidates:
        if Path(path).is_file():
            return ImageFont.truetype(path, size=size, index=index)
    raise RuntimeError("Diagram font unavailable: use macOS Helvetica or install fonts-liberation on Linux. See docs/diagrams/README.md.")


def element(kind, x, y, width, height, **extra):
    item = {
        "id": f"architecture-{len(elements):03d}",
        "type": kind, "x": x, "y": y, "width": width, "height": height,
        "angle": 0, "strokeColor": BLUE, "backgroundColor": "transparent",
        "fillStyle": "solid", "strokeWidth": 1.5, "strokeStyle": "solid",
        "roughness": 0, "opacity": 100, "groupIds": [], "frameId": None,
        "roundness": None, "seed": len(elements) + 1, "version": 1,
        "versionNonce": 0, "isDeleted": False, "boundElements": None,
        "updated": 1, "link": None, "locked": False,
    }
    item.update(extra)
    elements.append(item)
    return item


def rect(x, y, w, h, stroke=BLUE, fill="transparent", radius=20, dashed=False):
    element("rectangle", x, y, w, h, strokeColor=stroke, backgroundColor=fill,
            roundness={"type": 3} if radius else None,
            strokeStyle="dashed" if dashed else "solid")
    dash = ' stroke-dasharray="6 6"' if dashed else ""
    parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{radius}" '
                 f'fill="{fill if fill != "transparent" else "none"}" '
                 f'stroke="{stroke}" stroke-width="2"{dash}/>')


def text(x, y, lines, size=22, bold=False, max_width=None):
    if isinstance(lines, str):
        lines = [lines]
    font = measured_font(size, bold)
    width = max(font.getlength(line) for line in lines)
    if max_width is not None:
        assert width <= max_width, (lines, width, max_width)
    visible_height = size * 1.38 * len(lines)
    assert x >= 0 and y >= 0 and x + width <= WIDTH and y + visible_height <= HEIGHT
    text_bounds.append((x, y, width, visible_height))
    element("text", x, y, width + 8, size * 2.5 * len(lines),
            text="\n".join(lines), originalText="\n".join(lines),
            fontSize=size, fontFamily=2, strokeColor="#000000",
            textAlign="left", verticalAlign="top", containerId=None,
            autoResize=True, lineHeight=1.38)
    weight = ' font-weight="700"' if bold else ""
    spans = "".join(
        f'<tspan x="{x}" y="{y + size + i * size * 1.38:.2f}">'
        f'{html.escape(line)}</tspan>' for i, line in enumerate(lines)
    )
    parts.append(f'<text font-family="{FONT}" font-size="{size}" fill="{NAVY}"'
                 f'{weight}>{spans}</text>')


def icon(key, x, y, size=82):
    asset = ROOT / "icons" / ICONS[key]["file"]
    raw = asset.read_bytes()
    assert hashlib.sha256(raw).hexdigest() == ICONS[key]["sha256"]
    ET.fromstring(raw)
    data = "data:image/svg+xml;base64," + base64.b64encode(raw).decode()
    files[key] = {"id": key, "mimeType": "image/svg+xml", "dataURL": data,
                  "created": 1, "lastRetrieved": 1}
    element("image", x, y, size, size, fileId=key, status="saved", scale=[1, 1])
    parts.append(f'<image x="{x}" y="{y}" width="{size}" height="{size}" '
                 f'href="{data}" preserveAspectRatio="xMidYMid meet"/>')


def lane(y, h, title):
    rect(25, y, WIDTH - 50, h, stroke="#AEC7E3", radius=16)
    # Header is a leaf, not an opaque container over the cards.
    rect(26, y + 1, WIDTH - 52, 64, stroke="#AEC7E3", fill="#EDF4FB", radius=15)
    text(60, y + 14, title, 28, True, WIDTH - 140)


def card(x, y, title, body, kind="service", glyph=None, w=390, h=330):
    stroke, fill = COLORS[kind]
    rect(x, y, w, h, stroke, fill, 32)
    cards.append((x, y, w, h))
    if glyph:
        icon(glyph, x + 30, y + 34)
        text(x + 142, y + 47, title, 25, True, w - 166)
    else:
        text(x + 32, y + 55, title, 26, True, w - 60)
    body_y = y + 166
    text(x + 32, body_y, body, 22, max_width=w - 62)
    assert body_y + len(body) * 22 * 1.38 <= y + h - 20, title


def arrow(points, label=None, label_xy=None, color="#446886", dashed=False):
    x, y = points[0]
    relative = [[px - x, py - y] for px, py in points]
    element("arrow", x, y,
            max(p[0] for p in points) - min(p[0] for p in points),
            max(p[1] for p in points) - min(p[1] for p in points),
            strokeColor=color, strokeWidth=2, strokeStyle="dashed" if dashed else "solid",
            points=relative, startBinding=None, endBinding=None,
            startArrowhead=None, endArrowhead="arrow", elbowed=False)
    for a, b in zip(points, points[1:]):
        assert a[0] == b[0] or a[1] == b[1], "Use orthogonal connectors"
        for cx, cy, cw, ch in cards:
            if a[0] == b[0]:
                assert not (cx < a[0] < cx + cw and
                            max(min(a[1], b[1]), cy) < min(max(a[1], b[1]), cy + ch))
            else:
                assert not (cy < a[1] < cy + ch and
                            max(min(a[0], b[0]), cx) < min(max(a[0], b[0]), cx + cw))
    dash = ' stroke-dasharray="6 6"' if dashed else ""
    marker = "amber-arrow" if color == AMBER else "arrow"
    parts.append(f'<polyline points="{" ".join(f"{px},{py}" for px, py in points)}" '
                 f'fill="none" stroke="{color}" stroke-width="3" '
                 f'stroke-linejoin="round" marker-end="url(#{marker})"{dash}/>')
    if label:
        lx, ly = label_xy
        if isinstance(label, str):
            label = [label]
        font = measured_font(18)
        width = max(font.getlength(line) for line in label) + 12
        label_height = len(label) * 24.84 + 6
        for a, b in zip(points, points[1:]):
            if a[0] == b[0]:
                assert not (lx - 6 < a[0] < lx - 6 + width and
                            max(min(a[1], b[1]), ly - 2) <
                            min(max(a[1], b[1]), ly - 2 + label_height)), label
            else:
                assert not (ly - 2 < a[1] < ly - 2 + label_height and
                            max(min(a[0], b[0]), lx - 6) <
                            min(max(a[0], b[0]), lx - 6 + width)), label
        rect(lx - 6, ly - 2, width, label_height,
             stroke="#FFFFFF", fill="#FFFFFF", radius=0)
        text(lx, ly, label, 18)


def build():
    text(45, 25, "Private document review | Application flow", 38, True)
    text(45, 90, "Synthetic documents only. People make decisions; model answers are suggestions.", 24)
    xs = [45, 485, 925, 1365]
    lane(160, 445, "1  Upload, extract and confirm")
    card(xs[0], 255, ["Case owner"], [
        "Entra sign-in",
        "Upload PDF through portal",
        "No direct data-service access",
    ], glyph="entra_roles", h=290)
    card(xs[1], 255, ["Portal / API", "+ worker"], [
        "Authorize owner and roles",
        "Retain original and case state",
        "Call extraction service",
    ], glyph="container_apps", h=290)
    card(xs[2], 255, ["Content", "Understanding"], [
        "Propose fields and sources",
        "Extraction is not approval",
    ], glyph="content", h=290)
    card(xs[3], 255, ["Owner self-review"], [
        "Both assigned roles required",
        "Correct and confirm every field",
        "API checks gate publication",
    ], "human", h=290)
    for i in range(3):
        arrow([(xs[i] + 390, 410), (xs[i + 1], 410)])

    lane(690, 445, "2  Publish evidence and ask case-scoped questions")
    card(xs[0], 785, ["Published", "evidence"], [
        "Approved PDF + corrected fields",
        "Originals / case state not indexed",
        "Publication can be retried safely",
    ], "data", "storage", h=290)
    card(xs[1], 785, ["Search /", "Foundry IQ"], [
        "Index published evidence",
        "API enforces case + owner filters",
        "API validates source records",
    ], glyph="search", h=290)
    card(xs[2], 785, ["Azure OpenAI"], [
        "Direct private inference; no tools",
        "API supplies validated evidence",
        "Citation IDs checked by API",
    ], glyph="foundry", h=290)
    card(xs[3], 785, ["Answer suggestion"], [
        "Shown through portal",
        "Citation IDs do not prove truth",
        "Human verifies the evidence",
    ], "logic", h=290)
    for i in range(3):
        arrow([(xs[i] + 390, 940), (xs[i + 1], 940)])
    arrow([(1560, 545), (1560, 640), (15, 640), (15, 900), (45, 900)], color=AMBER)
    text(550, 650, "Only after explicit confirmation", 21)
    rect(25, 1180, 1750, 205, stroke=GRAY)
    text(55, 1200, "Trust boundaries", 27, True)
    text(55, 1250, [
        "API and worker share one trusted identity; containers are not privilege isolation.",
        "Model output cannot authorize publication. Instructions do not guarantee grounded answers.",
        "All app/data access is private. Network access is shown separately in the connectivity diagram.",
    ], 24, max_width=1670)
    text(45, 1420, "Arrows summarize the workflow, not every network request. Infrastructure publication is not proof of live readiness.", 21)


def outputs():
    svg = (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{HEIGHT}" '
        f'viewBox="0 0 {WIDTH} {HEIGHT}" role="img" aria-labelledby="diagram-title diagram-description">\n'
        '<title id="diagram-title">Private document review | Current Azure service architecture</title>\n'
        '<desc id="diagram-description">Two workflow lanes: private portal upload, Content Understanding extraction and owner self-review; '
        'publication of approved PDFs and corrected fields, Search and Foundry IQ retrieval, and direct no-tools Azure OpenAI inference. '
        'The API enforces case-and-owner authorization and validates sources and citation IDs. API and worker share one trusted identity. '
        'Model suggestions cannot authorize publication and require human verification. Synthetic-only; not a live readiness report.</desc>\n'
        '<defs><marker id="arrow" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto">'
        '<path d="M0 0 L8 4 L0 8 Z" fill="#446886"/></marker>'
        '<marker id="amber-arrow" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto">'
        f'<path d="M0 0 L8 4 L0 8 Z" fill="{AMBER}"/></marker></defs>\n'
        f'<rect width="{WIDTH}" height="{HEIGHT}" fill="#FFFFFF"/>\n'
        + "\n".join(parts) + "\n</svg>\n"
    )
    drawing = {
        "type": "excalidraw", "version": 2, "source": "private-document-review offline generator",
        "elements": elements,
        "appState": {"viewBackgroundColor": "#FFFFFF", "gridSize": None},
        "files": files,
    }
    return {
        ROOT / "private-document-review.svg": svg,
        ROOT / "private-document-review.excalidraw": json.dumps(drawing, indent=2) + "\n",
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Validate geometry, icons and deterministic committed outputs")
    args = parser.parse_args()
    ICONS = json.loads((ROOT / "icons" / "manifest.json").read_text())
    build()
    generated = outputs()
    assert len({item["id"] for item in elements}) == len(elements)
    assert all(item["fileId"] in files for item in elements if item["type"] == "image")
    assert all(item["width"] > 0 and item["height"] > 0
               for item in elements if item["type"] in ("text", "image"))
    if args.check:
        for path, expected in generated.items():
            assert path.read_text() == expected, f"Stale output: {path.name}"
    else:
        for path, content in generated.items():
            path.write_text(content)
    print(f"{'Checked' if args.check else 'Generated'} SVG + Excalidraw; "
          f"{len(elements)} elements, {len(files)} embedded official icons; geometry validated.")

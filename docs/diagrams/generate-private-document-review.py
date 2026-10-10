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
WIDTH, HEIGHT = 2400, 2820
NAVY, BLUE, GREEN, AMBER, GRAY = "#203747", "#6D9FD1", "#71B381", "#DF9C22", "#9FAABA"
COLORS = {
    "service": (BLUE, "#FFFFFF"),
    "data": (GREEN, "#F4FAF5"),
    "human": (AMBER, "#FFF8E8"),
    "logic": (GRAY, "#F4F5F7"),
}
FONT = "Helvetica, Arial, sans-serif"
elements, files, parts, text_bounds, cards = [], {}, [], [], []


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
    # Conservatively validate actual Helvetica glyph extents, not padded editor bounds.
    from PIL import ImageFont
    font = ImageFont.truetype(
        "/System/Library/Fonts/Helvetica.ttc",
        size=size, index=1 if bold else 0,
    )
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
    rect(25, y, 2350, h, stroke="#AEC7E3", radius=16)
    # Header is a leaf, not an opaque container over the cards.
    rect(26, y + 1, 2348, 64, stroke="#AEC7E3", fill="#EDF4FB", radius=15)
    text(60, y + 14, title, 28, True, 2260)


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
        from PIL import ImageFont
        font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 18)
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
    text(40, 26, "Private document review | Azure service architecture", 44, True)
    text(40, 104,
         "Evidence flows through human validation before indexing; answers are scoped to the authenticated owner's selected case.", 25)
    text(40, 153,
         "Current solution boundaries • synthetic PoC • architecture, not a readiness or certification claim", 21)

    xs = [70, 535, 1000, 1465, 1930]
    lane(220, 495, "1  Intake, extraction and human review | left to right")
    y = 340
    card(xs[0], y, ["Microsoft Entra ID", "+ browser"], [
        "SPA authorization code + PKCE",
        "API JWT, delegated scope, roles",
        "Caseworker / Reviewer",
        "Browser uploads; Entra signs in",
    ], glyph="entra_roles")
    card(xs[1], y, ["Azure Container", "Apps"], [
        "Portal API + durable worker",
        "Managed Environment PE / TLS",
        "Internal; public network Disabled",
        "Peer encryption; runtime identity",
    ], glyph="container_apps")
    card(xs[2], y, ["Azure Blob", "Storage"], [
        "Original PDF + original SHA-256",
        "Durable case state + leases",
        "Bounded extraction / polling",
        "Retain full extraction + review",
    ], "data", "storage")
    card(xs[3], y, ["Content", "Understanding"], [
        "Application calls custom analyzer",
        "Fields, confidence + sources",
        "Retained PDF is the input",
        "Extraction is not approval",
    ], glyph="content")
    card(xs[4], y, ["Human validation"], [
        "Inspect original + field evidence",
        "Correct and confirm every field",
        "Reviewer role + owner match",
        "Confirmation gates publication",
    ], "human")
    for i, label in enumerate([
        "JWT / PDF", "Retain", "Worker", "Fields",
    ]):
        arrow([(xs[i] + 390, 490), (xs[i + 1], 490)], label, (xs[i] + 397, 451))

    lane(775, 480, "2  Publication and knowledge indexing | right to left")
    text(70, 884, "Private connectivity + authorization boundaries", 27, True, 870)
    text(70, 954, [
        "Runtime managed identity calls private Azure services.",
        "Search managed identity reads ONLY the two published containers.",
        "Native shared private links: Search to Blob and CU.",
        "PDF layout skill is not the custom extraction analyzer.",
        "Private DNS / endpoints; keyless access and scoped RBAC.",
        "Foundry IQ uses searchIndex — no Fabric source in this app.",
    ], 22, max_width=870)
    card(xs[2], 880, ["Foundry IQ"], [
        "Knowledge base: searchIndex",
        "Extractive evidence retrieval",
        "Semantic text / minimal retrieval",
        "No Fabric source attached",
    ], glyph="iq", h=320)
    card(xs[3], 880, ["Azure AI Search"], [
        "Private / keyless index + skillset",
        "PDF layout + JSON indexers",
        "Page chunks + reviewed fields",
        "case_id + owner_id metadata",
    ], glyph="search", h=320)
    card(xs[4], 880, ["Azure Blob", "Storage"], [
        "Approved, unchanged PDF copy",
        "Human-validated field JSON",
        "Only these containers indexed",
        "Originals / state excluded",
    ], "data", "storage", h=320)
    arrow([(2125, 670), (2125, 880)], "Portal publishes only after confirmation", (1780, 736), AMBER)
    arrow([(1930, 1030), (1855, 1030)], "Indexers", (1858, 993))
    arrow([(1465, 1030), (1390, 1030)], "Source", (1395, 993))

    lane(1360, 510, "3  Case-scoped question answering | left to right")
    card(xs[0], 1470, ["Reviewer question"], [
        "Selected approved case",
        "Question + untrusted history",
        "Submitted through portal UI",
        "Cannot select another owner",
    ], "logic", h=340)
    card(xs[1], 1470, ["Portal API"], [
        "Checks identity + Approved state",
        "Owner from authenticated token",
        "Filter: case_id AND owner_id",
        "Always query; retrieval fail-closed",
    ], "logic", h=340)
    card(xs[2], 1470, ["Reference checks"], [
        "Verify EVERY source reference",
        "Case + owner metadata match",
        "Reject missing / partial evidence",
        "Pass all current reviewed fields",
    ], "logic", h=340)
    card(xs[3], 1470, ["Foundry Agent", "Service"], [
        "Managed prompt agent",
        "Question + untrusted history",
        "Reviewed fields + evidence",
        "Tools disabled; store=false",
        "Native scope + Prompt Shields",
    ], glyph="agent", h=340)
    card(xs[4], 1470, ["Answer + citations"], [
        "Current reference IDs only",
        "Returned through portal API / UI",
        "Human judgment authoritative",
        "Never approve / deny / decide",
        "No eligibility determinations",
    ], "logic", h=340)
    arrow([(730, 1470), (730, 1320), (1115, 1320), (1115, 1200)],
          "Case + owner filtered retrieval", (763, 1280))
    arrow([(1260, 1200), (1260, 1328), (1195, 1328), (1195, 1470)],
          "Evidence + references", (1280, 1288))
    for i, label in enumerate([
        "Question", "Validate", "Evidence", "Answer",
    ]):
        arrow([(xs[i] + 390, 1620), (xs[i + 1], 1620)], label, (xs[i] + 396, 1580))

    lane(1920, 255, "Native security controls | managed instructions and model policy, not app safety judges")
    text(70, 2006, "Task-scope managed instructions", 25, True, 700)
    text(70, 2050, [
        "Whole-request refusal for unrelated or mixed tasks.",
        "Fields / documents / history are data, not instructions.",
        "Only current evidence; human authority remains final.",
    ], 21, max_width=710)
    text(855, 2006, "Chat model • native Prompt Shields", 25, True, 710)
    text(855, 2050, [
        "Blocking: Medium harm on Prompt + Completion.",
        "Binary Jailbreak / Indirect Attack on Prompt.",
        "Protected material Completion; rai_config: full policy ARM ID.",
    ], 21, max_width=710)
    text(1640, 2006, "Evidence limits — not zero injection risk", 25, True, 675)
    text(1640, 2050, [
        "Strong jailbreak blocked; field fixtures ignored.",
        "Responses indirect-detector coverage unproven.",
        "Native preview behavior needs separate acceptance.",
    ], 21, max_width=665)

    lane(2225, 260, "Supporting platform | infrastructure and image delivery, NOT the document data path")
    icon("network", 65, 2311, 62)
    text(145, 2322, "Private VNet / DNS / endpoints", 25, True, 675)
    text(70, 2400, [
        "Managed Environment PE, not internal ILB alone.",
        "No public app / data ingress; private HTTPS.",
    ], 21, max_width=710)
    icon("foundry", 855, 2311, 62)
    text(935, 2322, "Foundry private agent foundation", 25, True, 625)
    text(855, 2400, [
        "Private inbound / outbound; BYO Blob + Cosmos stores.",
        "Native agent state separate from application evidence.",
    ], 21, max_width=710)
    icon("registry", 1640, 2311, 62)
    text(1720, 2322, "Private ACR + build pool", 25, True, 600)
    text(1640, 2400, [
        "Immutable digest images; private registry + MI pulls.",
        "VNet-connected build pool currently idle.",
    ], 21, max_width=670)

    rect(25, 2530, 2350, 112, stroke=GRAY, dashed=True)
    text(60, 2548, "Separate inherited Fabric sample — NOT connected to the review app", 26, True)
    text(60, 2591, "Synthetic lakehouse to Site / Asset ontology. Reference only; separate deployment and delegated authorization required.", 22)
    text(40, 2676, [
        "Approved processing boundary • controlled outbound-only NAT public IP, not public ingress or unrestricted Internet.",
        "Synthetic PoC: FIPS attestations deferred / NOT certified. Preview limitations and end-to-end readiness remain separate verification gates.",
    ], 21)
    text(40, 2750,
         "Legend: blue = Azure service | green = stored data | amber = human gate | gray = app logic. Official Microsoft icons, embedded offline; see icons/NOTICE.md.", 19)


def outputs():
    svg = (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{HEIGHT}" '
        f'viewBox="0 0 {WIDTH} {HEIGHT}" role="img" aria-labelledby="diagram-title diagram-description">\n'
        '<title id="diagram-title">Private document review | Current Azure service architecture</title>\n'
        '<desc id="diagram-description">Three directional lanes: retain original PDFs, custom extraction and explicit human validation; '
        'publish only approved copies and reviewed JSON to private Search indexers and a searchIndex Foundry IQ knowledge base; '
        'server-authorized case-and-owner retrieval with every reference checked before a tools-disabled managed prompt agent. '
        'Actual Container Apps Managed Environment private endpoint, native scope refusal and Prompt Shields, supporting private '
        'platform and separate disconnected inherited Fabric sample. Synthetic PoC, not readiness or FIPS certification.</desc>\n'
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

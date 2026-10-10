#!/usr/bin/env python3
"""Build the canonical static offline network view."""

import argparse
import importlib.util
import json
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("architecture", ROOT / "generate-private-document-review.py")
d = importlib.util.module_from_spec(spec)
spec.loader.exec_module(d)
d.WIDTH, d.HEIGHT = 1800, 1320
d.NAVY = "#000000"
d.ICONS = json.loads((ROOT / "icons/manifest.json").read_text())
BLUE, GREEN, AMBER, GRAY = "#0078D4", "#107C10", "#CF7900", "#647488"
routes = {}


def box(x, y, w, h, title, body, glyph=None, color=BLUE):
    d.rect(x, y, w, h, stroke=color, radius=16)
    d.cards.append((x, y, w, h))
    if glyph:
        d.icon(glyph, x + 22, y + 20, 48)
    d.text(x + (86 if glyph else 22), y + 22, title, 27, True,
           w - (108 if glyph else 44))
    d.text(x + 22, y + 70, body, 22, max_width=w - 44)
    assert y + 70 + len(body) * 22 * 1.38 <= y + h - 12, title


def route(name, points, color=BLUE, dashed=False):
    routes[name] = {"points": points, "color": color, "dns": dashed}
    d.arrow(points, color=color, dashed=dashed)
    # The inherited renderer has two marker colors; each network route owns its marker.
    d.parts[-1] = d.parts[-1].replace('url(#arrow)', f'url(#{name}-head)').replace(
        'url(#amber-arrow)', f'url(#{name}-head)')


def build():
    d.text(45, 25, "Private network connectivity | Document review", 38, True)
    d.text(45, 90, "Private app / data ingress. One shared outbound-only NAT; no public app or gateway IP.", 24)
    box(45, 160, 500, 150, "Browser / operator", [
        "Approved private route via admin VM",
        "Entra sign-in uses public HTTPS",
    ], "entra_roles")
    box(1170, 160, 585, 150, "Entra ID", [
        "Identity service, not a customer PE",
        "API checks token, owner and roles",
    ], "entra_roles", AMBER)
    route("identity", [[545, 235], [1170, 235]], AMBER)

    d.rect(25, 360, 1070, 630, stroke=BLUE)
    d.text(55, 380, "PoC virtual network", 28, True)
    box(55, 445, 480, 180, "Application subnet", [
        "Private Container App: API + worker",
        "Direct inference is an API operation",
        "Shared trusted runtime identity",
    ], "container_apps")
    box(55, 735, 480, 180, "Build subnet", [
        "Private ACR build pool",
        "Image delivery, not document intake",
    ], "registry", AMBER)
    box(660, 445, 400, 470, "Endpoint subnet", [
        "Container Apps ingress",
        "Application Blob",
        "AI account: CU + OpenAI",
        "Search",
        "Container Registry",
        "Private DNS resolves endpoints",
    ], "network")
    box(1170, 445, 585, 470, "Azure managed services", [
        "Container Apps private HTTPS",
        "Blob Storage",
        "Content Understanding + OpenAI",
        "Search / Foundry IQ",
        "Private Container Registry",
        "Public app/data access disabled",
        "Search-owned private links to",
        "Blob and CU are separate",
    ], "foundry")
    route("ingress", [[295, 310], [295, 335], [610, 335], [610, 485], [660, 485]])
    route("runtime", [[535, 560], [660, 560]])
    route("build", [[535, 815], [660, 815]], AMBER)
    route("services", [[1060, 650], [1170, 650]])
    box(55, 1040, 660, 180, "One shared outbound-only NAT", [
        "Administration, runtime and build",
        "Separate subnet egress policies; deny other",
        "Public IP does not provide inbound access",
    ], "network", AMBER)
    box(870, 1040, 885, 180, "Private DNS + service authorization", [
        "DNS supports the approved private access path",
        "NAT is not an allowlist; Private Endpoints are not authorization",
        "Scoped managed identities enforce data-service permissions",
    ], "network")
    route("outbound", [[55, 565], [35, 565], [35, 1115], [55, 1115]], AMBER)
    route("build-outbound", [[300, 915], [300, 1040]], AMBER)
    route("dns", [[1060, 880], [1125, 880], [1125, 1040]], GRAY, True)
    d.text(45, 1250, [
        "Solid arrows summarize access; dashed = DNS; amber = identity / outbound / build support.",
        "Synthetic only. Shared process and identity can mutate case data; network boxes are not approval isolation.",
    ], 22)


def outputs():
    markers = "".join(
        f'<marker id="{key}-head" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto">'
        f'<path d="M0 0 L8 4 L0 8 Z" fill="{value["color"]}"/></marker>'
        for key, value in routes.items())
    svg = (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{d.WIDTH}" height="{d.HEIGHT}" '
        f'viewBox="0 0 {d.WIDTH} {d.HEIGHT}" role="img" aria-labelledby="title desc">'
        '<title id="title">Private document review network connectivity</title>'
        '<desc id="desc">Approved private administration access to one PoC VNet, with application, build and private endpoint subnets. '
        'Entra identity is public and separate from private application ingress. DNS is dashed. Search shared private links '
        'are service-owned. One shared outbound-only NAT supports admin, runtime and build with separate subnet policies. '
        'Direct model inference is a runtime operation, not another workload. Shared identity retains case mutation authority. Synthetic-only.</desc>'
        f'<defs>{markers}</defs><rect width="{d.WIDTH}" height="{d.HEIGHT}" fill="#FFFFFF"/>'
        + "\n".join(d.parts) + "</svg>\n"
    )
    drawing = {
        "type": "excalidraw", "version": 2, "source": "private-network offline generator",
        "elements": d.elements, "files": d.files,
        "appState": {"viewBackgroundColor": "#FFFFFF", "gridSize": None},
    }
    return {
        ROOT / "private-network.svg": svg,
        ROOT / "private-network.excalidraw": json.dumps(drawing, indent=2) + "\n",
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    build()
    generated = outputs()
    ET.fromstring(generated[ROOT / "private-network.svg"])
    assert len({e["id"] for e in d.elements}) == len(d.elements)
    assert all(e["width"] > 0 and e["height"] > 0 for e in d.elements if e["type"] in ("text", "image"))
    assert all(e["strokeColor"] == "#000000" for e in d.elements if e["type"] == "text")
    assert all(e["backgroundColor"] == "transparent" for e in d.elements if e["type"] == "rectangle")
    for path, content in generated.items():
        if args.check:
            assert path.read_text() == content, f"Stale output: {path.name}"
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
    print(f"{'Checked' if args.check else 'Generated'} network SVG / Excalidraw; icons + geometry validated.")

#!/usr/bin/env python3
"""Build the separate offline network view and Remotion's self-contained scene."""

import argparse
import importlib.util
import json
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("architecture", ROOT / "generate-private-document-review.py")
d = importlib.util.module_from_spec(spec)
spec.loader.exec_module(d)
d.WIDTH, d.HEIGHT = 1800, 2060
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
    d.text(45, 24, "Private network connectivity | Document review PoC", 38, True)
    d.text(45, 82, "One owned VNet • selected region • private app / data ingress • no peering or deployed AKS", 25)
    box(65, 145, 510, 150, "Authorized private browser", [
        "Caseworker / Reviewer • synthetic evidence",
        "Tailnet route + exact-name split DNS",
    ])
    box(650, 145, 405, 150, "Public outbound only", [
        "Tailnet + scoped platform paths",
        "No unsolicited inbound via NAT",
    ], color=AMBER)
    box(1140, 145, 590, 150, "Entra ID / global control plane", [
        "Public identity HTTPS; not a customer PE",
        "App validates token, role, case + owner",
    ], "entra_roles", AMBER)
    route("identity", [[575, 165], [610, 165], [610, 125], [1450, 125], [1450, 145]], AMBER)

    d.rect(25, 330, 1020, 1270, stroke=BLUE)
    d.icon("network", 55, 343, 40)
    d.text(110, 343, "PoC VNet • 10.20.0.0/16", 28, True)
    box(65, 400, 510, 180, "Private admin • 10.20.3.0/27", [
        "Tailscale router VM • no NIC public IP",
        "dnsmasq on tailscale0 -> Azure DNS",
        "Synthetic admin only; NOT FIPS-certified",
    ], "network")
    route("browser", [[575, 270], [590, 270], [590, 390], [550, 390], [550, 400]])
    route("client-dns", [[100, 295], [100, 400]], GRAY, True)
    d.text(65, 310, "DNS", 20)
    d.text(610, 365, "Admin NAT", 21)

    box(65, 630, 510, 230, "ACA runtime • 10.20.1.0/24", [
        "Internal Managed Environment; public Disabled",
        "HTTPS via actual environment Private Endpoint",
        "Peer traffic encrypted • app managed identity",
        "PDF intake / human review / case questions",
    ], "container_apps")
    box(65, 960, 510, 230, "BYO agent • 10.20.0.0/24", [
        "Foundry private outbound network injection",
        "Dedicated delegated subnet • NO platform NAT",
        "Capability host + AAD project connections",
        "Private agent Blob / Cosmos / Search access",
    ], "agent")
    box(65, 1230, 510, 120, "Platform NAT • runtime + build", [
        "Scoped NSG destinations; deny other egress",
    ], color=AMBER)
    box(65, 1390, 510, 180, "ACR build • 10.20.4.0/24", [
        "VNet-connected native ACR agent pool",
        "Idle snapshot; supporting image delivery",
        "Immutable runtime image; no document path",
    ], "registry", AMBER)
    d.rect(740, 400, 270, 1160, stroke=BLUE)
    d.text(760, 420, ["Reserved PE subnet", "10.20.2.0/24"], 24, True, 240)
    d.text(1140, 350, "Azure managed services (not inside customer subnets)", 25, True)

    pe_names = [
        ("aca", 630, ["ACA environment", "managedEnvironments"]),
        ("blob", 800, ["Application Blob", "blob"]),
        ("foundry", 970, ["Foundry account", "account"]),
        ("search", 1140, ["Search service", "searchService"]),
        ("agent-data", 1310, ["Agent data PEs", "Blob + Cosmos Sql"]),
        ("acr", 1480, ["ACR registry", "registry / data"]),
    ]
    for key, y, labels in pe_names:
        d.rect(765, y, 220, 80, stroke=BLUE)
        d.cards.append((765, y, 220, 80))
        d.text(780, y + 9, labels, 17, True, 196)
        route(f"service-{key}", [[985, y + 40], [1140, y + 40]])
    box(1140, 630, 590, 135, "Container Apps private HTTPS", [
        "PE backs ingress; internal ILB alone is not a PE",
    ], "container_apps")
    box(1140, 800, 590, 135, "Application storage • keyless", [
        "Originals + state / reviewed JSON / approved PDFs",
    ], "storage", GREEN)
    box(1140, 970, 590, 135, "Foundry + Content Understanding", [
        "Private inbound: services.ai / cognitive / OpenAI",
    ], "foundry")
    box(1140, 1140, 590, 135, "AI Search • private / keyless", [
        "Scoped searchIndex knowledge; approved sources only",
    ], "search")
    box(1140, 1310, 590, 135, "Agent Blob + Cosmos DB", [
        "Native thread / agent state; not app evidence storage",
    ], "storage", GREEN)
    box(1140, 1480, 590, 135, "Private ACR • Premium", [
        "Admin Disabled / public Disabled / bypass None",
    ], "registry", AMBER)

    route("ingress", [[575, 485], [620, 485], [620, 650], [765, 650]])
    route("to-runtime", [[765, 690], [660, 690], [660, 730], [575, 730]])
    route("app-blob", [[575, 830], [620, 830], [620, 840], [765, 840]], GREEN)
    route("app-foundry", [[575, 770], [645, 770], [645, 1010], [765, 1010]])
    route("app-search", [[575, 850], [610, 850], [610, 1170], [765, 1170]])
    route("agent-search", [[575, 1050], [700, 1050], [700, 1200], [765, 1200]])
    route("agent-stores", [[575, 1100], [675, 1100], [675, 1350], [765, 1350]])
    route("build-push", [[575, 1490], [665, 1490], [665, 1520], [765, 1520]], AMBER)
    route("runtime-pull", [[575, 805], [635, 805], [635, 1540], [765, 1540]], AMBER)
    route("runtime-nat", [[65, 805], [50, 805], [50, 1270], [65, 1270]], AMBER)
    route("build-nat", [[320, 1390], [320, 1350]], AMBER)
    route("platform-outbound", [[575, 1280], [720, 1280], [720, 310], [845, 310], [845, 295]], AMBER)
    route("admin-nat", [[575, 440], [600, 440], [600, 235], [650, 235]], AMBER)
    route("shared-blob", [[1730, 1180], [1760, 1180], [1760, 850], [1730, 850]], GREEN)
    route("shared-content", [[1730, 1220], [1780, 1220], [1780, 1020], [1730, 1020]], GREEN)
    d.text(1110, 1640, [
        "Search-owned shared private links (right-hand green routes)",
        "Blob -> app storage; foundry_account +",
        "cognitiveservices_account -> Content Understanding.",
        "These are NOT PEs in the customer endpoint subnet.",
    ], 23, max_width=650)
    d.rect(25, 1640, 1020, 175, stroke=GRAY)
    d.text(65, 1654, "Private DNS • links to this VNet; not a document route", 25, True)
    d.text(65, 1700, [
        "Exact app/service names + exact private-link aliases -> router -> 168.63.129.16",
        "Zones: Blob / Search / Cosmos / ACR / cognitive / OpenAI / services.ai",
        "ACA: environment defaultDomain wildcard -> PE; privatelink.<region>.azurecontainerapps.io",
    ], 21, max_width=940)
    route("azure-dns", [[65, 520], [35, 520], [35, 1745], [65, 1745]], GRAY, True)
    route("dns-pe", [[1025, 1640], [1025, 470], [1010, 470]], GRAY, True)
    d.rect(25, 1850, 1750, 122, stroke=BLUE)
    d.text(55, 1865, "Read the flow | solid = HTTPS / transport • dashed = DNS • amber = supporting outbound", 25, True)
    d.text(55, 1908, [
        "1 Private ingress -> 2 PDF + extraction -> 3 reviewed publication / private indexing",
        "4 Scoped retrieval + agent response -> 5 separate private image delivery / controlled outbound",
    ], 24)
    d.text(40, 1990, [
        "Synthetic PoC • FIPS attestations deferred / NOT certified • NSG service tags are NOT firewall / FQDN allowlisting.",
        "Blocking Prompt Shields + managed agent task scope live in Foundry; not zero injection risk or proof of end-to-end readiness.",
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
        '<desc id="desc">One PoC VNet with separate admin, runtime, agent, build and reserved private endpoint subnets. '
        'Entra identity is public and separate from private application ingress. DNS is dashed. Search shared private links '
        'are service-owned. Two outbound-only NAT paths, no runtime/build NAT on the agent subnet. Synthetic, not certified.</desc>'
        f'<defs>{markers}</defs><rect width="{d.WIDTH}" height="{d.HEIGHT}" fill="#FFFFFF"/>'
        + "\n".join(d.parts) + "</svg>\n"
    )
    drawing = {
        "type": "excalidraw", "version": 2, "source": "private-network offline generator",
        "elements": d.elements, "files": d.files,
        "appState": {"viewBackgroundColor": "#FFFFFF", "gridSize": None},
    }
    scene = {"width": d.WIDTH, "height": d.HEIGHT, "svg": svg, "routes": routes}
    return {
        ROOT / "private-network.svg": svg,
        ROOT / "private-network.excalidraw": json.dumps(drawing, indent=2) + "\n",
        ROOT / "network-animation/src/scene.json": json.dumps(scene, indent=2) + "\n",
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
    print(f"{'Checked' if args.check else 'Generated'} network SVG / Excalidraw / Remotion scene; icons + geometry validated.")

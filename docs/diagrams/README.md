# Private document review architecture

The existing canonical [SVG](private-document-review.svg) and
[editable Excalidraw](private-document-review.excalidraw) describe the current
Container Apps solution. They are linked from the repository README and scenario
guide. Three marked flow directions separate intake/review, publication/indexing
and server-authorized case questions. The disconnected inherited Fabric sample
is deliberately outside the app's retrieval path.

`generate-private-document-review.py` is the offline editable layout/content
source. It emits both artifacts with embedded, unchanged official Microsoft SVG
icons. See [icon provenance and terms](icons/NOTICE.md) and the hashed
[source manifest](icons/manifest.json). No network or cloud access is involved.

On the authoritative macOS authoring host, using the existing Python/Pillow
installation and system Helvetica:

```sh
python3 docs/diagrams/generate-private-document-review.py
python3 docs/diagrams/generate-private-document-review.py --check
```

The check verifies deterministic output, unique element IDs, nonzero editable
text/image dimensions, icon hashes, text extents and orthogonal connectors that
do not cross service cards. Inspect the SVG at full size after content/layout
changes; structural checks do not replace visual review. Use the approved
[Microsoft Excalidraw instance](https://aka.ms/excalidraw) only if interactive
editing is needed; these artifacts do not require uploading private content.

The diagram is **not** a deployment-status dashboard, end-to-end readiness proof
or FIPS certification. FIPS attestations are deferred for this synthetic PoC.
Native scope instructions and model Prompt Shields are real architecture
boundaries, not proof of zero injection risk: Responses indirect-detector
coverage has not been independently established. Temporary runtime incidents,
agent versions, physical resource IDs and customer identity details are
intentionally excluded. US processing, preview service behavior and acceptance
remain independent verification gates.

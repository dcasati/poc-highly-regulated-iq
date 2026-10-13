# Architecture illustrations

- [Document review architecture](private-document-review.svg): two workflow lanes for intake and owner confirmation, then approved evidence retrieval and answer suggestions.
- [Private network connectivity](private-network.svg): private access, application/build/endpoint subnets, grouped managed services, DNS and one shared outbound-only NAT.

![Private network connectivity.](private-network.svg)

These static diagrams summarize the current architecture: direct private Azure OpenAI inference, without managed-agent stores or an agent subnet. They are not deployment-status reports. Service boxes represent managed services, not services hosted inside the endpoint subnet. Arrows summarize workflow or access, not every request; dashed paths show DNS. Search-owned private links to Blob and Content Understanding are separate from customer-subnet endpoints.

One shared NAT gateway serves administration, runtime and build subnets, each with its own egress policy. Direct inference is an operation of the application, not a separate workload. Owner self-review is gated by API checks within one trusted process and identity; private networking and storage containers do not isolate approval authority. Model output remains an untrusted suggestion even when its citation IDs are valid.

App/data ingress uses Private Endpoints only. An approved controlled outbound NAT public IP does not create public ingress; NAT alone is not a destination allowlist. Entra sign-in remains identity HTTPS.

CIDRs, DNS forwarding chains, Private Link group names and detailed service handoffs are intentionally omitted. The source contract is [`infra/bicep/`](../../infra/bicep/README.md); follow [getting started](../getting-started.md) for deployment details and [the scenario](../highly-regulated-scenario.md) for application controls. Illustration labels do not override those contracts.

Icon attribution and usage terms remain in [the notice](icons/NOTICE.md).

## Offline generation

Use Python 3 with Pillow. Text extents are measured with system Helvetica on macOS or Liberation Sans on Linux; missing fonts produce an explicit error rather than unchecked layout. The devcontainer includes `python3-pil` and `fonts-liberation`. SVG viewers use the corresponding Helvetica/Arial-compatible sans-serif font.

```bash
python3 docs/diagrams/generate-private-document-review.py
python3 docs/diagrams/generate-private-network.py
python3 docs/diagrams/generate-private-document-review.py --check
python3 docs/diagrams/generate-private-network.py --check
```

Each generator updates its SVG and Excalidraw source together. `--check` checks geometry, icon integrity and exact generated output without writing files. Font metrics can differ between hosts; regenerate and inspect both diagrams on the selected authoring host before checking and committing them.

# Architecture illustrations

- [Document review architecture](private-document-review.svg): intake, human confirmation, approved evidence indexing and case-authorized answers.
- [Private network connectivity](private-network.svg): subnet, Private Endpoint, DNS and separate outbound paths.

![Private network connectivity.](private-network.svg)

These static diagrams are the canonical current architecture: direct private Azure OpenAI inference, without managed-agent stores or an agent subnet. They are not deployment-status reports. Service boxes represent managed services, not services hosted inside the endpoint subnet. Solid paths show requests; dashed paths show DNS.

The retained `network-animation/` scene and older GIF are historical managed-agent illustrations, not the current contract. Do not use them for deployment guidance; no large animation rerender is part of this reduction. The offline generators update the static SVG/Excalidraw outputs only.

App/data ingress uses Private Endpoints only. An approved controlled outbound NAT public IP does not create public ingress; NAT alone is not a destination allowlist. Entra sign-in remains identity HTTPS. The disconnected Fabric sample is outside the application.

Illustrative addresses are not deployment inputs. The current source contract is [`infra/bicep/`](../../infra/bicep/README.md); follow [getting started](../getting-started.md) for approval and service handoffs. Existing illustration labels do not override that contract.

Icon attribution and usage terms remain in [the notice](icons/NOTICE.md).

export const FPS = 12;
export const WIDTH = 1200;
export const HEIGHT = 1374;
export const seconds = (value) => Math.round(value * FPS);

// Each leg travels, then holds. A negative direction follows a response back.
export const BEATS = [
  {
    start: 0, duration: 4,
    title: "1 · Private browser ingress",
    detail: "Exact-name DNS through the tailnet router; HTTPS reaches the ACA environment PE, then the runtime.",
    packet: "Private HTTPS",
    legs: [["browser", 1], ["ingress", 1], ["to-runtime", 1]],
  },
  {
    start: 4, duration: 4,
    title: "2 · Original PDF + private extraction",
    detail: "App managed identity retains the original in app Blob and calls the private Content Understanding analyzer.",
    packet: "PDF / analyzer request",
    legs: [["app-blob", 1], ["service-blob", 1], ["app-foundry", 1], ["service-foundry", 1]],
  },
  {
    start: 8, duration: 4,
    title: "3 · Human-reviewed publication",
    detail: "Only reviewed JSON / approved PDF copies are published; Search indexes through its own shared private links.",
    packet: "Reviewed publication / index",
    legs: [["app-blob", 1], ["service-blob", 1], ["shared-blob", 1], ["shared-content", 1]],
  },
  {
    start: 12, duration: 4,
    title: "4 · Scoped private retrieval",
    detail: "The server authorizes case + owner, queries Search, and checks evidence references before agent context.",
    packet: "Case-scoped query / references",
    legs: [["app-search", 1], ["service-search", 1], ["service-search", -1], ["app-search", -1]],
  },
  {
    start: 16, duration: 4,
    title: "4 · Foundry-native agent security",
    detail: "Tools-disabled managed prompt agent: task scope + Blocking Prompt Shields. Coverage is not zero-risk proof.",
    packet: "Scoped prompt / agent answer",
    legs: [["app-foundry", 1], ["service-foundry", 1], ["service-foundry", -1], ["app-foundry", -1]],
  },
  {
    start: 20, duration: 4,
    title: "4 · Private response to the browser",
    detail: "The application returns the case-scoped answer over the same private ingress; no public app endpoint.",
    packet: "Case-scoped answer",
    legs: [["to-runtime", -1], ["ingress", -1], ["browser", -1]],
  },
  {
    start: 24, duration: 4,
    title: "Foundation · BYO agent connections",
    detail: "Separate native agent/thread stores and Search connections use private outbound injection. No runtime/build NAT here.",
    packet: "Native private connections",
    legs: [["agent-stores", 1], ["service-agent-data", 1], ["agent-search", 1], ["service-search", 1]],
  },
  {
    start: 28, duration: 4,
    title: "5 · Private image delivery — not document processing",
    detail: "Native ACR build pool publishes an immutable image; ACA managed identity pulls from the private registry.",
    packet: "Build / digest pull",
    legs: [["build-push", 1], ["service-acr", 1], ["runtime-pull", 1], ["service-acr", 1]],
  },
  {
    start: 32, duration: 4,
    title: "5 · Separate outbound-only NAT paths",
    detail: "Admin NAT is separate. Runtime + build use scoped platform egress; NSG destinations are not an FQDN firewall.",
    packet: "Supporting outbound",
    legs: [["admin-nat", 1], ["runtime-nat", 1], ["build-nat", 1], ["platform-outbound", 1]],
  },
];
export const PAUSE_SECONDS = 3;
export const DURATION_IN_FRAMES = seconds(36 + PAUSE_SECONDS);

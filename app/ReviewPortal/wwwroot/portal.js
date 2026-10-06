"use strict";
const $ = id => document.getElementById(id);
let config, token, selected, version, poll;
let loadSequence = 0, chatSequence = 0;
const notice = (text, error = false) => {
  $("notice").textContent = text;
  $("notice").classList.toggle("error", error);
};
const safe = fn => async event => {
  event?.preventDefault();
  try { await fn(event); } catch (error) { notice(error.message, true); }
};
async function api(path, options = {}) {
  const headers = new Headers(options.headers);
  if (token) headers.set("Authorization", `Bearer ${token}`);
  if (options.body && !(options.body instanceof File)) headers.set("Content-Type", "application/json");
  const response = await fetch(path, { ...options, headers, cache: "no-store" });
  if (!response.ok) {
    if (response.status === 401) { token = null; clearInterval(poll); }
    const body = await response.json().catch(() => ({}));
    throw new Error(`${body.error || `Request failed (${response.status})`}${body.requestId ? ` Request ID: ${body.requestId}` : ""}`);
  }
  return response.status === 204 || response.headers.get("content-length") === "0" ? null : response.json();
}
const base64url = bytes => btoa(String.fromCharCode(...bytes)).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
async function signin() {
  const verifier = base64url(crypto.getRandomValues(new Uint8Array(32)));
  const state = base64url(crypto.getRandomValues(new Uint8Array(32)));
  const challenge = base64url(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier))));
  sessionStorage.setItem("review-login", JSON.stringify({ verifier, state, created: Date.now() }));
  const query = new URLSearchParams({
    client_id: config.clientId, response_type: "code", redirect_uri: location.origin + "/",
    scope: config.apiScope, state, code_challenge: challenge, code_challenge_method: "S256",
    response_mode: "query"
  });
  location.assign(`https://login.microsoftonline.com/${config.tenantId}/oauth2/v2.0/authorize?${query}`);
}
async function callback() {
  const query = new URLSearchParams(location.search);
  if (!query.has("code") && !query.has("error")) return;
  const saved = sessionStorage.getItem("review-login");
  sessionStorage.removeItem("review-login");
  const login = saved ? JSON.parse(saved) : null;
  history.replaceState(null, "", "/");
  if (!login || login.state !== query.get("state") || Date.now() - login.created > 600000)
    throw new Error("Sign-in state is invalid or expired. Sign in again.");
  if (query.has("error")) throw new Error("Organizational sign-in was denied.");
  const response = await fetch(`https://login.microsoftonline.com/${config.tenantId}/oauth2/v2.0/token`, {
    method: "POST", body: new URLSearchParams({
      client_id: config.clientId, grant_type: "authorization_code", code: query.get("code"),
      redirect_uri: location.origin + "/", code_verifier: login.verifier, scope: config.apiScope
    })
  });
  if (!response.ok) throw new Error("Token exchange failed. Check the approved SPA registration.");
  const result = await response.json();
  if (!result.access_token) throw new Error("No API access token was returned.");
  token = result.access_token;
  $("signin").textContent = "Sign in again";
  $("upload").querySelector("button").disabled = false;
  $("refresh").disabled = false;
  notice("Signed in. Upload or select an application.");
  await list();
  poll = setInterval(safe(async () => { if (selected && token) await load(selected); }), 10000);
}
async function list() {
  const cases = await api("/api/cases/");
  $("cases").replaceChildren();
  for (const item of cases) {
    const li = document.createElement("li"), button = document.createElement("button");
    button.textContent = `${item.id.slice(0, 8)} · ${item.status}`;
    button.addEventListener("click", safe(() => load(item.id)));
    li.append(button); $("cases").append(li);
  }
}
async function load(id) {
  const sequence = ++loadSequence;
  const snapshot = await api(`/api/cases/${id}`);
  if (sequence !== loadSequence) return;
  const previous = selected;
  selected = id;
  $("state").textContent = `Case ${id} · ${snapshot.case.status}${snapshot.case.failureCode ? ` · ${snapshot.case.failureCode}` : ""}`;
  $("original").disabled = false;
  $("retry").hidden = snapshot.case.status !== "Failed";
  $("chat").querySelector("button").disabled = snapshot.case.status !== "Approved";
  if (previous !== id) { ++chatSequence; $("answer").textContent = ""; $("references").replaceChildren(); }
  // Preserve an in-progress human review when the stored case hasn't changed.
  if (version === snapshot.version && previous === id) return;
  version = snapshot.version;
  $("fields").replaceChildren();
  for (const field of snapshot.case.fields || []) {
    const row = document.createElement("tr");
    row.classList.toggle("attention", field.confidence == null || field.confidence < config.confidenceThreshold || !field.value.trim());
    const name = document.createElement("td"); name.textContent = field.name;
    const value = document.createElement("td"), input = document.createElement("textarea");
    input.value = field.value; input.maxLength = 4000; input.dataset.field = field.name;
    input.setAttribute("aria-label", `${field.name} value`);
    input.disabled = snapshot.case.status !== "NeedsReview";
    value.append(input);
    const evidence = document.createElement("td");
    evidence.textContent = field.confidence == null ? "Unknown confidence" : `${Math.round(field.confidence * 100)}%`;
    const source = document.createElement("small"); source.textContent = field.source || "No source position returned.";
    evidence.append(source);
    const confirm = document.createElement("td"), checkbox = document.createElement("input");
    checkbox.type = "checkbox"; checkbox.required = true; checkbox.checked = field.reviewed;
    checkbox.setAttribute("aria-label", `Confirm ${field.name}`);
    checkbox.disabled = snapshot.case.status !== "NeedsReview"; confirm.append(checkbox);
    row.append(name, value, evidence, confirm); $("fields").append(row);
  }
  $("approve").disabled = snapshot.case.status !== "NeedsReview";
}
$("signin").addEventListener("click", safe(signin));
$("refresh").addEventListener("click", safe(list));
$("upload").addEventListener("submit", safe(async () => {
  const file = $("pdf").files[0];
  if (!file || file.size > config.maxUploadBytes) throw new Error("Choose a PDF within the displayed size limit.");
  const item = await api("/api/cases/", { method: "POST", headers: { "Content-Type": "application/pdf" }, body: file });
  $("upload").reset(); notice("Original retained securely. Extraction is queued.");
  await list(); await load(item.id);
}));
$("review").addEventListener("submit", safe(async () => {
  if (!confirm("Confirm every field against the original and publish this case for retrieval? This is not an application decision.")) return;
  const values = Object.fromEntries([...$("fields").querySelectorAll("textarea")].map(input => [input.dataset.field, input.value]));
  await api(`/api/cases/${selected}/review`, { method: "POST", body: JSON.stringify({ values, version }) });
  notice("Review recorded. Publication and indexing are asynchronous.");
  await load(selected); await list();
}));
$("retry").addEventListener("click", safe(async () => {
  if (!confirm("Retry processing? An uncertain previous submission may incur duplicate analysis charges.")) return;
  await api(`/api/cases/${selected}/retry`, { method: "POST" });
  await load(selected);
}));
$("original").addEventListener("click", safe(async () => {
  const response = await fetch(`/api/cases/${selected}/original`, { headers: { Authorization: `Bearer ${token}` } });
  if (!response.ok) throw new Error("Original download failed.");
  const url = URL.createObjectURL(await response.blob()), link = document.createElement("a");
  link.href = url; link.download = "application.pdf"; link.click();
  setTimeout(() => URL.revokeObjectURL(url), 60000);
}));
$("chat").addEventListener("submit", safe(async () => {
  const caseId = selected, sequence = ++chatSequence;
  const result = await api(`/api/cases/${caseId}/chat`, { method: "POST", body: JSON.stringify({ question: $("question").value }) });
  if (selected !== caseId || sequence !== chatSequence) return;
  $("answer").textContent = result.answer; $("references").replaceChildren();
  for (const ref of result.references) {
    const details = document.createElement("details"), summary = document.createElement("summary"), body = document.createElement("pre");
    const data = ref.sourceData || {};
    summary.textContent = `Evidence ${ref.id} · ${data.title || "source"} · pages ${data.page_from ?? "?"}-${data.page_to ?? "?"}`;
    body.textContent = data.content || "Source text not returned.";
    details.append(summary, body); $("references").append(details);
  }
}));
safe(async () => {
  config = await api("/api/config");
  $("pdf").setAttribute("aria-description", `Maximum ${Math.round(config.maxUploadBytes / 1024 / 1024)} MB`);
  await callback();
})();

"""Reconcile only the Bicep-owned CU analyzer and eight Search data-plane objects.

Run on the approved private operator host. Default is read-only comparison.
This is not an infrastructure deployment wrapper or a readiness test.
"""

import argparse
import json
import re
import subprocess
import time
from pathlib import Path
from urllib.error import HTTPError
from urllib.parse import parse_qs, urlparse
from urllib.request import HTTPRedirectHandler, Request, build_opener


class Failure(RuntimeError):
    pass


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise Failure("Redirect refused; verify private endpoint/TLS configuration.")


def endpoint(value, suffixes):
    parsed = urlparse(value)
    if (parsed.scheme != "https" or parsed.username or parsed.password
            or parsed.port not in (None, 443) or parsed.query or parsed.fragment
            or parsed.path not in ("", "/") or not parsed.hostname
            or not any(parsed.hostname.endswith("." + suffix) for suffix in suffixes)):
        raise Failure("Supply a verified commercial-Azure private service HTTPS endpoint.")
    return value.rstrip("/")


def operation_url(value, origin):
    parsed, expected = urlparse(value), urlparse(origin)
    if (parsed.scheme, parsed.netloc) != (expected.scheme, expected.netloc):
        raise Failure("Operation-Location must remain on the authenticated service origin.")
    if parsed.username or parsed.password or parsed.fragment:
        raise Failure("Untrusted operation URL refused.")
    return value


def contains(actual, desired):
    """Ignore service-added defaults, but compare every declared property."""
    if isinstance(desired, dict):
        return isinstance(actual, dict) and all(
            key in actual and contains(actual[key], value) for key, value in desired.items()
        )
    if isinstance(desired, list):
        return isinstance(actual, list) and len(actual) == len(desired) and all(
            contains(a, d) for a, d in zip(actual, desired)
        )
    return actual == desired


class Client:
    def __init__(self, audience):
        result = subprocess.run(
            ["az", "account", "get-access-token", "--resource", audience, "--output", "json"],
            capture_output=True, text=True, check=False, timeout=60,
        )
        if result.returncode:
            raise Failure("Ephemeral Entra authentication failed; no service write was attempted.")
        try:
            self._token = json.loads(result.stdout)["accessToken"]
        except (KeyError, ValueError):
            raise Failure("Azure CLI did not return an access token.") from None
        self._opener = build_opener(NoRedirect())

    def request(self, method, url, body=None, *, missing_ok=False, etag=None):
        headers = {"Authorization": "Bearer " + self._token, "Accept": "application/json"}
        if body is not None:
            headers["Content-Type"] = "application/json"
        if etag:
            headers["If-Match"] = etag
        request = Request(url, data=None if body is None else json.dumps(body).encode(),
                          headers=headers, method=method)
        try:
            with self._opener.open(request, timeout=30) as response:
                payload = response.read()
                return (json.loads(payload) if payload else {}), response.headers
        except HTTPError as error:
            status = error.code
            error.close()
            if status == 404 and missing_ok:
                return None, {}
            raise Failure(f"Native data-plane request failed with HTTP {status}; preserve assets and inspect privately.") from None


def poll(client, location, origin, *, deadline, clock=time.monotonic, sleep=time.sleep):
    location = operation_url(location, origin)
    while clock() < deadline:
        result, _ = client.request("GET", location)
        status = str(result.get("status", "")).lower()
        if status == "succeeded":
            return
        if status in ("failed", "canceled", "cancelled"):
            raise Failure("Native analyzer operation failed; preserve assets and inspect privately.")
        if status not in ("notstarted", "running", "inprogress"):
            raise Failure("Unknown native analyzer operation status; stop rather than assume success.")
        sleep(min(10, max(0, deadline - clock())))
    raise Failure("Native analyzer operation exceeded the 30-minute budget.")


def read_outputs(path):
    document = json.loads(path.read_text())
    outputs = {name: item["value"] for name, item in document.items()}
    analyzer = outputs["analyzer_request"]
    requests = outputs["search_requests"]
    owner = outputs["ownership"]
    project = owner["project_name"]
    analyzer_id = owner["analyzer_id"]
    if (not re.fullmatch(r"[a-z][a-z0-9-]{1,14}[a-z0-9]", project) or "--" in project
            or not re.fullmatch(r"[a-zA-Z0-9._]{1,64}", analyzer_id)):
        raise Failure("Unreviewed project/analyzer naming boundary.")
    if outputs["search_api_version"] != "2026-08-01-preview" or len(requests) != 8:
        raise Failure("Use the reviewed Bicep knowledge outputs and pinned API version.")
    analyzer_path = urlparse(analyzer["path"])
    if (analyzer["method"] != "PUT"
            or analyzer_path.scheme or analyzer_path.netloc or analyzer_path.fragment
            or analyzer_path.path != f"/contentunderstanding/analyzers/{analyzer_id}"
            or parse_qs(analyzer_path.query) != {"api-version": ["2025-11-01"]}
            or analyzer["body"]["processingLocation"] not in ("geography", "dataZone")):
        raise Failure("Unreviewed analyzer request or processing boundary.")
    kinds = ["indexes", "datasources", "datasources", "skillsets",
             "indexers", "indexers", "knowledgesources", "knowledgebases"]
    names = [f"{project}-evidence", f"{project}-evidence-pdf", f"{project}-evidence-fields",
             f"{project}-evidence-cu", f"{project}-evidence-pdf", f"{project}-evidence-fields",
             f"{project}-review-source", f"{project}-review"]
    for item, kind, name in zip(requests, kinds, names):
        parsed = urlparse(item["path"])
        if (item["method"] != "PUT" or parsed.query or parsed.fragment or parsed.netloc
                or parsed.scheme or parsed.path != f"/{kind}/{name}" or item["body"]["name"] != name):
            raise Failure("Requests must match Bicep-owned object names and dependency order.")
    return analyzer, requests, outputs["search_api_version"]


def reconcile(client, origin, request, *, apply, analyzer=False, replace=False,
              clock=time.monotonic):
    url = origin + request["path"]
    existing, headers = client.request("GET", url, missing_ok=True)
    if existing is not None and contains(existing, request["body"]):
        return False
    if not apply:
        raise Failure("Declared object is missing or differs; review before explicitly authorizing writes.")
    if existing is not None and request["path"].startswith("/knowledgesources/"):
        if (existing.get("kind") != request["body"].get("kind")
                or existing.get("searchIndexParameters", {}).get("searchIndexName")
                != request["body"].get("searchIndexParameters", {}).get("searchIndexName")):
            raise Failure("Source identity/kind replacement requires reviewed base-before-source rebuild; no write attempted.")
    if analyzer and existing is not None and not replace:
        raise Failure("Existing analyzer differs; replacement requires --replace-analyzer after review.")
    if analyzer and existing is not None:
        url += "&allowReplace=true"
    result, response_headers = client.request(
        "PUT", url, request["body"],
        etag=headers.get("ETag") or (existing or {}).get("@odata.etag"),
    )
    operation = response_headers.get("Operation-Location")
    if operation:
        poll(client, operation, origin, deadline=clock() + 1800, clock=clock)
    elif analyzer and str(result.get("status", "")).lower() in ("running", "notstarted", "inprogress"):
        raise Failure("Asynchronous analyzer response omitted Operation-Location.")
    readback, _ = client.request("GET", origin + request["path"])
    if not contains(readback, request["body"]):
        raise Failure("Declared data-plane properties were not confirmed by GET readback.")
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--outputs", required=True, type=Path,
                        help="Owner-only materialized properties.outputs JSON from the Bicep payload entry.")
    parser.add_argument("--content-endpoint", required=True)
    parser.add_argument("--search-endpoint", required=True)
    parser.add_argument("--approve-write", action="store_true",
                        help="Execute only separately authorized CU/Search object writes.")
    parser.add_argument("--replace-analyzer", action="store_true",
                        help="Explicitly reviewed replacement of the existing custom analyzer.")
    args = parser.parse_args()
    try:
        content = endpoint(args.content_endpoint, ["cognitiveservices.azure.com", "services.ai.azure.com"])
        search = endpoint(args.search_endpoint, ["search.windows.net"])
        analyzer, requests, version = read_outputs(args.outputs)
        changed = int(reconcile(Client("https://cognitiveservices.azure.com/"), content, analyzer,
                                apply=args.approve_write, analyzer=True, replace=args.replace_analyzer))
        client = Client("https://search.azure.com/")
        for request in requests:
            request = {**request, "path": request["path"] + "?api-version=" + version}
            changed += int(reconcile(client, search, request, apply=args.approve_write))
    except (Failure, OSError, ValueError, KeyError, subprocess.TimeoutExpired) as error:
        parser.exit(1, (str(error) if isinstance(error, Failure) else "Local/native request failed; inspect privately.") + "\n")
    print(f"Declared objects reconciled ({changed} writes). Ingestion, selected processing boundaries, authorization and runtime readiness NOT established.")


if __name__ == "__main__":
    main()

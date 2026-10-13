#!/usr/bin/env python3
"""Read-only synthetic indexing gate, NOT portal/retrieval or human-review acceptance.

Run only for an authorized synthetic case after explicit human review/publication.
Requires the ReviewPortal schema in infra/bicep/knowledge/payloads.bicep and the
publication contract in app/ReviewPortal/CaseStore.cs. Reads metadata only: it
cannot prove document contents, review provenance, retention, private Azure OpenAI
chat inference, source entailment or grounded answers. No managed agent is used.
Exit 0 means this indexing gate passed; 1 means not ready; 2 means check failed.
No retry, indexer trigger, extraction, upload, review or publication is performed.
"""

import argparse
import json
import os
from pathlib import Path
import re
import signal
import socket
import subprocess
import time
from urllib import error, parse, request
from uuid import UUID


API_VERSION = "2026-08-01-preview"
SELECT = "id,parent_id,case_id,owner_id,source_kind,page_from,page_to,title"
MAX_BODY = 2 * 1024 * 1024


class CheckError(Exception):
    """Only fixed check codes may reach stdout."""


class NoRedirect(request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise CheckError("redirect_rejected")


def guid(value):
    if not re.fullmatch(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", value):
        raise argparse.ArgumentTypeError("Expected a nonzero hyphenated UUID.")
    result = UUID(value)
    if not result.int:
        raise argparse.ArgumentTypeError("Expected a nonzero hyphenated UUID.")
    return str(result)


def name(value):
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,126}[a-z0-9]|[a-z0-9]", value):
        raise argparse.ArgumentTypeError("Expected an Azure Search name, not a URL.")
    return value


class Deadline:
    def __init__(self, seconds):
        self.end = time.monotonic() + seconds

    def remaining(self):
        remaining = self.end - time.monotonic()
        if remaining <= 0:
            raise CheckError("overall_timeout")
        return remaining


def acquire_token(args, deadline):
    env = dict(os.environ, AZURE_CONFIG_DIR=str(args.azure_config_dir))
    command = [args.azure_cli, "account", "get-access-token", "--subscription",
               args.subscription_id, "--resource", "https://search.azure.com/",
               "--output", "json", "--only-show-errors"]
    try:
        result = subprocess.run(command, env=env, capture_output=True, check=True,
                                timeout=min(args.request_timeout, deadline.remaining()))
        data = json.loads(result.stdout)
        if data.get("tenant") != args.tenant_id or data.get("subscription") != args.subscription_id:
            raise CheckError("cli_context_mismatch")
        token = data.get("accessToken")
        if not isinstance(token, str) or not token or "\r" in token or "\n" in token:
            raise CheckError("token_invalid")
        return token
    except subprocess.TimeoutExpired:
        raise CheckError("token_timeout") from None
    except (OSError, subprocess.CalledProcessError, ValueError, TypeError):
        raise CheckError("token_acquisition_failed") from None


class Search:
    def __init__(self, search_name, token, deadline, timeout):
        self.origin = f"https://{search_name}.search.windows.net"
        self.token, self.deadline, self.timeout = token, deadline, timeout
        # Do not send credentials via environment-selected proxies or redirects.
        self.opener = request.build_opener(request.ProxyHandler({}), NoRedirect())

    def get(self, path, **query):
        if not path.startswith(("/indexes/", "/indexers/")) or "?" in path or "#" in path:
            raise CheckError("request_path_rejected")
        url = self.origin + path + "?" + parse.urlencode({"api-version": API_VERSION, **query})
        parts = parse.urlsplit(url)
        if parts.scheme != "https" or parts.netloc != parse.urlsplit(self.origin).netloc:
            raise CheckError("request_host_rejected")
        req = request.Request(url, headers={"Authorization": f"Bearer {self.token}",
                                           "Accept": "application/json"}, method="GET")
        try:
            with self.opener.open(req, timeout=min(self.timeout, self.deadline.remaining())) as response:
                if response.geturl() != url:
                    raise CheckError("redirect_rejected")
                payload = response.read(MAX_BODY + 1)
                self.deadline.remaining()
                if len(payload) > MAX_BODY:
                    raise CheckError("response_too_large")
                return json.loads(payload)
        except error.HTTPError as exc:
            exc.close()
            raise CheckError("redirect_rejected" if 300 <= exc.code < 400 else "search_http_error") from None
        except (TimeoutError, socket.timeout):
            raise CheckError("request_timeout") from None
        except (error.URLError, OSError):
            raise CheckError("search_transport_error") from None
        except (ValueError, UnicodeError):
            raise CheckError("response_invalid") from None


def count(value):
    if type(value) is not int or value < 0:
        raise CheckError("count_invalid")
    return value


def schema_valid(schema):
    fields = {field["name"]: field for field in schema.get("fields", [])}
    required = {
        "id": "Edm.String", "parent_id": "Edm.String", "content": "Edm.String",
        "title": "Edm.String", "case_id": "Edm.String", "owner_id": "Edm.String",
        "source_kind": "Edm.String", "page_from": "Edm.Int32", "page_to": "Edm.Int32",
    }
    return (all(fields.get(key, {}).get("type") == kind for key, kind in required.items())
            and fields["id"].get("key") is True
            and all(fields[key].get("filterable") is True
                    for key in ("case_id", "owner_id", "source_kind"))
            and all(fields[key].get("retrievable", True) is True for key in SELECT.split(",")))


def verify(search, args):
    failures = []
    counters = {}
    if not schema_valid(search.get(f"/indexes/{args.index_name}")):
        raise CheckError("schema_mismatch")
    for role, indexer in (("pdf", args.pdf_indexer), ("fields", args.fields_indexer)):
        definition = search.get(f"/indexers/{indexer}")
        if definition.get("name") != indexer or definition.get("targetIndexName") != args.index_name:
            failures.append(f"{role}_indexer_target_mismatch")
        status = search.get(f"/indexers/{indexer}/status")
        last = status.get("lastResult") or {}
        failed = last.get("itemsFailed")
        if (status.get("status") != "running" or last.get("status") != "success"
                or not last.get("endTime") or type(failed) is not int or failed != 0
                or last.get("errors", []) != []):
            failures.append(f"{role}_indexer_not_successful")
        # Search's top-level "running" means enabled, not an active execution.
        counters[f"{role}_failed_items"] = failed if type(failed) is int and failed >= 0 else None
    counters["index_documents"] = count(search.get(f"/indexes/{args.index_name}/docs/$count"))
    path = f"/indexes/{args.index_name}/docs"
    case_filter = f"case_id eq '{args.case_id}'"
    scope = f"{case_filter} and owner_id eq '{args.owner_id}'"
    case_count = count(search.get(path, search="*", **{
        "$filter": case_filter, "$count": "true", "$top": 0, "$select": "id"})["@odata.count"])
    scoped_count = count(search.get(path, search="*", **{
        "$filter": scope, "$count": "true", "$top": 0, "$select": "id"})["@odata.count"])
    counters.update(case_documents=case_count, scoped_documents=scoped_count,
                    pdf_documents=0, reviewed_json_documents=0)
    if not counters["index_documents"] or not scoped_count:
        failures.append("empty_evidence")
    if case_count != scoped_count:
        failures.append("case_owner_contamination")
    if case_count > counters["index_documents"]:
        failures.append("evidence_changed_or_truncated")
    if scoped_count > args.max_records:
        failures.append("record_bound_exceeded")
    else:
        seen = set()
        for skip in range(0, scoped_count, 100):
            data = search.get(path, search="*", **{
                "$filter": scope, "$count": "true", "$top": min(100, scoped_count - skip),
                "$skip": skip, "$select": SELECT})
            if count(data["@odata.count"]) != scoped_count or "@odata.nextLink" in data:
                failures.append("evidence_changed_or_truncated")
            records = data.get("value")
            if not isinstance(records, list) or len(records) != min(100, scoped_count - skip):
                raise CheckError("evidence_response_invalid")
            for record in records:
                if record.get("case_id") != args.case_id or record.get("owner_id") != args.owner_id:
                    failures.append("record_scope_mismatch")
                    continue
                identity = record.get("id")
                if not isinstance(identity, str) or not identity or identity in seen:
                    failures.append("record_identity_invalid")
                    continue
                seen.add(identity)
                start, end = record.get("page_from"), record.get("page_to")
                if (record.get("source_kind") == "original"
                        and isinstance(record.get("parent_id"), str) and record["parent_id"]
                        and record.get("title") == f"{args.case_id}.pdf"
                        and type(start) is int and type(end) is int and 1 <= start <= end):
                    counters["pdf_documents"] += 1
                elif (record.get("source_kind") == "reviewedFields"
                      and identity == f"review-{args.case_id}"
                      and record.get("title") == "Human-validated extraction"
                      and type(start) is int and type(end) is int and start == end == 0):
                    counters["reviewed_json_documents"] += 1
                else:
                    failures.append("record_evidence_invalid")
    if counters["pdf_documents"] == 0:
        failures.append("pdf_evidence_missing")
    if counters["reviewed_json_documents"] != 1:
        failures.append("reviewed_json_evidence_missing_or_duplicate")
    return {"indexing_ready": not failures, "acceptance_ready": False,
            "checks": sorted(set(failures)) or ["indexing_gate_passed"], "counters": counters}


def arguments(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    for flag in ("search-name", "index-name", "pdf-indexer", "fields-indexer"):
        parser.add_argument("--" + flag, type=name, required=True)
    for flag in ("case-id", "owner-id", "subscription-id", "tenant-id"):
        parser.add_argument("--" + flag, type=guid, required=True)
    parser.add_argument("--schema", choices=["review-portal-v1"], required=True)
    parser.add_argument("--synthetic-after-human-review", action="store_true", required=True,
                        help="Operator attests authorized synthetic input and completed human review.")
    parser.add_argument("--azure-config-dir", type=Path, required=True)
    parser.add_argument("--azure-cli", default="az", help="Selected trusted Azure CLI executable.")
    parser.add_argument("--request-timeout", type=float, default=15)
    parser.add_argument("--overall-timeout", type=float, default=120)
    parser.add_argument("--max-records", type=int, default=1000)
    args = parser.parse_args(argv)
    if not args.azure_config_dir.is_absolute() or not args.azure_config_dir.is_dir():
        parser.error("Azure CLI context must be an existing absolute directory.")
    if not 1 <= args.request_timeout <= 60 or not 1 <= args.overall_timeout <= 300:
        parser.error("Request timeout must be 1..60 seconds; overall timeout 1..300 seconds.")
    if not 1 <= args.max_records <= 10000 or args.pdf_indexer == args.fields_indexer:
        parser.error("Use distinct indexers and a record bound of 1..10000.")
    return args


def alarm(_signum, _frame):
    raise CheckError("overall_timeout")


def main(argv=None):
    args = arguments(argv)
    # Unix alarm bounds even a slow streaming response, not just socket inactivity.
    if not hasattr(signal, "setitimer"):
        print(json.dumps({"indexing_ready": False, "acceptance_ready": False,
                          "checks": ["overall_timeout_guard_unavailable"]}))
        return 2
    previous = signal.signal(signal.SIGALRM, alarm)
    signal.setitimer(signal.ITIMER_REAL, args.overall_timeout)
    try:
        deadline = Deadline(args.overall_timeout)
        token = acquire_token(args, deadline)
        result = verify(Search(args.search_name, token, deadline, args.request_timeout), args)
        exit_code = 0 if result["indexing_ready"] else 1
    except CheckError as exc:
        result = {"indexing_ready": False, "acceptance_ready": False, "checks": [str(exc)]}
        exit_code = 2
    except Exception:
        result = {"indexing_ready": False, "acceptance_ready": False, "checks": ["response_invalid"]}
        exit_code = 2
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, previous)
    print(json.dumps(result, sort_keys=True))
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())

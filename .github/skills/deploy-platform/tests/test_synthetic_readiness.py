"""Offline stdlib tests; no sign-in, cloud writes or acceptance claims."""

import contextlib
import copy
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import time
from types import SimpleNamespace
import unittest
from unittest.mock import MagicMock, patch
from urllib.error import HTTPError, URLError


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/check_synthetic_readiness.py"
SPEC = importlib.util.spec_from_file_location("readiness", SCRIPT)
r = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(r)
CASE = "11111111-1111-4111-8111-111111111111"
OWNER = "22222222-2222-4222-8222-222222222222"
ARGS = SimpleNamespace(index_name="sample-evidence", pdf_indexer="sample-pdf",
                       fields_indexer="sample-fields", case_id=CASE, owner_id=OWNER,
                       max_records=1000)


def schema():
    return {"fields": [{"name": key, "type": "Edm.Int32" if key.startswith("page_") else "Edm.String",
                        "key": key == "id", "filterable": True} for key in
                       (r.SELECT + ",content").split(",")]}


def records():
    base = {"case_id": CASE, "owner_id": OWNER}
    return [dict(base, id="chunk-1", parent_id="pdf-parent", source_kind="original",
                 title=f"{CASE}.pdf", page_from=1, page_to=2),
            dict(base, id=f"review-{CASE}", source_kind="reviewedFields",
                 title="Human-validated extraction", page_from=0, page_to=0)]


class FakeSearch:
    def __init__(self):
        self.records = records()
        self.schema = schema()
        self.last = {"status": "success", "itemsFailed": 0, "errors": [],
                     "endTime": "2026-10-08T20:00:00Z"}
        self.status = "running"
        self.extra_owner = 0
        self.target = ARGS.index_name
        self.calls = []

    def get(self, path, **query):
        self.calls.append((path, query))
        if path.endswith("/status"):
            return {"status": self.status, "lastResult": copy.deepcopy(self.last)}
        if path.startswith("/indexers/"):
            return {"name": path.rsplit("/", 1)[1], "targetIndexName": self.target}
        if path.endswith("/$count"):
            return len(self.records)
        if path.endswith("/docs"):
            scoped = "owner_id" in query["$filter"]
            total = len(self.records) + (0 if scoped else self.extra_owner)
            return {"@odata.count": total, "value":
                    self.records[query.get("$skip", 0):][:query["$top"]]}
        return self.schema


class ReadinessTests(unittest.TestCase):
    def test_nonempty_two_evidence_types(self):
        fake = FakeSearch()
        result = r.verify(fake, ARGS)
        self.assertTrue(result["indexing_ready"])
        self.assertFalse(result["acceptance_ready"])
        self.assertEqual(result["counters"]["pdf_documents"], 1)
        self.assertEqual(result["counters"]["reviewed_json_documents"], 1)
        for path, query in fake.calls:
            self.assertNotIn("content", query.get("$select", ""))
            self.assertNotIn("/run", path)

    def test_empty_index_is_not_ready_even_with_successful_indexers(self):
        fake = FakeSearch()
        fake.records = []
        result = r.verify(fake, ARGS)
        self.assertFalse(result["indexing_ready"])
        self.assertIn("empty_evidence", result["checks"])

    def test_case_and_owner_contamination(self):
        for field in ("case_id", "owner_id"):
            with self.subTest(field=field):
                fake = FakeSearch()
                fake.records[0][field] = "other"
                self.assertIn("record_scope_mismatch", r.verify(fake, ARGS)["checks"])
        fake = FakeSearch()
        fake.extra_owner = 1
        self.assertIn("case_owner_contamination", r.verify(fake, ARGS)["checks"])

    def test_wrong_evidence_contract(self):
        for field, value in (("source_kind", "pdf"), ("page_from", 0),
                             ("title", "wrong.pdf"), ("parent_id", "")):
            with self.subTest(field=field):
                fake = FakeSearch()
                fake.records[0][field] = value
                self.assertIn("record_evidence_invalid", r.verify(fake, ARGS)["checks"])
        fake = FakeSearch()
        fake.records[1]["id"] = "unreviewed"
        self.assertFalse(r.verify(fake, ARGS)["indexing_ready"])

    def test_failed_partial_active_and_never_run_indexers(self):
        for status in ("transientFailure", "persistentFailure", "inProgress", "reset", None):
            fake = FakeSearch()
            fake.last["status"] = status
            self.assertIn("pdf_indexer_not_successful", r.verify(fake, ARGS)["checks"])
        for change in ({"itemsFailed": 1}, {"endTime": None}, {"itemsFailed": None},
                       {"errors": [{"message": "sensitive"}]}):
            fake = FakeSearch()
            fake.last.update(change)
            self.assertFalse(r.verify(fake, ARGS)["indexing_ready"])
        fake = FakeSearch()
        fake.status = "error"
        self.assertFalse(r.verify(fake, ARGS)["indexing_ready"])
        fake = FakeSearch()
        fake.last = {}
        self.assertFalse(r.verify(fake, ARGS)["indexing_ready"])

    def test_schema_and_target_mismatch(self):
        fake = FakeSearch()
        fake.schema["fields"][3]["filterable"] = False  # owner_id
        with self.assertRaisesRegex(r.CheckError, "schema_mismatch"):
            r.verify(fake, ARGS)
        fake = FakeSearch()
        fake.target = "other-index"
        self.assertIn("pdf_indexer_target_mismatch", r.verify(fake, ARGS)["checks"])

    def test_bound_and_duplicate_identity(self):
        fake = FakeSearch()
        args = SimpleNamespace(**vars(ARGS))
        args.max_records = 1
        self.assertIn("record_bound_exceeded", r.verify(fake, args)["checks"])
        fake.records[1]["id"] = fake.records[0]["id"]
        self.assertIn("record_identity_invalid", r.verify(fake, ARGS)["checks"])

    def test_pagination_is_bounded_and_metadata_only(self):
        fake = FakeSearch()
        pdf = fake.records[0]
        fake.records = [dict(pdf, id=f"chunk-{i}") for i in range(205)] + [fake.records[1]]
        result = r.verify(fake, ARGS)
        self.assertTrue(result["indexing_ready"])
        self.assertEqual(result["counters"]["pdf_documents"], 205)
        pages = [query for _, query in fake.calls if query.get("$top", 0)]
        self.assertEqual([q["$skip"] for q in pages], [0, 100, 200])


class TransportTests(unittest.TestCase):
    def client(self):
        client = r.Search("example-search", "SECRET_TOKEN", r.Deadline(10), 2)
        client.opener = MagicMock()
        return client

    def test_fixed_host_get_and_bounded_timeout(self):
        client = self.client()
        response = client.opener.open.return_value.__enter__.return_value
        url = client.origin + "/indexes/sample/docs/$count?api-version=" + r.API_VERSION
        response.geturl.return_value = url
        response.read.return_value = b"2"
        self.assertEqual(client.get("/indexes/sample/docs/$count"), 2)
        req = client.opener.open.call_args.args[0]
        self.assertEqual(req.full_url, url)
        self.assertEqual(req.method, "GET")
        self.assertEqual(client.opener.open.call_args.kwargs["timeout"], 2)
        response.read.assert_called_once_with(r.MAX_BODY + 1)

    def test_redirect_never_followed(self):
        with self.assertRaisesRegex(r.CheckError, "redirect_rejected"):
            r.NoRedirect().redirect_request(None, None, 302, "", {}, "https://evil.example/")
        client = self.client()
        response = client.opener.open.return_value.__enter__.return_value
        response.geturl.return_value = "https://evil.example/"
        with self.assertRaisesRegex(r.CheckError, "redirect_rejected"):
            client.get("/indexes/sample")
        response.read.assert_not_called()

    def test_timeout_and_errors_are_redacted(self):
        for exception, code in ((TimeoutError("SECRET"), "request_timeout"),
                                (URLError("SECRET"), "search_transport_error"),
                                (HTTPError("secret-url", 403, "SECRET", {}, io.BytesIO(b"SECRET")),
                                 "search_http_error")):
            client = self.client()
            client.opener.open.side_effect = exception
            with self.assertRaises(r.CheckError) as raised:
                client.get("/indexes/sample")
            self.assertEqual(str(raised.exception), code)
        client = self.client()
        client.opener.open.side_effect = HTTPError(
            "secret-url", 307, "SECRET", {"Location": "https://evil.example"},
            io.BytesIO(b"SECRET"))
        with self.assertRaisesRegex(r.CheckError, "redirect_rejected"):
            client.get("/indexes/sample")
        self.assertEqual(client.opener.open.call_count, 1)

    def test_token_in_memory_context_and_error_redaction(self):
        args = SimpleNamespace(azure_config_dir=Path("/approved/context"), azure_cli="az",
                               subscription_id=CASE, tenant_id=OWNER, request_timeout=2)
        data = {"accessToken": "SECRET", "subscription": CASE, "tenant": OWNER}
        with patch.object(r.subprocess, "run", return_value=SimpleNamespace(stdout=json.dumps(data))) as run:
            self.assertEqual(r.acquire_token(args, r.Deadline(10)), "SECRET")
            self.assertNotIn("SECRET", str(run.call_args))
            self.assertEqual(run.call_args.kwargs["env"]["AZURE_CONFIG_DIR"], "/approved/context")
        data["tenant"] = CASE
        with patch.object(r.subprocess, "run", return_value=SimpleNamespace(stdout=json.dumps(data))):
            with self.assertRaisesRegex(r.CheckError, "cli_context_mismatch"):
                r.acquire_token(args, r.Deadline(10))
        for exception in (subprocess.CalledProcessError(1, "az", stderr="SECRET"),
                          subprocess.TimeoutExpired("az", 2, output="SECRET")):
            with patch.object(r.subprocess, "run", side_effect=exception):
                with self.assertRaises(r.CheckError) as raised:
                    r.acquire_token(args, r.Deadline(10))
                self.assertNotIn("SECRET", str(raised.exception))

    def test_overall_timeout_and_oversized_response(self):
        deadline = r.Deadline(-1)
        with self.assertRaisesRegex(r.CheckError, "overall_timeout"):
            deadline.remaining()
        with self.assertRaisesRegex(r.CheckError, "overall_timeout"):
            r.alarm(None, None)
        client = self.client()
        response = client.opener.open.return_value.__enter__.return_value
        response.geturl.return_value = client.origin + "/indexes/sample?api-version=" + r.API_VERSION
        response.read.return_value = b"x" * (r.MAX_BODY + 1)
        with self.assertRaisesRegex(r.CheckError, "response_too_large"):
            client.get("/indexes/sample")

    def test_cli_failure_output_never_contains_service_exception(self):
        args = SimpleNamespace(overall_timeout=2)
        output = io.StringIO()
        with patch.object(r, "arguments", return_value=args), \
                patch.object(r, "acquire_token", side_effect=RuntimeError("SECRET_TOKEN document-content")), \
                contextlib.redirect_stdout(output):
            self.assertEqual(r.main([]), 2)
        data = json.loads(output.getvalue())
        self.assertEqual(data["checks"], ["response_invalid"])
        self.assertNotIn("SECRET", output.getvalue())

    def test_actual_overall_alarm_interrupts_blocking_work(self):
        args = SimpleNamespace(overall_timeout=0.02)
        output = io.StringIO()
        started = time.monotonic()
        with patch.object(r, "arguments", return_value=args), \
                patch.object(r, "acquire_token", side_effect=lambda *args: time.sleep(2)), \
                contextlib.redirect_stdout(output):
            self.assertEqual(r.main([]), 2)
        self.assertLess(time.monotonic() - started, 1)
        self.assertEqual(json.loads(output.getvalue())["checks"], ["overall_timeout"])

    def test_invalid_names_and_uuid_injection(self):
        for value in ("https://evil.example", "search/../../evil", "search?api-version=x"):
            with self.assertRaises(r.argparse.ArgumentTypeError):
                r.name(value)
        with self.assertRaises(r.argparse.ArgumentTypeError):
            r.guid("case' or true")


if __name__ == "__main__":
    unittest.main()

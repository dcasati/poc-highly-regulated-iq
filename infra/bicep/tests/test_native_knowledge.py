"""Mocked native knowledge reconciliation. No authentication or network calls."""

import importlib.util
import io
import json
import unittest
from pathlib import Path
from urllib.error import HTTPError
from unittest.mock import Mock

SOURCE = Path(__file__).resolve().parents[1] / "native/reconcile_knowledge.py"
SPEC = importlib.util.spec_from_file_location("reconcile_knowledge", SOURCE)
NATIVE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(NATIVE)


class NativeKnowledge(unittest.TestCase):
    def test_declared_subset_ignores_service_defaults_but_detects_drift(self):
        self.assertTrue(NATIVE.contains({"name": "owned", "default": True}, {"name": "owned"}))
        self.assertFalse(NATIVE.contains({"name": "other"}, {"name": "owned"}))
        self.assertFalse(NATIVE.contains({"fields": [{"name": "owner_id"}]}, {"fields": [{"name": "case_id"}]}))

    def test_endpoint_and_operation_origins_cannot_leak_authentication(self):
        valid = "https://owned.search.windows.net"
        self.assertEqual(NATIVE.endpoint(valid, ["search.windows.net"]), valid)
        for url in ("http://owned.search.windows.net", "https://evil.example/",
                    "https://owned.search.windows.net.evil.example",
                    "https://user:password@owned.search.windows.net",
                    "https://owned.search.windows.net:8443"):
            with self.assertRaises(NATIVE.Failure):
                NATIVE.endpoint(url, ["search.windows.net"])
        with self.assertRaises(NATIVE.Failure):
            NATIVE.operation_url("https://evil.example/operation", valid)
        with self.assertRaises(NATIVE.Failure):
            NATIVE.NoRedirect().redirect_request(None, None, 302, None, None, "https://evil.example")

    def test_check_mode_never_writes_missing_or_drifted_objects(self):
        client = Mock()
        client.request.return_value = (None, {})
        with self.assertRaises(NATIVE.Failure):
            NATIVE.reconcile(client, "https://owned.search.windows.net",
                             {"path": "/indexes/owned", "body": {"name": "owned"}}, apply=False)
        self.assertEqual([call.args[0] for call in client.request.call_args_list], ["GET"])

    def test_repeat_apply_is_read_only_when_declared_properties_match(self):
        client = Mock()
        client.request.return_value = ({"name": "owned", "serviceAdded": True}, {})
        changed = NATIVE.reconcile(client, "https://owned.search.windows.net",
                                   {"path": "/indexes/owned", "body": {"name": "owned"}}, apply=True)
        self.assertFalse(changed)
        self.assertEqual([call.args[0] for call in client.request.call_args_list], ["GET"])

    def test_existing_analyzer_replacement_requires_explicit_review(self):
        client = Mock()
        client.request.return_value = ({"description": "previous"}, {})
        with self.assertRaises(NATIVE.Failure):
            NATIVE.reconcile(client, "https://owned.cognitiveservices.azure.com",
                             {"path": "/contentunderstanding/analyzers/owned?api-version=2025-11-01",
                              "body": {"description": "new"}}, apply=True, analyzer=True)
        self.assertEqual(client.request.call_count, 1)

    def test_source_replacement_never_updates_before_reviewed_base_rebuild(self):
        client = Mock()
        client.request.return_value = ({"name": "owned", "kind": "otherKind"}, {})
        with self.assertRaises(NATIVE.Failure):
            NATIVE.reconcile(client, "https://owned.search.windows.net",
                             {"path": "/knowledgesources/owned", "body": {
                                 "name": "owned", "kind": "searchIndex",
                                 "searchIndexParameters": {"searchIndexName": "owned-evidence"},
                             }}, apply=True)
        self.assertEqual(client.request.call_count, 1)

    def test_materialized_output_ownership_and_dependency_order_are_enforced(self):
        kinds = ["indexes", "datasources", "datasources", "skillsets",
                 "indexers", "indexers", "knowledgesources", "knowledgebases"]
        names = ["review-demo-evidence", "review-demo-evidence-pdf", "review-demo-evidence-fields",
                 "review-demo-evidence-cu", "review-demo-evidence-pdf", "review-demo-evidence-fields",
                 "review-demo-review-source", "review-demo-review"]
        values = {
            "ownership": {"project_name": "review-demo", "analyzer_id": "application_review"},
            "search_api_version": "2026-08-01-preview",
            "analyzer_request": {"method": "PUT",
                                 "path": "/contentunderstanding/analyzers/application_review?api-version=2025-11-01",
                                 "body": {"processingLocation": "geography"}},
            "search_requests": [{"method": "PUT", "path": f"/{kind}/{name}", "body": {"name": name}}
                                for kind, name in zip(kinds, names)],
        }
        path = Mock()
        path.read_text.return_value = json.dumps({name: {"value": value} for name, value in values.items()})
        self.assertEqual(len(NATIVE.read_outputs(path)[1]), 8)
        values["search_requests"][0]["path"] = "/indexes/unrelated"
        values["search_requests"][0]["body"]["name"] = "unrelated"
        path.read_text.return_value = json.dumps({name: {"value": value} for name, value in values.items()})
        with self.assertRaises(NATIVE.Failure):
            NATIVE.read_outputs(path)

    def test_put_is_dependency_local_conditional_and_verified(self):
        client = Mock()
        client.request.side_effect = [
            ({"name": "owned", "description": "old"}, {"ETag": '"previous"'}),
            ({}, {}),
            ({"name": "owned", "description": "new"}, {}),
        ]
        self.assertTrue(NATIVE.reconcile(
            client, "https://owned.search.windows.net",
            {"path": "/indexes/owned", "body": {"name": "owned", "description": "new"}}, apply=True))
        self.assertEqual([call.args[0] for call in client.request.call_args_list], ["GET", "PUT", "GET"])
        self.assertEqual(client.request.call_args_list[1].kwargs["etag"], '"previous"')

    def test_poll_propagates_failure_unknown_status_and_timeout(self):
        for status in ("Failed", "Canceled", "Unexpected"):
            client = Mock()
            client.request.return_value = ({"status": status}, {})
            with self.assertRaises(NATIVE.Failure):
                NATIVE.poll(client, "https://owned.cognitiveservices.azure.com/operation",
                            "https://owned.cognitiveservices.azure.com", deadline=30,
                            clock=lambda: 0, sleep=lambda _: None)
        client = Mock()
        with self.assertRaises(NATIVE.Failure):
            NATIVE.poll(client, "https://owned.cognitiveservices.azure.com/operation",
                        "https://owned.cognitiveservices.azure.com", deadline=30,
                        clock=lambda: 30)
        client.request.assert_not_called()

    def test_native_http_errors_propagate_and_only_explicit_404_is_missing(self):
        client = NATIVE.Client.__new__(NATIVE.Client)
        client._token = "synthetic-token-never-printed"
        client._opener = Mock()
        url = "https://owned.search.windows.net/indexes/review-demo-evidence"
        for status in (401, 403, 409, 429, 500):
            body = io.BytesIO(b"synthetic-error-details-not-printed")
            client._opener.open.side_effect = HTTPError(url, status, "synthetic failure", {}, body)
            with self.assertRaises(NATIVE.Failure) as error:
                client.request("GET", url, missing_ok=True)
            self.assertIn(f"HTTP {status}", str(error.exception))
            self.assertNotIn(client._token, str(error.exception))
            self.assertTrue(body.closed)
        client._opener.open.side_effect = HTTPError(url, 404, "missing", {}, io.BytesIO())
        self.assertEqual(client.request("GET", url, missing_ok=True), (None, {}))
        with self.assertRaises(NATIVE.Failure):
            client.request("GET", url)


if __name__ == "__main__":
    unittest.main()

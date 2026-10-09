"""Isolated presentation tests; serve wwwroot on localhost:5297 before running."""
import json
import os
from pathlib import Path
from urllib.parse import urlparse

from playwright.sync_api import sync_playwright

CASE = "22222222-2222-2222-2222-222222222222"
OTHER_CASE = "33333333-3333-3333-3333-333333333333"
BASE_URL = os.environ.get("REPORT_BASE_URL", "http://127.0.0.1:5297").rstrip("/")
ANSWER = (
    "**Proposed activities:** The organization proposes **free after-school science "
    "and reading workshops** for **40 students** over a **12-week term**, delivered "
    "by **eight volunteers** providing two 90-minute sessions per week. "
    "The program states it charges **no tuition or membership fees**. (ref_id: 2; ref_id: 1)\n\n"
    "**Annual budget:** The synthetic annual budget shows **total income of $100,000** "
    "(Grant income **$90,000** + Donation income **$10,000**) and **total expenses of "
    "$100,000** (Program instruction and supplies **$78,000**; Facility costs **$12,000**; "
    "Administration **$10,000**), with a **projected surplus of $0**. (ref_id: 0)"
)
REFERENCES = [
    {"id": "0", "sourceData": {"title": CASE + ".pdf", "page_from": 2, "page_to": 3,
                             "content": "Income: $100,000. Expenses: $100,000. Surplus: $0."}},
    {"id": "1", "sourceData": {"title": CASE + ".pdf", "page_from": 1, "page_to": 2,
                             "content": "Free workshops for 40 students over a 12-week term."}},
    {"id": "2", "sourceData": {"title": "Human-validated extraction", "page_from": 0,
                             "page_to": 0, "content": "Explicitly reviewed application fields."}},
    {"id": "3", "sourceData": {"title": CASE + ".pdf", "page_from": 3, "page_to": 3,
                             "content": "The educational program is overseen by a three-person board."}},
]
SNAPSHOT = {"case": {"id": CASE, "status": "Approved", "fields": []}, "version": "fixture-1"}


def api(route):
    path = urlparse(route.request.url).path
    if path == "/api/config":
        value = {"tenantId": CASE, "clientId": CASE, "apiScope": "api://fixture/access_as_user",
                 "confidenceThreshold": 0.9, "maxUploadBytes": 20971520}
    elif path == "/api/cases/":
        value = [{"id": CASE, "status": "Approved"}]
    elif path == "/api/cases/" + CASE:
        value = SNAPSHOT
    elif path == "/api/cases/" + OTHER_CASE:
        value = {"case": {**SNAPSHOT["case"], "id": OTHER_CASE}, "version": "fixture-other"}
    elif path == "/api/cases/" + CASE + "/chat":
        value = {"answer": ANSWER, "references": REFERENCES}
    else:
        raise AssertionError(f"Unexpected fixture request: {path}")
    route.fulfill(status=200, content_type="application/json", body=json.dumps(value))


def render(page, answer, references=REFERENCES):
    page.evaluate(
        "value => ReviewReport.render(document.getElementById('answer'), "
        "document.getElementById('references'), value.answer, value.references)",
        {"answer": answer, "references": references},
    )


with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    try:
        for width, theme in [(1366, "light"), (1178, "light"), (390, "light"), (390, "dark")]:
            page = browser.new_page(viewport={"width": width, "height": 1000}, color_scheme=theme)
            errors = []
            page.on("pageerror", lambda error: errors.append(str(error)))
            page.route("**/api/**", api)
            page.goto(BASE_URL + "/", wait_until="networkidle")
            page.evaluate("async id => { token = 'synthetic-ui-fixture'; await list(); await load(id); }", CASE)
            page.get_by_label("Your question").fill("What activities and budget are proposed?")
            page.get_by_role("button", name="Ask review assistant").click()
            page.get_by_role("heading", name="Application evidence report").wait_for()
            assert page.locator(".report-body h4").all_text_contents() == ["Proposed activities", "Annual budget"]
            assert page.locator(".report-body strong").count() == 13
            assert "**" not in page.locator(".report-body").inner_text()
            assert "ref_id:" not in page.locator(".report-body").inner_text()
            assert page.locator(".report-citation").all_text_contents() == ["[3]", "[2]", "[1]"]
            for amount in ["$100,000", "$90,000", "$10,000", "$78,000", "$12,000", "$0"]:
                assert amount in page.locator(".report-body").inner_text()
            assert "0-0" not in page.locator("#references").inner_text()
            assert CASE not in " ".join(page.locator("#references summary").all_text_contents())
            assert "Reviewed field record" in page.locator("#references").inner_text()
            assert page.locator("#references details").count() == 4
            page.get_by_role("link", name="Read source 3: Reviewed application fields").click()
            assert page.locator("#report-source-3").evaluate("node => node.open")
            assert page.locator("#report-source-3 summary").evaluate("node => node === document.activeElement")
            page.locator("#report-source-1 summary").focus()
            page.locator("#report-source-1 summary").press("Enter")
            assert page.locator("#report-source-1").evaluate("node => node.open")
            assert not page.evaluate("document.documentElement.scrollWidth > innerWidth")
            assert not errors, errors
            screenshots = os.environ.get("REPORT_SCREENSHOT_DIR")
            if screenshots:
                page.locator("#assistant").screenshot(path=str(Path(screenshots) / f"report-{width}-{theme}.png"))

            render(page, "# Findings\n\n- **Reviewed** evidence [0]\n- Second item\n\n"
                   "1. Confirm values\n2. Read `original.pdf`\n\n"
                   "| Budget item | Amount |\n| --- | --- |\n| Income | $100,000 |\n| Surplus | $0 |\n\n"
                   "```text\nUnmodified **code**\n```")
            assert page.locator(".report-body h4").inner_text() == "Findings"
            assert page.locator(".report-body ul li").count() == 2
            assert page.locator(".report-body ol li").count() == 2
            assert page.locator(".report-table tbody tr").count() == 2
            assert page.locator(".report-code").inner_text() == "Unmodified **code**"
            assert not page.evaluate("document.documentElement.scrollWidth > innerWidth")

            malicious = "<img src=x onerror='window.reportInjected=true'><script>window.reportInjected=true</script>"
            hostile_sources = [{"id": "0", "sourceData": {"title": malicious, "content": malicious}}]
            render(page, "**" + malicious + "** (ref_id: 0) [open](javascript:alert(1))", hostile_sources)
            assert page.locator("#answer img,#answer script,#references img,#references script").count() == 0
            assert page.locator("#answer a[href^='javascript:']").count() == 0
            assert not page.evaluate("Boolean(window.reportInjected)")
            assert malicious in page.locator("#answer").inner_text()
            assert page.locator("#references summary strong").inner_text() == malicious

            render(page, "Unknown evidence (ref_id: 99). Known evidence (ref_id: 0).")
            assert "(ref_id: 99)" in page.locator(".report-body").inner_text()
            assert page.locator(".report-citation").count() == 1
            render(page, "Repeated IDs (ref_id: 0; ref_id: 0).")
            assert page.locator(".report-citation").count() == 1
            try:
                render(page, "Ambiguous sources", [REFERENCES[0], REFERENCES[0]])
            except Exception as error:
                assert "Evidence references are missing or ambiguous" in str(error)
            else:
                raise AssertionError("Duplicate sources were accepted")
            page.evaluate("id => load(id)", OTHER_CASE)
            assert page.locator("#answer").inner_text() == ""
            assert page.locator("#references").inner_text() == ""
            page.close()
            print(f"Report formatting, citations, inert untrusted text and responsive layout: {width}px/{theme} passed")
    finally:
        browser.close()

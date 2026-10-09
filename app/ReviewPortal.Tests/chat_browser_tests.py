"""Isolated chat interaction tests; intercept every API call with synthetic data."""
import json
import os
from pathlib import Path
from urllib.parse import urlparse

from playwright.sync_api import sync_playwright

CASE = "22222222-2222-2222-2222-222222222222"
OTHER = "33333333-3333-3333-3333-333333333333"
BASE = os.environ.get("REPORT_BASE_URL", "http://127.0.0.1:5297").rstrip("/")
REFERENCES = [{"id": "0", "sourceData": {"title": "Application PDF", "page_from": 2, "page_to": 2,
                                       "content": "Income $100,000, expenses $100,000, surplus $0."}}]

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    try:
        for width, theme in [(1366, "light"), (1178, "light"), (390, "light"), (390, "dark")]:
            page = browser.new_page(viewport={"width": width, "height": 1000}, color_scheme=theme)
            requests, errors = [], []
            state = {"status": "NeedsReview", "version": "review-1", "fail": False}

            def api(route):
                path = urlparse(route.request.url).path
                response_status = 200
                if path == "/api/config":
                    value = {"tenantId": CASE, "clientId": CASE, "apiScope": "api://fixture/access_as_user",
                             "confidenceThreshold": 0.9, "maxUploadBytes": 20971520}
                elif path == "/api/cases/":
                    value = [{"id": CASE, "status": state["status"]}, {"id": OTHER, "status": "Approved"}]
                elif path in ["/api/cases/" + CASE, "/api/cases/" + OTHER]:
                    value = {"case": {"id": path.rsplit("/", 1)[1], "status": state["status"] if path.endswith(CASE) else "Approved",
                                      "fields": [{"name": "ApplicantName", "value": "Synthetic organization",
                                                  "confidence": 0.95, "reviewed": False}]}, "version": state["version"]}
                elif path.endswith("/chat"):
                    requests.append(json.loads(route.request.post_data))
                    if state["fail"]:
                        response_status = 502
                        value = {"error": "Synthetic request failed.", "requestId": "synthetic-request-id"}
                    else:
                        value = {"answer": f"**Answer {len(requests)}:** The annual budget is **$100,000**. (ref_id: 0)",
                                 "references": REFERENCES}
                else:
                    raise AssertionError(path)
                route.fulfill(status=response_status, content_type="application/json", body=json.dumps(value))

            page.route("**/api/**", api)
            page.on("pageerror", lambda error: errors.append(str(error)))
            page.goto(BASE + "/", wait_until="networkidle")
            page.get_by_role("tab", name="Chat assistant").click()
            assert page.get_by_label("Message the application assistant").is_disabled()
            page.evaluate("async id => { token = 'synthetic-chat-fixture'; await list(); await load(id); }", CASE)
            assert page.locator("#validation").is_visible()
            assert page.locator("#assistant").is_hidden()
            page.locator("#fields textarea").fill("Explicit human correction")
            page.locator("#fields input[type=checkbox]").check()
            page.evaluate("id => load(id)", CASE)
            assert page.locator("#fields textarea").input_value() == "Explicit human correction"
            assert page.locator("#fields input[type=checkbox]").is_checked()

            state.update(status="Approved", version="approved-2")
            page.evaluate("id => load(id)", CASE)
            assert page.locator("#assistant").is_visible()
            assert page.locator("#validation").is_hidden()
            composer = page.get_by_label("Message the application assistant")
            assert composer.is_enabled()
            page.get_by_role("tab", name="Chat assistant").focus()
            page.keyboard.press("ArrowLeft")
            assert page.get_by_role("tab", name="Review fields").evaluate("node => node === document.activeElement")
            page.keyboard.press("End")
            assert page.get_by_role("tab", name="Chat assistant").evaluate("node => node === document.activeElement")
            composer.fill("What is the budget?")
            composer.evaluate("node => node.dispatchEvent(new KeyboardEvent('keydown', {key:'Enter', isComposing:true, bubbles:true, cancelable:true}))")
            assert not requests
            composer.press("Shift+Enter")
            assert composer.input_value().endswith("\n")
            composer.press("Backspace")
            composer.press("Enter")
            page.locator(".assistant-message .chat-answer").wait_for()
            assert requests[0] == {"question": "What is the budget?", "history": []}
            assert page.locator(".user-message").count() == 1
            assert page.locator(".assistant-message").count() == 1
            assert page.locator(".report-heading,.answer-report").count() == 0
            assert composer.input_value() == ""
            assert page.locator(".message-evidence").evaluate("node => !node.open")
            page.locator(".report-citation").click()
            assert page.locator(".message-evidence").evaluate("node => node.open")

            composer.fill("What does that leave as surplus?")
            composer.press("Enter")
            page.wait_for_function("document.querySelectorAll('.chat-answer').length === 2")
            assert requests[1]["history"][0] == {"role": "user", "content": "What is the budget?"}
            assert requests[1]["history"][1]["role"] == "assistant"
            assert "$100,000" in requests[1]["history"][1]["content"]
            ids = page.locator(".report-source").evaluate_all("nodes => nodes.map(node => node.id)")
            assert len(ids) == len(set(ids)) == 2
            assert page.locator(".user-message").count() == 2
            assert page.locator(".assistant-message").count() == 2
            assert not page.evaluate("document.documentElement.scrollWidth > innerWidth")
            assert page.locator("#chat-messages").evaluate("node => node.scrollHeight > node.clientHeight") or width > 700

            state["fail"] = True
            composer.fill("Show missing information")
            composer.press("Enter")
            page.locator(".reply-error").wait_for()
            assert "synthetic-request-id" in page.locator(".reply-error").inner_text()
            user_count = page.locator(".user-message").count()
            state["fail"] = False
            page.get_by_role("button", name="Try again").click()
            page.wait_for_function("document.querySelectorAll('.chat-answer').length === 3")
            assert page.locator(".user-message").count() == user_count
            assert page.locator(".reply-error").count() == 0

            page.evaluate("""() => {
              window.fixtureFetch = window.fetch;
              window.fetch = (url, options) => String(url).endsWith('/chat') ?
                new Promise((resolve, reject) => {
                  window.fixtureResolve = resolve;
                  options.signal.addEventListener('abort', () => reject(new DOMException('Stopped', 'AbortError')));
                }) : window.fixtureFetch(url, options);
            }""")
            composer.fill("A delayed question")
            composer.press("Enter")
            page.locator(".reply-progress").wait_for()
            assert page.get_by_role("button", name="Stop", exact=True).is_visible()
            composer.fill("Draft for the next question")
            composer.press("Enter")
            page.evaluate("id => load(id)", CASE)
            assert composer.input_value() == "Draft for the next question"
            assert page.locator(".reply-progress").count() == 1
            page.get_by_role("button", name="Stop", exact=True).click()
            page.get_by_text("Reply stopped.", exact=True).wait_for()
            assert page.locator(".reply-progress").count() == 0
            page.evaluate("window.fetch = window.fixtureFetch")
            page.get_by_role("button", name="New chat", exact=True).click()
            assert page.locator(".chat-message").count() == 0
            assert page.locator("#chat-empty").is_visible()
            assert composer.input_value() == ""

            page.get_by_role("button", name="Explain the budget", exact=True).click()
            page.locator(".chat-answer").wait_for()
            assert requests[-1]["history"] == []
            for index in range(7):
                composer.fill(f"Follow-up {index}")
                composer.press("Enter")
                page.wait_for_function("(count) => document.querySelectorAll('.chat-answer').length === count", arg=index + 2)
            assert len(requests[-1]["history"]) == 12
            assert sum(len(turn["content"]) for turn in requests[-1]["history"]) <= 48000

            page.evaluate("""() => {
              window.fetch = (url, options) => String(url).endsWith('/chat') ?
                new Promise(resolve => { window.fixtureResolve = resolve; }) : window.fixtureFetch(url, options);
            }""")
            composer.fill("An answer that arrives after switching applications")
            composer.press("Enter")
            page.locator(".reply-progress").wait_for()
            page.evaluate("id => load(id)", OTHER)
            page.evaluate("""() => window.fixtureResolve(new Response(JSON.stringify({
              answer: 'STALE_OTHER_CASE_ANSWER', references: []
            }), {status:200, headers:{'Content-Type':'application/json'}}))""")
            page.wait_for_function("document.getElementById('chat-send').hidden === false")
            assert "STALE_OTHER_CASE_ANSWER" not in page.locator("#chat-messages").inner_text()
            assert page.locator(".chat-message").count() == 0
            page.evaluate("window.fetch = window.fixtureFetch")
            page.evaluate("id => load(id)", CASE)
            composer.fill("A new conversation")
            composer.press("Enter")
            page.locator(".chat-answer").wait_for()
            assert requests[-1]["history"] == []

            screenshots = os.environ.get("REPORT_SCREENSHOT_DIR")
            if screenshots:
                page.locator("#assistant").screenshot(path=str(Path(screenshots) / f"chat-{width}-{theme}.png"))
            page.evaluate("id => load(id)", OTHER)
            assert page.locator(".chat-message").count() == 0
            assert page.locator("#chat-empty").is_visible()
            composer.fill("Question on another application")
            composer.press("Enter")
            page.locator(".chat-answer").wait_for()
            assert requests[-1]["history"] == []
            assert not errors, errors
            page.close()
            print(f"Chat history, retry/stop, case isolation, composer and responsive UI: {width}px/{theme} passed")
    finally:
        browser.close()

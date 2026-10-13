"use strict";
const CaseChat = (() => {
  function create({ request, authenticated, notify }) {
    const $ = id => document.getElementById(id);
    const transcript = $("chat-messages"), empty = $("chat-empty"), input = $("question");
    let caseId, status, generation = 0, serial = 0, active, turns = [];
    const element = (tag, text, className) => {
      const node = document.createElement(tag);
      if (text !== undefined) node.textContent = text;
      if (className) node.className = className;
      return node;
    };
    const ready = () => Boolean(caseId && status === "Approved" && authenticated());
    const nearBottom = () => transcript.scrollHeight - transcript.scrollTop - transcript.clientHeight < 100;
    const scroll = () => {
      transcript.scrollTop = transcript.scrollHeight;
      $("chat-latest").hidden = true;
    };
    function resize() {
      input.style.height = "auto";
      input.style.height = `${Math.max(44, Math.min(input.scrollHeight, 160))}px`;
      $("chat-count").textContent = `${input.value.length} / 4000`;
    }
    function controls() {
      input.disabled = !ready();
      $("chat-send").disabled = !ready() || Boolean(active) || !input.value.trim();
      $("chat-send").hidden = Boolean(active);
      $("chat-stop").hidden = !active;
      $("chat-new").disabled = !caseId || !authenticated();
      for (const button of empty.querySelectorAll("button")) button.disabled = !ready() || Boolean(active);
      $("chat-case").textContent = caseId ? `Application ${caseId.slice(0, 8)} - ${status === "Approved" ? "Reviewed evidence" : status}` : "Select a reviewed application to start.";
      $("chat-guidance").textContent = ready() ?
        "Ask a question or choose a starting point. Follow up naturally; every answer stays grounded in this application." :
        "Select an application and finish human validation before asking questions.";
    }
    function reset() {
      ++generation;
      active?.controller.abort(); active = null;
      turns = [];
      $("chat-help").textContent = "Enter to send. Shift+Enter for a new line.";
      transcript.replaceChildren(empty); empty.hidden = false;
      input.value = ""; resize(); controls(); scroll();
    }
    function history() {
      const recent = turns.slice(-6).flatMap(turn => [
        { role: "user", content: turn.question }, { role: "assistant", content: turn.answer }
      ]);
      while (recent.length && recent.reduce((total, turn) => total + turn.content.length, 0) > 48000)
        recent.splice(0, 2);
      if (recent.some(turn => turn.content.length > (turn.role === "user" ? 4000 : 12000))) {
        $("chat-help").textContent = "The previous answer is too long for follow-up context. Ask an explicit question.";
        return [];
      }
      return recent;
    }
    function message(role, text) {
      const wrapper = element("article", undefined, `chat-message ${role}-message`);
      wrapper.setAttribute("aria-label", role === "user" ? "Your message" : "Assistant reply");
      const avatar = element("span", role === "user" ? "Y" : "A", "message-avatar");
      avatar.setAttribute("aria-hidden", "true");
      const content = element("div", undefined, "message-main");
      content.append(element("p", role === "user" ? "You" : "Review assistant", "message-label"));
      const bubble = element("div", text, "message-bubble");
      content.append(bubble); wrapper.append(avatar, content); transcript.append(wrapper);
      return { wrapper, bubble };
    }
    async function send(question, retry) {
      question = question.trim();
      if (active) return;
      if (!ready()) { notify("Select a reviewed application and sign in before asking questions.", true); return; }
      if (!question || question.length > 4000) { notify("Enter a message of 1-4000 characters.", true); return; }
      const context = history(), currentGeneration = generation, currentCase = caseId;
      const controller = new AbortController(), flight = { controller };
      active = flight;
      empty.hidden = true;
      const user = retry?.user || message("user", question);
      const assistant = retry?.assistant || message("assistant");
      assistant.bubble.replaceChildren();
      assistant.wrapper.classList.add("message-pending");
      const progress = element("div", undefined, "reply-progress");
      progress.append(element("span", undefined, "reply-pulse"), element("span", "Preparing an evidence-based reply..."));
      assistant.bubble.append(progress);
      const prefix = `chat-${generation}-${++serial}`;
      input.value = ""; resize(); controls(); scroll(); input.focus();
      try {
        const result = await request(`/api/cases/${currentCase}/chat`, {
          method: "POST", signal: controller.signal, body: JSON.stringify({ question, history: context })
        });
        if (generation !== currentGeneration || caseId !== currentCase || controller.signal.aborted) return;
        const follow = nearBottom();
        const answer = element("div", undefined, "message-answer"), sources = element("details", undefined, "message-evidence");
        const sourceBody = element("div"), summary = element("summary",
          `${result.references.length} ${result.references.length === 1 ? "source" : "sources"}`);
        sources.append(summary, sourceBody);
        ReviewReport.render(answer, sourceBody, result.answer, result.references, { compact: true, idPrefix: prefix });
        assistant.bubble.replaceChildren(answer);
        if (result.references.length) assistant.bubble.append(sources);
        turns.push({ question, answer: result.answer });
        if (follow) scroll(); else $("chat-latest").hidden = false;
      } catch (error) {
        if (generation !== currentGeneration || caseId !== currentCase) return;
        const stopped = controller.signal.aborted;
        const warning = element("p", stopped ? "Reply stopped." : error.message, stopped ? "reply-status" : "reply-error");
        const again = element("button", "Try again", "button-secondary message-retry");
        again.type = "button";
        again.addEventListener("click", () => send(question,
          transcript.lastElementChild === assistant.wrapper ? { user, assistant } : undefined));
        assistant.bubble.replaceChildren(warning, again);
        if (!stopped) notify(error.message, true);
        if (nearBottom()) scroll();
      } finally {
        if (active === flight) {
          active = null;
          assistant.wrapper.classList.remove("message-pending");
          controls();
        }
      }
    }
    $("chat").addEventListener("submit", event => { event.preventDefault(); send(input.value); });
    input.addEventListener("input", () => { resize(); controls(); });
    input.addEventListener("keydown", event => {
      if (event.key === "Enter" && !event.shiftKey && !event.isComposing) {
        event.preventDefault();
        if (!active) send(input.value);
      }
    });
    for (const button of empty.querySelectorAll("button"))
      button.addEventListener("click", () => send(button.dataset.question));
    $("chat-stop").addEventListener("click", () => active?.controller.abort());
    $("chat-new").addEventListener("click", () => { reset(); input.focus(); });
    $("chat-latest").addEventListener("click", scroll);
    transcript.addEventListener("scroll", () => { if (nearBottom()) $("chat-latest").hidden = true; });
    controls();
    return {
      selectCase(id, state) {
        if (id !== caseId) reset();
        caseId = id; status = state; controls();
      },
      focus() { resize(); if (ready()) input.focus(); },
      refresh: controls
    };
  }
  return { create };
})();

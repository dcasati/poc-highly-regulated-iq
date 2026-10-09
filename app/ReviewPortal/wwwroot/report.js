"use strict";
const ReviewReport = (() => {
  const node = (tag, text, className) => {
    const element = document.createElement(tag);
    if (text !== undefined) element.textContent = text;
    if (className) element.className = className;
    return element;
  };
  const cells = line => line.trim().replace(/^\||\|$/g, "").split("|").map(cell => cell.trim());
  const listItem = line => line.match(/^\s*(?:([-+*])|(\d+)[.)])\s+(.+)$/);
  const heading = line => line.match(/^(#{1,6})\s+(.+?)\s*#*$/);
  const isTable = (lines, index) => {
    if (index + 1 >= lines.length || !lines[index].includes("|")) return false;
    const header = cells(lines[index]), divider = cells(lines[index + 1]);
    return header.length > 1 && header.length === divider.length &&
      divider.every(cell => /^:?-{3,}:?$/.test(cell));
  };

  function inline(parent, text, sources) {
    const tokens = /\(\s*ref_id\s*:[^()\n]+\)|\[(?:ref_id\s*:\s*)?([A-Za-z0-9_.-]+)\]|`([^`\n]+)`|\*\*([^*\n]+)\*\*|__([^_\n]+)__|\*([^*\n]+)\*|_([^_\n]+)_/gi;
    let offset = 0;
    for (const match of text.matchAll(tokens)) {
      parent.append(document.createTextNode(text.slice(offset, match.index)));
      if (match[0].startsWith("(") || match[1] !== undefined) {
        const ids = match[1] !== undefined ? [match[1]] :
          match[0].slice(1, -1).split(/[;,]/).map(id => id.replace(/^\s*ref_id\s*:\s*/i, "").trim());
        if (ids.length > 0 && ids.every(id => sources.has(id))) {
          for (const id of new Set(ids)) {
            const source = sources.get(id);
            const link = node("a", `[${source.number}]`, "report-citation");
            link.href = `#${source.element.id}`;
            link.setAttribute("aria-label", `Read source ${source.number}: ${source.title}`);
            link.addEventListener("click", event => {
              event.preventDefault();
              source.element.open = true;
              source.element.scrollIntoView({ block: "start" });
              source.element.querySelector("summary").focus({ preventScroll: true });
            });
            parent.append(link);
          }
        } else {
          parent.append(document.createTextNode(match[0]));
        }
      } else {
        const tag = match[2] !== undefined ? "code" :
          match[3] !== undefined || match[4] !== undefined ? "strong" : "em";
        parent.append(node(tag, match.slice(2).find(value => value !== undefined)));
      }
      offset = match.index + match[0].length;
    }
    parent.append(document.createTextNode(text.slice(offset)));
  }

  function body(parent, text, sources) {
    const lines = text.replace(/\r\n?/g, "\n").split("\n");
    let index = 0;
    while (index < lines.length) {
      const line = lines[index].trim();
      if (!line) { ++index; continue; }
      if (line.startsWith("```")) {
        const code = [];
        ++index;
        while (index < lines.length && !lines[index].trim().startsWith("```")) code.push(lines[index++]);
        parent.append(node("pre", code.join("\n"), "report-code"));
        if (index < lines.length) ++index;
        continue;
      }
      const title = heading(line);
      if (title) {
        const element = node(`h${Math.min(6, title[1].length + 3)}`);
        inline(element, title[2], sources);
        parent.append(element);
        ++index;
        continue;
      }
      if (isTable(lines, index)) {
        const headers = cells(lines[index]), table = node("table", undefined, "report-table");
        const head = node("thead"), row = node("tr"), content = node("tbody");
        for (const text of headers) {
          const cell = node("th");
          cell.scope = "col"; inline(cell, text, sources); row.append(cell);
        }
        head.append(row); table.append(head, content); index += 2;
        while (index < lines.length && lines[index].includes("|") && cells(lines[index]).length === headers.length) {
          const row = node("tr");
          cells(lines[index++]).forEach((text, column) => {
            const cell = node("td");
            cell.dataset.label = headers[column]; inline(cell, text, sources); row.append(cell);
          });
          content.append(row);
        }
        const scroll = node("div", undefined, "report-table-scroll");
        scroll.append(table); parent.append(scroll);
        continue;
      }
      const item = listItem(line);
      if (item) {
        const ordered = item[2] !== undefined, list = node(ordered ? "ol" : "ul");
        if (ordered && Number.isSafeInteger(Number(item[2]))) list.start = Number(item[2]);
        while (index < lines.length) {
          const next = listItem(lines[index]);
          if (!next || (next[2] !== undefined) !== ordered) break;
          const entry = node("li");
          inline(entry, next[3], sources); list.append(entry); ++index;
        }
        parent.append(list);
        continue;
      }
      const paragraph = [lines[index++]];
      while (index < lines.length && lines[index].trim() && !heading(lines[index].trim()) &&
          !listItem(lines[index]) && !isTable(lines, index) && !lines[index].trim().startsWith("```")) {
        paragraph.push(lines[index++]);
      }
      const value = paragraph.join(" "), label = value.match(/^\*\*([^*\n]{1,120}):\*\*\s*([\s\S]*)$/);
      if (label) parent.append(node("h4", label[1]));
      if (!label || label[2]) {
        const element = node("p");
        inline(element, label ? label[2] : value, sources); parent.append(element);
      }
    }
  }

  function sourceTitle(data) {
    const title = typeof data.title === "string" ? data.title : "";
    if (/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.pdf$/i.test(title))
      return "Application PDF";
    if (/^human-validated extraction$/i.test(title)) return "Reviewed application fields";
    return title || "Application evidence";
  }

  function pageLabel(data) {
    const from = Number(data.page_from), to = Number(data.page_to);
    if (typeof data.page_from !== "boolean" && Number.isSafeInteger(from) && from > 0) {
      if (typeof data.page_to !== "boolean" && Number.isSafeInteger(to) && to > from) return `Pages ${from}-${to}`;
      if (to === from || data.page_to == null) return `Page ${from}`;
    }
    return /^human-validated extraction$/i.test(data.title || "") ?
      "Reviewed field record" : "Page location not provided";
  }

  function render(answerElement, referencesElement, answer, references) {
    if (typeof answer !== "string" || !Array.isArray(references))
      throw new Error("The answer response could not be displayed. Contact the operator.");
    const sources = new Map(), evidence = document.createDocumentFragment();
    references.forEach((reference, index) => {
      const id = String(reference.id ?? "");
      if (!id || sources.has(id)) throw new Error("Evidence references are missing or ambiguous.");
      const data = reference.sourceData || {}, title = sourceTitle(data), number = index + 1;
      const details = node("details", undefined, "report-source");
      details.id = `report-source-${number}`;
      const summary = node("summary"), badge = node("span", String(number), "source-number");
      const label = node("span", undefined, "source-label");
      label.append(node("strong", title), node("span", pageLabel(data), "source-location"));
      summary.append(badge, label);
      details.append(summary, node("div", data.content || "Source text not returned.", "source-content"));
      sources.set(id, { number, title, element: details }); evidence.append(details);
    });
    const article = node("article", undefined, "answer-report"), header = node("header", undefined, "report-heading");
    const title = node("h3", "Application evidence report");
    title.id = "report-title"; article.setAttribute("aria-labelledby", title.id);
    header.append(node("p", "Reviewed evidence", "eyebrow"), title,
      node("p", `${references.length} supporting ${references.length === 1 ? "source" : "sources"}`, "report-meta"));
    const content = node("div", undefined, "report-body");
    body(content, answer, sources);
    article.append(header, content, node("p",
      "Assistant-generated summary. Verify statements against the supporting evidence; this is not an application decision.",
      "report-disclaimer"));
    answerElement.replaceChildren(article);
    referencesElement.replaceChildren(node("h3", "Supporting evidence"), evidence);
  }

  return { render };
})();

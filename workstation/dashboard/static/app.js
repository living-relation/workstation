const $ = (id) => document.getElementById(id);
const openNames = new Set();
const openItems = new Set(); // "<project>|<fp>" of expanded tracker rows, kept across the 15 s re-render
const drafts = new Map(); // "<project>|<fp>" -> half-typed answer, kept across the re-render
let canWriteActions = false; // from the snapshot: write actions are on only where local settings allow
let light = null;

function esc(value) {
  return String(value ?? "").replace(/[&<>"']/g, (ch) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  }[ch]));
}

function clip(value, limit) {
  const text = String(value ?? "").replace(/\s+/g, " ").trim();
  return text.length > limit ? `${text.slice(0, limit - 1)}…` : text;
}

async function load() {
  const response = await fetch("/api/snapshot", { cache: "no-store" });
  if (!response.ok) throw new Error(`snapshot ${response.status}`);
  render(await response.json());
}

function render(board) {
  const projects = board.projects || [];
  canWriteActions = board.canWriteActions === true;
  $("stamp").textContent = board.generatedAt ? `Updated ${board.generatedAt}` : "";
  renderNav(projects);
  renderTiles(projects);
  renderAlerts(board.alerts || []);
  renderShortcuts(board.shortcuts || []);
  renderBoard(projects);
}

const slug = (name) => "p-" + String(name).toLowerCase().replace(/[^a-z0-9]+/g, "-");
const COLORS = ["#0b61cd", "#4d7c0f", "#b45309", "#7c3aed", "#be123c", "#0f766e", "#475569", "#c2410c"];
function colorFor(name) {
  let h = 0;
  for (const ch of String(name)) h = (h * 31 + ch.charCodeAt(0)) >>> 0;
  return COLORS[h % COLORS.length];
}
function health(project) {
  if ((project.ciFailures || []).length || (project.blockers || []).length) return "bad";
  if (project.dirty || (project.warnings || []).length) return "warn";
  return "";
}

function renderNav(projects) {
  $("nav").innerHTML = projects.map((p) => {
    const n = (p.tasks || []).length;
    return `<a href="#${slug(p.name)}"><span class="dot ${health(p)}"></span><span class="nm">${esc(p.name)}</span>${n ? `<span class="cnt">${n}</span>` : ""}</a>`;
  }).join("");
}

function renderTiles(projects) {
  const sum = (f) => projects.reduce((a, p) => a + f(p), 0);
  const tiles = [
    ["Projects", projects.length, "var(--ink)"],
    ["Open PRs", sum((p) => p.openPrs || (p.prs || []).length), "var(--next)"],
    ["CI failures", sum((p) => (p.ciFailures || []).length), "var(--err)"],
    ["Open tasks", sum((p) => (p.tasks || []).length), "var(--accent)"],
    ["Blockers", sum((p) => (p.blockers || []).length), "var(--warn)"],
    ["Dirty trees", projects.filter((p) => p.dirty).length, "var(--ok)"],
  ];
  $("tiles").innerHTML = tiles.map(([l, n, c]) => `<div class="tile" style="--c:${c}"><span class="n">${n}</span><span class="l">${esc(l)}</span></div>`).join("");
}

function renderAlerts(alerts) {
  $("alerts").innerHTML = alerts.map((alert) => {
    const body = alert.url ? `<a href="${esc(alert.url)}">${esc(alert.text)}</a>` : esc(alert.text);
    return `<div class="alert ${esc(alert.level || "")}">${body}</div>`;
  }).join("");
}

function renderShortcuts(links) {
  $("shortcuts").innerHTML = links.map((link) =>
    `<button type="button" data-shortcut="${esc(link.name)}">${esc(link.name)}</button>`
  ).join("");
  for (const button of $("shortcuts").querySelectorAll("button")) {
    button.addEventListener("click", async () => {
      const response = await fetch("/api/shortcut", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name: button.dataset.shortcut }),
      });
      const payload = await response.json();
      if (!payload.ok) button.textContent = payload.error || "failed";
    });
  }
}

// Tracker items are {text, textFull, line, id?, githubUrl?}; plain strings still render (older snapshots).
function itemText(item) {
  return typeof item === "string" ? item : (item && item.text) || "";
}

function lastDone(project) {
  if (project.completed && project.completed.length) return itemText(project.completed[0]);
  if (project.merged) return `Merged #${project.merged.number} ${project.merged.title || ""}`;
  if (project.lastCommit) return project.lastCommit.subject || "";
  return "";
}

function ciChip(project) {
  const failed = (project.ciFailures || [])[0];
  if (failed && failed.url) return `<a class="chip bad" href="${esc(failed.url)}">CI failed</a>`;
  const prs = project.prs || [];
  const pending = prs.find((pr) => pr.ci === "pending" && pr.url);
  if (pending) return `<a class="chip warn" href="${esc(pending.url)}">CI pending</a>`;
  const passing = prs.find((pr) => pr.ci === "passing" && pr.url);
  if (passing) return `<a class="chip ok" href="${esc(passing.url)}">CI passing</a>`;
  return "";
}

// The dashboard never edits a repo: each action starts a Claude session in that project, which
// makes the changes and opens the PR. The card shows "Claude started" and, once it exists, the PR.
const KIND_LABEL = { answer: "record your answer", "hand-off": "do this task" };

function sessionLine(item) {
  if (!item) return "";
  const pr = item.sessionPr ? ` <a href="${esc(item.sessionPr)}" target="_blank" rel="noopener">${esc(item.sessionPr.replace(/^.*\/pull\//, "PR #"))}</a>` : "";
  if (!item.session) return pr ? `<p class="answer-done">PR:${pr}</p>` : "";
  const when = String(item.session.startedAt || "").replace("T", " ").slice(0, 16);
  return `<p class="answer-done">Claude started to ${esc(KIND_LABEL[item.session.kind] || "work on this")} (${esc(when)} UTC).${pr || " No PR yet."}</p>`;
}

// Action box: Waiting rows get Yes / No / typed answer; every row gets Hand to Claude with an optional note.
function actionBox(project, item, answerable) {
  if (!item || !item.fp) return "";
  const status = sessionLine(item);
  if (!canWriteActions) return `${status}<p class="answer-off">Actions are off on this PC.</p>`;
  const kind = answerable ? "answer" : "hand-off";
  const key = `${project}|${item.fp}`;
  const answers = answerable
    ? `<button type="button" class="pill sm" data-quick="Yes">Yes</button><button type="button" class="pill sm" data-quick="No">No</button>`
    : "";
  return `${status}<div class="answer" data-project="${esc(project)}" data-fp="${esc(item.fp)}" data-kind="${kind}">
    ${answers}
    <input type="text" class="answer-text" maxlength="500" placeholder="${answerable ? "Or type an answer" : "Note for Claude (optional)"}" value="${esc(drafts.get(key) || "")}">
    <button type="button" class="pill sm send-answer">${answerable ? "Send answer" : "Hand to Claude"}</button>
    <span class="answer-msg"></span>
  </div>`;
}

// A row with more to show is a native <details>: tap expands the full text, the GitHub link and the actions.
function listItem(project, item, answerable) {
  const text = itemText(item);
  const full = (item && item.textFull) || text;
  const url = item && item.githubUrl;
  const answer = actionBox(project, item, answerable);
  if (full === text && !url && !answer) return `<li>${esc(text)}</li>`;
  const key = `${project}|${item.fp || item.line}`;
  const more = full !== text ? `<p class="item-full">${esc(full)}</p>` : "";
  const link = url ? `<a class="pill sm" href="${esc(url)}" target="_blank" rel="noopener">Open on GitHub${item.line && url.includes("#L") ? ` (line ${esc(item.line)})` : ""}</a>` : "";
  return `<li class="item"><details data-key="${esc(key)}"${openItems.has(key) ? " open" : ""}><summary>${esc(text)}</summary>${more}${link}${answer}</details></li>`;
}

function listBlock(title, items, project, answerable) {
  if (!items || !items.length) return "";
  return `<div class="sub-h">${esc(title)}</div><ul>${items.map((item) => listItem(project, item, answerable)).join("")}</ul>`;
}

async function sendAction(box, value) {
  const text = String(value || "").replace(/\s+/g, " ").trim();
  const msg = box.querySelector(".answer-msg");
  const answer = box.dataset.kind === "answer";
  if (answer && !text) { msg.textContent = "Type an answer first."; return; }
  const what = answer ? `record your answer:\n\n"${text}"` : `do this task${text ? ` (your note: "${text}")` : ""}`;
  if (!window.confirm(`Start Claude in ${box.dataset.project} to ${what}\n\nIt follows that repo's rules and opens a PR. Nothing is merged.`)) return;
  box.querySelectorAll("button, input").forEach((el) => { el.disabled = true; });
  msg.textContent = "Starting Claude…";
  try {
    const url = answer ? "/api/item-answer" : "/api/item-hand-off";
    const result = await post(url, { project: box.dataset.project, fp: box.dataset.fp, [answer ? "answer" : "note"]: text });
    if (result.ok) {
      drafts.delete(`${box.dataset.project}|${box.dataset.fp}`);
      msg.textContent = `Claude started (${result.name}). Its PR shows here once it opens one.`;
      setTimeout(() => {  // redraw so the card shows the session line (tick skips while buttons are disabled)
        box.querySelectorAll("button, input").forEach((el) => { el.disabled = false; });
        if (document.activeElement && document.activeElement.blur) document.activeElement.blur();
        tick();
      }, 2500);
      return;
    }
    msg.textContent = result.error || "Could not start Claude.";
  } catch (error) {
    msg.textContent = `Could not start Claude: ${error.message}`;
  }
  box.querySelectorAll("button, input").forEach((el) => { el.disabled = false; });
}

function mdHtml(text) {
  const safe = esc(text || "");
  return safe
    .replace(/^### (.*)$/gm, "<h3>$1</h3>")
    .replace(/^## (.*)$/gm, "<h2>$1</h2>")
    .replace(/^# (.*)$/gm, "<h1>$1</h1>")
    .replace(/`([^`]+)`/g, "<code>$1</code>")
    .replace(/\n/g, "<br>");
}

function previewSrc(project, item) {
  const query = `project=${encodeURIComponent(project)}&rel=${encodeURIComponent(item.rel)}`;
  if (item.kind === "pdf") return `/preview?${query}`;
  if (item.kind === "image") return `/media?${query}`;
  return "";
}

function gallery(project) {
  const items = project.previews || [];
  if (!items.length) return "";
  const cards = items.map((item, index) => {
    if (item.kind === "markdown") {
      return `<button type="button" class="thumb" data-preview="${index}"><article class="md-page">${mdHtml(item.excerpt || item.title || "")}</article></button>`;
    }
    const src = previewSrc(project.name, item);
    return `<button type="button" class="thumb" data-preview="${index}"><img alt="${esc(item.title || "")}" src="${src}"></button>`;
  }).join("");
  return `<div class="sub-h">Previews</div><div class="gallery">${cards}</div>`;
}

function projectCard(project) {
  const tasks = (project.tasks || []).length;
  const blocked = (project.blockers || []).length;
  const prs = project.prs || [];
  const failing = new Set((project.ciFailures || []).map((f) => f.url));
  const done = lastDone(project);
  const open = openNames.has(project.name) ? " open" : "";
  const tree = project.git ? `<span class="chip ${project.dirty ? "warn" : "ok"}">${project.dirty ? "dirty" : "clean"}</span>` : "";
  const prLinks = prs.slice(0, 4).map((pr) => `<a class="pill sm" href="${esc(pr.url)}">#${esc(pr.number)}</a>`).join("");
  const stats = [
    `<div class="stat${tasks ? " hot" : ""}"><b>${tasks}</b><span>tasks</span></div>`,
    `<div class="stat${blocked ? " bad" : ""}"><b>${blocked}</b><span>blockers</span></div>`,
    `<div class="stat"><b>${prs.length}</b><span>open PRs</span></div>`,
  ].join("");
  const hasDetail = tasks || blocked || prs.length || (project.warnings || []).length || (project.prompts || []).length || (project.previews || []).length;
  const detail = [
    prs.length ? `<div class="sub-h">Pull requests</div>${prs.map((pr) => `<a class="pr${pr.ci === "failing" || failing.has(pr.url) ? " failing" : ""}" href="${esc(pr.url)}"><span class="num">#${esc(pr.number)}</span><span>${esc(pr.title || "")}</span>${pr.ci ? `<span class="chip">${esc(pr.ci)}</span>` : ""}</a>`).join("")}` : "",
    listBlock("Tasks", project.tasks, project.name),
    listBlock("Blockers", project.blockers, project.name),
    listBlock("Warnings", project.warnings, project.name),
    listBlock("Waiting", project.prompts, project.name, true),
    gallery(project),
  ].join("");
  return `<section class="section${open}" id="${slug(project.name)}" data-project="${esc(project.name)}">
    <div class="section-hd">
      <div class="topic-icon" style="background:${colorFor(project.name)}">${esc(String(project.name).charAt(0).toUpperCase())}</div>
      <h2>${esc(project.name)}</h2>
      <span class="sub">${project.branch ? `<span class="chip branch">${esc(project.branch)}</span>` : ""}${tree}${ciChip(project)}</span>
      <div class="hd-links">${prLinks}</div>
    </div>
    <div class="section-bd">
      <div class="stats">${stats}</div>
      ${done ? `<p class="last"><b>Last done</b>${esc(clip(done, 160))}</p>` : ""}
      ${hasDetail ? `<button type="button" class="pill sm toggle-detail">${open ? "Hide details" : "Show details"}</button>` : ""}
      <div class="detail" data-for="${esc(project.name)}">${detail}</div>
    </div>
  </section>`;
}

function renderBoard(projects) {
  $("board").innerHTML = projects.map(projectCard).join("");
  $("board").querySelectorAll(".toggle-detail").forEach((button) => {
    button.addEventListener("click", () => {
      const card = button.closest(".section");
      card.classList.toggle("open");
      const isOpen = card.classList.contains("open");
      button.textContent = isOpen ? "Hide details" : "Show details";
      if (isOpen) openNames.add(card.dataset.project);
      else openNames.delete(card.dataset.project);
    });
  });
  $("board").querySelectorAll(".answer").forEach((box) => {
    const key = `${box.dataset.project}|${box.dataset.fp}`;
    const input = box.querySelector(".answer-text");
    input.addEventListener("input", () => { if (input.value) drafts.set(key, input.value); else drafts.delete(key); });
    box.querySelectorAll("[data-quick]").forEach((button) => button.addEventListener("click", () => sendAction(box, button.dataset.quick)));
    box.querySelector(".send-answer").addEventListener("click", () => sendAction(box, input.value));
  });
  $("board").querySelectorAll("details[data-key]").forEach((row) => {
    row.addEventListener("toggle", () => {
      if (row.open) openItems.add(row.dataset.key);
      else openItems.delete(row.dataset.key);
    });
  });
  $("board").querySelectorAll("img").forEach((img) => {
    img.addEventListener("error", () => {
      const thumb = img.closest(".thumb");
      if (thumb) thumb.remove();
    });
  });
  $("board").querySelectorAll("[data-preview]").forEach((button) => {
    button.addEventListener("click", (event) => {
      event.stopPropagation();
      const projectName = button.closest(".detail").dataset.for;
      const project = projects.find((item) => item.name === projectName);
      const item = (project.previews || [])[Number(button.dataset.preview)];
      if (project && item) showPreview(project.name, item);
    });
  });
}

function showPreview(project, item) {
  light = { project, item };
  $("light-title").textContent = item.title || item.rel || "Preview";
  const body = $("light-body");
  if (item.kind === "markdown") {
    body.innerHTML = `<article class="doc">${mdHtml(item.excerpt || "")}</article>`;
    fetch(`/doc?project=${encodeURIComponent(project)}&rel=${encodeURIComponent(item.rel)}`)
      .then((response) => response.ok ? response.json() : null)
      .then((payload) => {
        if (payload && light && light.item === item) {
          body.innerHTML = `<article class="doc">${mdHtml(payload.text || "")}</article>`;
        }
      })
      .catch(() => {});
  } else {
    const src = previewSrc(project, item);
    body.innerHTML = `<img alt="${esc(item.title || "")}" src="${src}">`;
  }
  $("light").showModal();
  fetch("/api/open-file", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ project, rel: item.rel }),
  }).catch(() => {});
}

$("light-close").addEventListener("click", () => $("light").close());
$("light-open").addEventListener("click", () => {
  if (!light) return;
  fetch("/api/open-file", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ project: light.project, rel: light.item.rel }),
  }).catch(() => {});
});
$("light").addEventListener("click", (event) => {
  if (event.target === $("light")) $("light").close();
});

async function tick() {
  // Don't redraw under someone typing an answer or waiting on a send (it would wipe the box).
  const active = document.activeElement;
  if (active && active.closest && active.closest(".answer")) return;
  if (document.querySelector(".answer button:disabled")) return;
  try {
    await load();
  } catch (error) {
    $("stamp").textContent = `Refresh failed: ${error.message}`;
  }
}

$("refresh").addEventListener("click", () => { tick(); loadToggles(); });
tick();
setInterval(tick, 15000);

// ---- Toggle row: one switch per toggle (toggles.json + %LOCALAPPDATA%\Workstation\toggles.json),
// a Health button that works only while the toggle is on, and a Process check button.
async function post(url, body) {
  const response = await fetch(url, {
    method: "POST",
    // The dashboard header is the CSRF check on write actions (a cross-site form can't send it).
    headers: { "Content-Type": "application/json", "X-Workstation-Dashboard": "1" },
    body: JSON.stringify(body || {}),
  });
  return response.json();
}

function showCheck(title, text) {
  $("checkout-title").textContent = title;
  $("checkout-body").textContent = text;
  $("checkout").showModal();
}

function processText(result) {
  const lines = [];
  const node = result.node || {};
  lines.push(`Node processes: ${node.count ?? "?"} (${node.mb ?? "?"} MB), for information`);
  for (const [owner, row] of Object.entries(node.byOwner || {})) lines.push(`  ${owner}: ${row.count} (${row.mb} MB)`);
  const all = result.orphans || [];
  const jobs = all.filter((o) => o.kind === "background-job");
  const orphans = all.filter((o) => o.kind !== "background-job");
  const row = (o) => {
    lines.push(`  ${o.expected ? "ok  " : "WARN"} pid ${o.pid} ${o.label || o.name}: ${o.processes} process(es), ${o.mb} MB${o.note ? ` - ${o.note}` : ""}`);
    lines.push(`       ${o.cmd}`);
  };
  lines.push("", `Orphaned process trees (parent gone): ${orphans.length}`);
  for (const o of orphans) row(o);
  lines.push("", `Background jobs (claude -p): ${jobs.length}`);
  for (const o of jobs) row(o);
  lines.push("", `Duplicate MCP / server processes: ${(result.duplicates || []).length}`);
  for (const d of result.duplicates || []) lines.push(`  x${d.count} (${d.mb} MB) ${d.server}`);
  lines.push("", (result.problems || []).length ? `Problems:\n  ${result.problems.join("\n  ")}` : "No problems found.");
  return lines.join("\n");
}

async function loadToggles() {
  const response = await fetch("/api/toggles", { cache: "no-store" });
  if (!response.ok) return;
  renderToggles((await response.json()).toggles || []);
}

function renderToggles(rows) {
  const cells = rows.map((row) => {
    const state = row.busy ? row.busy : (row.on ? "on" : "off");
    return `<div class="toggle ${row.on ? "is-on" : ""}" title="${esc(row.detail || "")}">
      <label><input type="checkbox" data-toggle="${esc(row.id)}" ${row.on ? "checked" : ""} ${row.busy ? "disabled" : ""}>
      <span>${esc(row.name)}</span> <em>${esc(state)}</em></label>
      ${row.hasHealth ? `<button type="button" data-health="${esc(row.id)}" ${row.on && !row.busy ? "" : "disabled"}>Health</button>` : ""}
    </div>`;
  });
  cells.push(`<div class="toggle plain"><button type="button" id="proc-check">Process check</button></div>`);
  $("toggles").innerHTML = cells.join("");
  for (const box of $("toggles").querySelectorAll("input[data-toggle]")) {
    box.addEventListener("change", async () => {
      box.disabled = true;
      const result = await post("/api/toggle", { id: box.dataset.toggle, action: box.checked ? "on" : "off" });
      if (!result.ok) showCheck("Toggle failed", result.error || "failed");
      setTimeout(loadToggles, 1500);
    });
  }
  for (const button of $("toggles").querySelectorAll("button[data-health]")) {
    button.addEventListener("click", async () => {
      button.disabled = true;
      button.textContent = "Checking...";
      const result = await post("/api/toggle-health", { id: button.dataset.health });
      button.textContent = result.ok ? "Healthy" : "Problem";
      button.classList.toggle("bad", !result.ok);
      button.disabled = false;
      showCheck(`Health: ${button.dataset.health}`, result.output || result.error || "");
    });
  }
  $("proc-check").addEventListener("click", async () => {
    const button = $("proc-check");
    button.disabled = true;
    button.textContent = "Checking...";
    const result = await post("/api/process-check", {});
    button.disabled = false;
    button.textContent = (result.problems || []).length ? `Process check (${result.problems.length} problem)` : "Process check";
    showCheck("Process check", processText(result));
  });
}

$("checkout-close").addEventListener("click", () => $("checkout").close());
loadToggles();
setInterval(() => { if (!$("checkout").open) loadToggles(); }, 10000);

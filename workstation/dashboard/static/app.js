const $ = (id) => document.getElementById(id);

function esc(value) {
  return String(value ?? "").replace(/[&<>"']/g, (ch) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  }[ch]));
}

function liteView() {
  return window.matchMedia("(max-width: 800px)").matches;
}

let board = null;
let stampAt = 0;

function ageText() {
  if (!stampAt) return "";
  const seconds = Math.max(0, Math.round((Date.now() - stampAt) / 1000));
  return `Updated ${seconds}s ago`;
}

async function load() {
  const lite = liteView() ? "1" : "0";
  const response = await fetch(`/api/snapshot?lite=${lite}`, { cache: "no-store" });
  if (!response.ok) throw new Error(`snapshot ${response.status}`);
  board = await response.json();
  stampAt = Date.now();
  render();
}

function render() {
  if (!board) return;
  $("stamp").textContent = `${board.generatedAt || ""} · ${ageText()} · refreshes every 15s`;
  renderApps();
  renderAlerts();
  renderMobileCi();
  renderReply();
  if (!liteView()) {
    renderCharts();
    renderShortcuts();
    renderProjects();
    renderSessions();
  }
}

function pill(name, on, detail) {
  return `<div class="pill"><strong><span class="dot ${on ? "on" : "off"}"></span>${esc(name)}</strong><div class="muted">${esc(detail)}</div></div>`;
}

function limitText(app) {
  const usage = (board.usage || {})[app] || {};
  if (usage.reported && usage.fields && Object.keys(usage.fields).length) {
    return Object.entries(usage.fields).map(([key, value]) => `${key} ${value}`).join(", ");
  }
  if (app === "cursor" && usage.authenticated === false) return "CLI not logged in";
  if (app === "cursor" && usage.authenticated === true) return "CLI logged in, no quota published";
  return "usage limit not published";
}

function renderApps() {
  const apps = board.apps || {};
  const claude = apps.claude || {};
  const worker = apps.cursorWorker || {};
  const grok = apps.grok || {};
  const dispatch = apps.dispatch || {};
  $("apps").innerHTML = `<div class="pills">
    ${pill("Claude", !!claude.up, `remote control ${claude.up ? "up" : "down"} · ${limitText("claude")}`)}
    ${pill("Dispatch", !!dispatch.up, `${dispatch.sessions || 0} chats · ${limitText("dispatch")}`)}
    ${pill("Cursor", !!worker.up, `worker ${worker.up ? worker.status : "down"} · ${limitText("cursor")}`)}
    ${pill("Grok", !!grok.running, `${grok.signedIn ? "signed in" : "not signed in"} · ${limitText("grok")}`)}
  </div>`;
}

function renderAlerts() {
  const alerts = board.alerts || [];
  if (!alerts.length) {
    $("alerts").innerHTML = `<div class="alert">No warnings, blockers, or permission prompts.</div>`;
    return;
  }
  $("alerts").innerHTML = alerts.map((alert) => {
    const body = alert.url
      ? `<a href="${esc(alert.url)}">${esc(alert.text)}</a>`
      : esc(alert.text);
    return `<div class="alert ${esc(alert.level || "")}">${body}</div>`;
  }).join("");
}

function ciRows() {
  const rows = [];
  for (const project of board.projects || []) {
    for (const failure of project.ciFailures || []) rows.push(failure);
  }
  return rows;
}

function renderMobileCi() {
  const rows = ciRows();
  if (!rows.length) {
    $("mobile-ci").innerHTML = `<h2>CI</h2><div class="alert">No CI failures.</div>`;
    return;
  }
  $("mobile-ci").innerHTML = `<h2>CI failures</h2>${rows.map((row) =>
    `<div class="alert failure"><a href="${esc(row.url)}">${esc(row.project)} #${esc(row.number)} ${esc(row.title)}</a></div>`
  ).join("")}`;
}

function sendable() {
  const rows = [];
  const groups = board.sessions || {};
  for (const name of ["claude", "dispatch", "cursor", "grok"]) {
    for (const row of groups[name] || []) rows.push(row);
  }
  return rows;
}

function renderReply() {
  const rows = sendable();
  const options = rows.map((row) =>
    `<option value="${esc(row.app)}|${esc(row.id)}">${esc(row.app)} · ${esc(row.title)} ${row.canSend ? "" : "(cannot send)"}</option>`
  ).join("");
  $("reply").innerHTML = `<div class="reply-box">
    <h2>Reply</h2>
    <select id="reply-target">${options || `<option value="">No chats</option>`}</select>
    <p id="reply-note" class="muted"></p>
    <textarea id="reply-text" placeholder="Snippet to the selected chat"></textarea>
    <button id="reply-send" type="button">Send</button>
    <div id="reply-out" class="out"></div>
  </div>`;
  const select = $("reply-target");
  const note = () => {
    const row = selected(select.value);
    $("reply-note").textContent = row ? contextLine(row) + " " + (row.sendNote || "") : "";
  };
  select.addEventListener("change", note);
  note();
  $("reply-send").addEventListener("click", () => postSend(select.value, $("reply-text").value, $("reply-out")));
}

function selected(value) {
  const [app, id] = String(value || "").split("|");
  return sendable().find((row) => row.app === app && row.id === id);
}

function contextLine(row) {
  const ctx = row.context;
  if (!ctx || ctx.percent == null && !ctx.inputTokens) return "Context not reported.";
  if (ctx.percent != null) return `Context ${ctx.percent}% of ${ctx.window || "the window"}.`;
  return `Context ${ctx.inputTokens} tokens in.`;
}

async function postSend(value, text, output) {
  const row = selected(value);
  output.textContent = "";
  if (!row) {
    output.textContent = "Pick a chat.";
    return;
  }
  if (!row.canSend) {
    output.textContent = row.sendNote || "This chat cannot receive a snippet.";
    return;
  }
  output.textContent = "Sending through the app CLI…";
  const response = await fetch("/api/send", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ app: row.app, id: row.id, text }),
  });
  const payload = await response.json();
  if (payload.sent) output.textContent = payload.reply || "Sent.";
  else output.textContent = payload.error || "Not sent.";
}

function renderCharts() {
  const projects = board.projects || [];
  $("charts").innerHTML = `<div class="chart-grid">
    ${chart("Open PRs", projects.map((item) => [item.name, item.openPrs || 0]))}
    ${chart("CI failures", projects.map((item) => [item.name, (item.ciFailures || []).length]))}
    ${chart("Open tracker rows", projects.map((item) => [item.name, item.openTasks || 0]))}
  </div>`;
}

function chart(title, pairs) {
  const max = Math.max(1, ...pairs.map((pair) => pair[1]));
  const rows = pairs.filter((pair) => pair[1] > 0).sort((a, b) => b[1] - a[1]);
  const body = rows.length
    ? rows.map(([name, count]) => `<div class="bar"><span>${esc(name)}</span><span class="track"><span class="fill" style="width:${Math.round(count / max * 100)}%"></span></span><span>${count}</span></div>`).join("")
    : `<p class="muted">None.</p>`;
  return `<div class="card"><h3>${esc(title)}</h3>${body}</div>`;
}

function renderShortcuts() {
  const links = board.shortcuts || [];
  $("shortcuts").innerHTML = `<h2>Shortcuts</h2><div class="shortcut-row">${links.map((link) =>
    `<button type="button" data-shortcut="${esc(link.name)}">${esc(link.name)}</button>`
  ).join("") || `<span class="muted">No shortcuts.</span>`}</div>`;
  for (const button of $("shortcuts").querySelectorAll("button")) {
    button.addEventListener("click", async () => {
      const response = await fetch("/api/shortcut", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name: button.dataset.shortcut }),
      });
      const payload = await response.json();
      button.textContent = payload.ok ? `${button.dataset.shortcut} launched` : (payload.error || "failed");
    });
  }
}

function list(items, empty) {
  if (!items || !items.length) return `<p class="muted">${esc(empty)}</p>`;
  return `<ul class="clean">${items.slice(0, 5).map((item) => `<li>${esc(item)}</li>`).join("")}</ul>`;
}

function renderProjects() {
  const cards = (board.projects || []).map((project) => {
    const ci = (project.ciFailures || []).length ? "CI failed" : (project.prs || []).some((pr) => pr.ci === "passing") ? "CI passing" : "no CI";
    const commit = project.lastCommit ? `${project.lastCommit.subject} (${project.lastCommit.at || ""})` : "no commit";
    const images = (project.images || []).map((image) =>
      `<img alt="" src="/media?project=${encodeURIComponent(project.name)}&rel=${encodeURIComponent(image.rel)}">`
    ).join("");
    const prs = (project.prs || []).map((pr) =>
      `<li><a href="${esc(pr.url)}">#${esc(pr.number)} ${esc(pr.title)}</a> <span class="muted">${esc(pr.ci)}</span></li>`
    ).join("");
    return `<article class="card">
      <h3>${esc(project.name)}</h3>
      <p class="meta">${esc(project.branch || "no git")} · ${project.dirty ? "dirty" : "clean"} · ${esc(ci)}</p>
      <p><strong>Last completed</strong></p>
      <p class="meta">${esc(commit)}</p>
      ${project.merged ? `<p class="meta">Merged <a href="${esc(project.merged.url)}">#${esc(project.merged.number)} ${esc(project.merged.title)}</a></p>` : ""}
      ${list(project.completed, "No tracker history.")}
      <p><strong>Tasks</strong></p>
      ${list(project.tasks, "No open tracker rows.")}
      <p><strong>Blockers</strong></p>
      ${list(project.blockers, "None.")}
      <p><strong>Warnings</strong></p>
      ${list(project.warnings, "None.")}
      <p><strong>Waiting / permission</strong></p>
      ${list(project.prompts, "None.")}
      ${prs ? `<p><strong>Open PRs</strong></p><ul class="clean">${prs}</ul>` : ""}
      ${project.readme ? `<details><summary>Doc preview</summary><pre class="md">${esc(project.readme)}</pre></details>` : ""}
      ${images ? `<div class="shots">${images}</div>` : ""}
    </article>`;
  }).join("");
  $("projects").innerHTML = `<h2>Projects</h2><div class="project-grid">${cards}</div>`;
}

function sessionCard(row) {
  const meter = row.context && row.context.percent != null
    ? `<div class="meter" title="${esc(contextLine(row))}"><span style="width:${Math.max(0, Math.min(100, row.context.percent))}%"></span></div>`
    : `<p class="muted">${esc(contextLine(row))}</p>`;
  const web = row.webUrl ? `<a href="${esc(row.webUrl)}">Web session</a>` : "";
  return `<article class="card" data-app="${esc(row.app)}" data-id="${esc(row.id)}">
    <h3>${esc(row.app)} · ${esc(row.title)}</h3>
    <p class="meta">${esc(row.state || "")} ${esc(row.shortId || "")}</p>
    ${meter}
    <p>${esc(row.snippet || "")}</p>
    ${row.permission ? `<p class="alert permission">${esc(row.permission)}</p>` : ""}
    <p class="muted">${esc(row.sendNote || "")}</p>
    <p>${web} <button type="button" data-open="1">Open on this PC</button></p>
    ${row.canSend ? `<textarea placeholder="Snippet"></textarea><button type="button" data-send="1">Send</button><div class="out"></div>` : ""}
  </article>`;
}

function renderSessions() {
  const groups = board.sessions || {};
  const cards = ["claude", "dispatch", "cursor", "grok"].flatMap((name) => (groups[name] || []).map(sessionCard)).join("");
  $("sessions").innerHTML = `<h2>Chats</h2><div class="session-grid">${cards || `<p class="muted">No chats.</p>`}</div>`;
  for (const card of $("sessions").querySelectorAll("article")) {
    const app = card.dataset.app;
    const id = card.dataset.id;
    const open = card.querySelector("[data-open]");
    open.addEventListener("click", async () => {
      const response = await fetch("/api/open", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ app, id }),
      });
      const payload = await response.json();
      open.textContent = payload.ok ? "Opened" : (payload.error || "Could not open");
    });
    const sendButton = card.querySelector("[data-send]");
    if (sendButton) {
      sendButton.addEventListener("click", () => {
        const text = card.querySelector("textarea").value;
        postSend(`${app}|${id}`, text, card.querySelector(".out"));
      });
    }
  }
}

async function tick() {
  try {
    await load();
  } catch (error) {
    $("stamp").textContent = `Refresh failed: ${error.message}`;
  }
}

tick();
setInterval(() => { $("stamp").textContent = ageText(); }, 1000);
setInterval(tick, 15000);

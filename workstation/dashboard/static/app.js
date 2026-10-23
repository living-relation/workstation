const $ = (id) => document.getElementById(id);
const openNames = new Set();
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
  $("stamp").textContent = board.generatedAt ? `Updated ${board.generatedAt}` : "";
  renderAlerts(board.alerts || []);
  renderCharts(board.projects || []);
  renderShortcuts(board.shortcuts || []);
  renderBoard(board.projects || []);
}

function renderAlerts(alerts) {
  $("alerts").innerHTML = alerts.map((alert) => {
    const body = alert.url ? `<a href="${esc(alert.url)}">${esc(alert.text)}</a>` : esc(alert.text);
    return `<div class="alert ${esc(alert.level || "")}">${body}</div>`;
  }).join("");
}

function chart(title, pairs) {
  const rows = pairs.filter((pair) => pair[1] > 0).sort((a, b) => b[1] - a[1]);
  if (rows.length < 2) return "";
  const max = Math.max(...rows.map((pair) => pair[1]));
  const bars = rows.map(([name, count]) =>
    `<div class="bar"><span class="clip">${esc(name)}</span><span class="track"><span class="fill" style="width:${Math.round(count / max * 100)}%"></span></span><span>${count}</span></div>`
  ).join("");
  return `<div class="chart"><h2>${esc(title)}</h2>${bars}</div>`;
}

function renderCharts(projects) {
  const html = [
    chart("Open PRs", projects.map((item) => [item.name, item.openPrs || 0])),
    chart("CI failures", projects.map((item) => [item.name, (item.ciFailures || []).length])),
    chart("Open tasks", projects.map((item) => [item.name, (item.tasks || []).length])),
    chart("Blockers", projects.map((item) => [item.name, (item.blockers || []).length])),
  ].filter(Boolean).join("");
  $("charts").innerHTML = html ? `<div class="chart-row">${html}</div>` : "";
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

function lastDone(project) {
  if (project.completed && project.completed.length) return project.completed[0];
  if (project.merged) return `Merged #${project.merged.number} ${project.merged.title || ""}`;
  if (project.lastCommit) return project.lastCommit.subject || "";
  return "";
}

function ciCell(project) {
  const failed = (project.ciFailures || [])[0];
  if (failed && failed.url) return `<a class="bad" href="${esc(failed.url)}">failed</a>`;
  const prs = project.prs || [];
  const pending = prs.find((pr) => pr.ci === "pending" && pr.url);
  if (pending) return `<a class="warn" href="${esc(pending.url)}">pending</a>`;
  const passing = prs.find((pr) => pr.ci === "passing" && pr.url);
  if (passing) return `<a class="ok" href="${esc(passing.url)}">passing</a>`;
  if (prs[0] && prs[0].url) return `<a href="${esc(prs[0].url)}">no checks</a>`;
  return `<span class="muted">—</span>`;
}

function prCell(project) {
  const prs = project.prs || [];
  if (!prs.length) return `<span class="muted">0</span>`;
  return prs.slice(0, 4).map((pr) =>
    `<a href="${esc(pr.url)}">#${esc(pr.number)}</a>`
  ).join(" ");
}

function listBlock(title, items) {
  if (!items || !items.length) return "";
  return `<h3>${esc(title)}</h3><ul>${items.map((item) => `<li>${esc(item)}</li>`).join("")}</ul>`;
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
  return `<h3>Previews</h3><div class="gallery">${cards}</div>`;
}

function renderBoard(projects) {
  const head = `<div class="head"><span>Project</span><span>Branch</span><span>Tree</span><span>CI</span><span>PRs</span><span>Last completed</span><span class="num">Tasks</span><span class="num">Blocked</span></div>`;
  const body = projects.map((project) => {
    const tasks = (project.tasks || []).length;
    const blocked = (project.blockers || []).length;
    const done = lastDone(project);
    const open = openNames.has(project.name) ? " open" : "";
    const detail = [
      (project.prs || []).length ? `<div class="prs"><h3>Pull requests</h3>${(project.prs || []).map((pr) => `<a href="${esc(pr.url)}">#${esc(pr.number)} ${esc(pr.title || "")}</a>`).join("")}</div>` : "",
      listBlock("Tasks", project.tasks),
      listBlock("Blockers", project.blockers),
      listBlock("Warnings", project.warnings),
      listBlock("Waiting", project.prompts),
      gallery(project),
    ].join("");
    return `<div class="row${open}" data-project="${esc(project.name)}">
      <span class="name">${esc(project.name)}</span>
      <span class="clip branch">${esc(project.branch || "—")}</span>
      <span class="${project.dirty ? "warn" : "ok"}">${project.git ? (project.dirty ? "dirty" : "clean") : "—"}</span>
      <span>${ciCell(project)}</span>
      <span class="prs">${prCell(project)}</span>
      <span class="clip last" title="${esc(done)}">${done ? esc(clip(done, 90)) : ""}</span>
      <span class="num">${tasks || ""}</span>
      <span class="num">${blocked || ""}</span>
    </div>
    <div class="detail" data-for="${esc(project.name)}">${detail}</div>`;
  }).join("");
  $("board").innerHTML = `<div class="table">${head}${body}</div>`;
  $("board").querySelectorAll(".row").forEach((row) => {
    row.addEventListener("click", (event) => {
      if (event.target.closest("a")) return;
      row.classList.toggle("open");
      if (row.classList.contains("open")) openNames.add(row.dataset.project);
      else openNames.delete(row.dataset.project);
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
  try {
    await load();
  } catch (error) {
    $("stamp").textContent = `Refresh failed: ${error.message}`;
  }
}

tick();
setInterval(tick, 15000);

// ---- Toggle row: one switch per toggle (toggles.json + %LOCALAPPDATA%\Workstation\toggles.json),
// a Health button that works only while the toggle is on, and a Process check button.
async function post(url, body) {
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
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
  lines.push(`Node processes: ${node.count ?? "?"} (${node.mb ?? "?"} MB), limit ${node.limit ?? "?"}`);
  for (const [owner, row] of Object.entries(node.byOwner || {})) lines.push(`  ${owner}: ${row.count} (${row.mb} MB)`);
  lines.push("", `Orphaned process trees (parent gone): ${(result.orphans || []).length}`);
  for (const o of result.orphans || []) {
    lines.push(`  ${o.expected ? "ok  " : "WARN"} pid ${o.pid} ${o.label || o.name}: ${o.processes} process(es), ${o.mb} MB${o.note ? ` - ${o.note}` : ""}`);
    lines.push(`       ${o.cmd}`);
  }
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
  cells.push(`<div class="toggle"><button type="button" id="proc-check">Process check</button></div>`);
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

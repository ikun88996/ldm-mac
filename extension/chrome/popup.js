/**
 * LDM Mac 扩展弹窗：显示 App 连接状态、当前任务进度、当前页面检测到的媒体
 */

const $ = (id) => document.getElementById(id);

function msg(key, fallback) {
  try {
    return chrome.i18n.getMessage(key) || fallback;
  } catch (e) {
    return fallback;
  }
}

function fmtBytes(n) {
  n = Number(n) || 0;
  if (n <= 0) return "0 B";
  const units = ["B", "KB", "MB", "GB", "TB"];
  let v = n;
  let i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return (i === 0 ? v.toFixed(0) : v.toFixed(2)) + " " + units[i];
}

function fmtSpeed(n) {
  return fmtBytes(n) + "/s";
}

function statusLabel(s) {
  const map = {
    waiting: msg("statusWaiting", "Queued"),
    active: msg("statusActive", "Downloading"),
    paused: msg("statusPaused", "Paused"),
    complete: msg("statusComplete", "Completed"),
    error: msg("statusError", "Failed")
  };
  return map[s] || s;
}

function send(message) {
  return new Promise((resolve) => {
    chrome.runtime.sendMessage(message, (res) => {
      if (chrome.runtime.lastError) resolve(null);
      else resolve(res);
    });
  });
}

function queryActiveTab() {
  return new Promise((resolve) => {
    chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => resolve(tabs && tabs[0]));
  });
}

function renderStatus(app) {
  const el = $("status");
  const text = $("statusText");
  el.classList.remove("ok", "bad");
  if (app && app.ok) {
    el.classList.add("ok");
    text.textContent = msg("statusConnected", "Connected") + " · v" + (app.version || "?");
  } else {
    el.classList.add("bad");
    text.textContent = msg("statusDisconnected", "App not running");
  }
}

function renderTasks(result) {
  const box = $("tasks");
  box.textContent = "";
  const tasks = (result && result.tasks) || [];
  if (!tasks.length) {
    const empty = document.createElement("div");
    empty.className = "empty";
    empty.textContent = msg("noTasks", "No tasks");
    box.appendChild(empty);
    return;
  }
  for (const t of tasks.slice(0, 6)) {
    const row = document.createElement("div");
    row.className = "task";

    const head = document.createElement("div");
    head.className = "task-head";

    const name = document.createElement("span");
    name.className = "task-name";
    name.textContent = t.name || t.url;
    name.title = t.path || t.url;

    const badge = document.createElement("span");
    badge.className = "badge";
    badge.textContent = statusLabel(t.status);

    head.appendChild(name);
    head.appendChild(badge);

    const meta = document.createElement("div");
    meta.className = "task-meta";
    const left = document.createElement("span");
    left.textContent = `${fmtBytes(t.done)} / ${fmtBytes(t.total)}`;
    const right = document.createElement("span");
    right.textContent =
      (t.speed > 0 ? fmtSpeed(t.speed) + " · " : "") +
      (t.status === "complete" ? "100%" : ((t.progress || 0) * 100).toFixed(1) + "%");
    meta.appendChild(left);
    meta.appendChild(right);

    const bar = document.createElement("div");
    bar.className = "bar";
    const fill = document.createElement("i");
    fill.style.width = Math.min(100, Math.max(0, (t.progress || 0) * 100)) + "%";
    bar.appendChild(fill);

    row.appendChild(head);
    row.appendChild(meta);
    row.appendChild(bar);
    box.appendChild(row);
  }
}

function actionButtons(t) {
  const wrap = document.createElement("span");
  const add = (label, action) => {
    const b = document.createElement("button");
    b.textContent = label;
    b.addEventListener("click", async () => {
      await send({ type: "ldm-task-action", id: t.id, action });
    });
    wrap.appendChild(b);
  };
  if (t.status === "active" || t.status === "waiting") add(msg("pause", "Pause"), "pause");
  if (t.status === "paused") add(msg("resume", "Resume"), "resume");
  add(msg("remove", "Remove"), "remove");
  return wrap;
}

function renderMedia(items) {
  const box = $("media");
  box.textContent = "";
  if (!items || !items.length) {
    const empty = document.createElement("div");
    empty.className = "empty";
    empty.textContent = msg("noMedia", "No media detected");
    box.appendChild(empty);
    return;
  }
  for (const item of items.slice(0, 6)) {
    const row = document.createElement("div");
    row.className = "media-row";

    const name = document.createElement("span");
    name.className = "media-name";
    name.textContent = (item.url.split("/").pop() || item.url).slice(0, 40);
    name.title = item.url;

    const badge = document.createElement("span");
    badge.className = "badge";
    badge.textContent = item.score >= 100 ? "HLS" : item.source || "media";

    const btn = document.createElement("button");
    btn.className = "primary";
    btn.textContent = msg("download", "Download");
    btn.addEventListener("click", async () => {
      await send({ type: "ldm-add", url: item.url, kind: item.score >= 100 ? "video" : "file" });
      refresh();
    });

    row.appendChild(name);
    row.appendChild(badge);
    row.appendChild(btn);
    box.appendChild(row);
  }
}

async function refresh() {
  const app = await send({ type: "ldm-ping" });
  renderStatus(app);

  if (app && app.ok) {
    const tasks = await send({ type: "ldm-tasks" });
    renderTasks(tasks);
  } else {
    renderTasks(null);
  }

  const tab = await queryActiveTab();
  if (tab && tab.id && /^https?:/i.test(tab.url || "")) {
    const items = await new Promise((resolve) => {
      chrome.tabs.sendMessage(tab.id, { type: "ldm-list" }, (res) => {
        if (chrome.runtime.lastError) resolve(null);
        else resolve(res);
      });
    });
    renderMedia(items && items.items ? items.items : []);
  } else {
    renderMedia(null);
  }
}

$("tasksTitle").textContent = msg("tasksTitle", "Tasks");
$("mediaTitle").textContent = msg("mediaTitle", "Media on this page");
$("hint").textContent = msg("popupHint", "Right-click a link or video → “Download with LDM”");

refresh();
setInterval(refresh, 1500);

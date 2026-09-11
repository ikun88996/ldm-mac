/**
 * LDM Mac 浏览器扩展 —— 后台服务工作线程
 *
 * 职责：
 *  1. 右键菜单「用 LDM 下载」（链接 / 视频 / 页面 / 选中文本）
 *  2. 把下载请求连同 Referer、Cookie 一起发给 LDM Mac 的本机接口
 *  3. 转发内容脚本的检测结果与下载请求，并回写角标
 */

const CANDIDATE_PORTS = [47823, 47824, 47825];
const VIDEO_HOSTS = [
  "youtube.com", "youtu.be", "bilibili.com", "b23.tv", "x.com", "twitter.com",
  "tiktok.com", "douyin.com", "reddit.com", "vimeo.com", "twitch.tv",
  "instagram.com", "facebook.com", "weibo.com", "weibo.cn", "kuaishou.com",
  "v.qq.com", "youku.com", "iqiyi.com", "ixigua.com", "netflix.com"
];
const MEDIA_EXT = [
  ".mp4", ".m4v", ".mov", ".mkv", ".webm", ".flv", ".ts", ".m3u8", ".mpd",
  ".mp3", ".m4a", ".aac", ".flac", ".wav", ".ogg",
  ".zip", ".rar", ".7z", ".dmg", ".pkg", ".exe", ".iso", ".apk",
  ".gguf", ".safetensors", ".bin", ".pdf", ".epub", ".srt", ".torrent"
];

let cachedPort = null;

// ---------------------------------------------------------------- 与 App 通信

async function api(path, options = {}) {
  const ports = cachedPort
    ? [cachedPort, ...CANDIDATE_PORTS.filter((p) => p !== cachedPort)]
    : CANDIDATE_PORTS;

  for (const port of ports) {
    try {
      const res = await fetch(`http://127.0.0.1:${port}${path}`, {
        ...options,
        signal: AbortSignal.timeout(2500)
      });
      if (!res.ok) continue;
      cachedPort = port;
      return await res.json();
    } catch (e) {
      // 端口不通，试下一个
    }
  }
  cachedPort = null;
  return { ok: false, error: "app-unreachable" };
}

async function pingApp() {
  const r = await api("/ping");
  return r && r.ok ? r : null;
}

async function listTasks() {
  return api("/tasks");
}

async function collectCookies(url) {
  try {
    if (!/^https?:/i.test(url)) return null;
    const list = await chrome.cookies.getAll({ url });
    if (!list || !list.length) return null;
    return list.map((c) => `${c.name}=${c.value}`).join("; ");
  } catch (e) {
    return null;
  }
}

function guessKind(url) {
  if (!url) return "auto";
  const lower = url.toLowerCase();
  if (VIDEO_HOSTS.some((h) => lower.includes(h))) return "video";
  const path = lower.split("?")[0];
  if (MEDIA_EXT.some((ext) => path.endsWith(ext))) return "file";
  return "auto";
}

/** 发一个下载请求给 LDM Mac */
async function addDownload({ url, kind, referer, pageTitle }) {
  if (!url) return { ok: false, error: "no-url" };
  const cookies = await collectCookies(url);
  const payload = {
    url,
    kind: kind || guessKind(url),
    referer: referer || null,
    cookies,
    filename: pageTitle ? null : null
  };
  const res = await api("/add", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload)
  });
  if (res && res.ok) {
    setBadgeFlash("✓");
  }
  return res || { ok: false, error: "app-unreachable" };
}

// ---------------------------------------------------------------- 右键菜单

const MENUS = [
  { id: "ldm-link", contexts: ["link"], titleKey: "menuLink" },
  { id: "ldm-media", contexts: ["video", "audio"], titleKey: "menuMedia" },
  { id: "ldm-selection", contexts: ["selection"], titleKey: "menuSelection" },
  { id: "ldm-page", contexts: ["page"], titleKey: "menuPage" }
];

function buildMenus() {
  chrome.contextMenus.removeAll(() => {
    for (const m of MENUS) {
      chrome.contextMenus.create({
        id: m.id,
        title: chrome.i18n.getMessage(m.titleKey),
        contexts: m.contexts,
        documentUrlPatterns: ["http://*/*", "https://*/*"]
      });
    }
  });
}

chrome.runtime.onInstalled.addListener(buildMenus);
chrome.runtime.onStartup.addListener(buildMenus);

chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  let url = null;
  let kind = "auto";

  if (info.menuItemId === "ldm-link") {
    url = info.linkUrl;
    kind = guessKind(url);
  } else if (info.menuItemId === "ldm-media") {
    url = info.srcUrl;
    kind = "file";
  } else if (info.menuItemId === "ldm-selection") {
    const text = (info.selectionText || "").trim();
    if (/^https?:\/\//i.test(text)) {
      url = text;
      kind = guessKind(text);
    } else {
      return;
    }
  } else if (info.menuItemId === "ldm-page") {
    url = info.pageUrl || (tab && tab.url);
    kind = "video";
  }

  if (!url) return;
  const res = await addDownload({ url, kind, referer: tab && tab.url, pageTitle: tab && tab.title });
  notifyTab(tab, res);
});

function notifyTab(tab, res) {
  if (!tab || typeof tab.id !== "number") return;
  chrome.tabs
    .sendMessage(tab.id, {
      type: "ldm-toast",
      ok: !!(res && res.ok),
      error: res && res.error ? res.error : null
    })
    .catch(() => {});
}

// ---------------------------------------------------------------- 内容脚本消息

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (!msg || !msg.type) return;

  if (msg.type === "ldm-add") {
    addDownload({
      url: msg.url,
      kind: msg.kind,
      referer: sender.tab && sender.tab.url,
      pageTitle: sender.tab && sender.tab.title
    }).then((res) => {
      if (sender.tab) notifyTab(sender.tab, res);
      sendResponse(res);
    });
    return true;
  }

  if (msg.type === "ldm-ping") {
    pingApp().then((r) => sendResponse(r || { ok: false }));
    return true;
  }

  if (msg.type === "ldm-tasks") {
    listTasks().then(sendResponse);
    return true;
  }

  if (msg.type === "ldm-task-action") {
    if (!msg.id || !msg.action) {
      sendResponse({ ok: false, error: "bad-request" });
      return true;
    }
    api("/task", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id: msg.id, action: msg.action })
    }).then(sendResponse);
    return true;
  }

  if (msg.type === "ldm-badge") {
    const tabId = sender.tab && sender.tab.id;
    if (typeof tabId === "number") {
      const count = Number(msg.count) || 0;
      chrome.action.setBadgeText({ tabId, text: count > 0 ? String(count) : "" });
      chrome.action.setBadgeBackgroundColor({ tabId, color: "#2D6BFF" });
    }
    sendResponse({ ok: true });
    return true;
  }
});

// ---------------------------------------------------------------- 角标

function setBadgeFlash(text) {
  chrome.action.setBadgeText({ text });
  chrome.action.setBadgeBackgroundColor({ color: "#22A06B" });
  setTimeout(() => chrome.action.setBadgeText({ text: "" }), 1800);
}

// 让 popup 能直接问「App 在不在」
chrome.runtime.onConnect && chrome.runtime.onConnect.addListener(() => {});

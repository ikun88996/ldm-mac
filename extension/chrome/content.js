/**
 * LDM Mac 浏览器扩展 —— 页面嗅探脚本
 *
 * 1. 检测当前页面上的视频/音频/分片流地址（DOM + performance + 源码兜底）
 * 2. 右下角浮出按钮，点开是候选列表，逐项发给 LDM Mac（也可以整页交给 yt-dlp）
 * 3. 顶帧才显示界面，iframe 只上报（避免同一页面出现多个按钮）
 */

(function () {
  "use strict";

  const MEDIA_EXT = [
    ".mp4", ".m4v", ".mov", ".mkv", ".webm", ".flv", ".ts", ".m3u8", ".mpd",
    ".mp3", ".m4a", ".aac", ".flac", ".wav", ".ogg"
  ];
  const STREAM_EXT = [".m3u8", ".mpd"];
  const MIN_SCORE = 1;

  // ------------------------------------------------------------ 纯函数（可单测）

  function stripQuery(url) {
    return String(url || "").split("?")[0].split("#")[0];
  }

  function isMediaUrl(url) {
    if (!/^https?:/i.test(url || "")) return false;
    const path = stripQuery(url).toLowerCase();
    return MEDIA_EXT.some((ext) => path.endsWith(ext));
  }

  function isStreamUrl(url) {
    if (!/^https?:/i.test(url || "")) return false;
    const path = stripQuery(url).toLowerCase();
    return STREAM_EXT.some((ext) => path.endsWith(ext));
  }

  /** 打分：分片流 > 视频容器 > 音频；同分靠后出现的优先（通常更接近真实播放源） */
  function scoreUrl(url) {
    const path = stripQuery(url).toLowerCase();
    if (path.endsWith(".m3u8") || path.endsWith(".mpd")) return 100;
    if (path.endsWith(".mp4") || path.endsWith(".m4v") || path.endsWith(".mkv") || path.endsWith(".webm")) return 80;
    if (path.endsWith(".flv")) return 70;
    if (path.endsWith(".ts")) return 40;
    if (path.endsWith(".mp3") || path.endsWith(".m4a") || path.endsWith(".aac") || path.endsWith(".flac")) return 30;
    return 10;
  }

  /** 去重并排序，返回 [{url, score, source}] */
  function rank(candidates) {
    const seen = new Map();
    for (const c of candidates) {
      if (!c || !isMediaUrl(c.url)) continue;
      const key = stripQuery(c.url);
      const prev = seen.get(key);
      if (!prev || prev.score < scoreUrl(c.url)) {
        seen.set(key, { url: c.url, score: scoreUrl(c.url), source: c.source || "unknown" });
      }
    }
    return Array.from(seen.values()).sort((a, b) => b.score - a.score);
  }

  const LDMCore = { rank, scoreUrl, isMediaUrl, isStreamUrl, stripQuery };

  // Node 单测环境：只导出纯函数，不碰 DOM
  if (typeof module !== "undefined" && module.exports) {
    module.exports = LDMCore;
    return;
  }

  // ------------------------------------------------------------ 采集

  function fromDom() {
    const out = [];
    document.querySelectorAll("video, audio, source").forEach((el) => {
      const src = el.currentSrc || el.src;
      if (src) out.push({ url: src, source: "dom" });
      if (el.tagName === "VIDEO" || el.tagName === "AUDIO") {
        el.querySelectorAll("source").forEach((s) => {
          if (s.src) out.push({ url: s.src, source: "dom-source" });
        });
      }
    });
    return out;
  }

  function fromPerformance() {
    const out = [];
    try {
      performance.getEntriesByType("resource").forEach((e) => {
        if (e && e.name && isMediaUrl(e.name)) out.push({ url: e.name, source: "network" });
      });
    } catch (err) {
      /* 某些页面禁用了 performance */
    }
    return out;
  }

  function fromSource() {
    const out = [];
    try {
      const html = document.documentElement ? document.documentElement.innerHTML.slice(0, 800000) : "";
      const re = /https?:\/\/[^\s"'<>\\]+?\.(?:m3u8|mpd|mp4)(?:\?[^\s"'<>\\]*)?/gi;
      let m;
      let guard = 0;
      while ((m = re.exec(html)) !== null && guard++ < 40) {
        out.push({ url: m[0].replace(/\\u002F/gi, "/"), source: "page-source" });
      }
    } catch (err) {
      /* ignore */
    }
    return out;
  }

  function detect() {
    return rank([...fromDom(), ...fromPerformance(), ...fromSource()]);
  }

  // ------------------------------------------------------------ 界面

  const isTopFrame = (() => {
    try {
      return window.top === window;
    } catch (e) {
      return false;
    }
  })();

  let panel = null;
  let fab = null;
  let lastCount = -1;

  function t(key, fallback) {
    try {
      return chrome.i18n.getMessage(key) || fallback;
    } catch (e) {
      return fallback;
    }
  }

  function shortUrl(u) {
    try {
      const url = new URL(u);
      const file = url.pathname.split("/").filter(Boolean).pop() || url.hostname;
      return file.length > 46 ? file.slice(0, 44) + "…" : file;
    } catch (e) {
      return u.slice(0, 46);
    }
  }

  function buildFab() {
    if (fab) return fab;
    fab = document.createElement("button");
    fab.id = "ldm-fab";
    fab.type = "button";
    fab.innerHTML = '<span class="ldm-arrow">⬇</span><span class="ldm-count">0</span>';
    fab.title = t("fabTitle", "Send to LDM Mac");
    fab.addEventListener("click", (e) => {
      e.stopPropagation();
      togglePanel();
    });
    document.documentElement.appendChild(fab);
    return fab;
  }

  function togglePanel() {
    if (panel) {
      panel.remove();
      panel = null;
      return;
    }
    renderPanel();
  }

  function flashFab(text) {
    if (!fab) return;
    fab.classList.add("ldm-flash");
    const countEl = fab.querySelector(".ldm-count");
    const old = countEl.textContent;
    countEl.textContent = text;
    setTimeout(() => {
      countEl.textContent = old;
      fab.classList.remove("ldm-flash");
    }, 1500);
  }

  function renderPanel() {
    const items = detect();
    panel = document.createElement("div");
    panel.id = "ldm-panel";

    const head = document.createElement("div");
    head.className = "ldm-head";
    head.innerHTML = `<span class="ldm-title">LDM Mac</span>`;
    const close = document.createElement("button");
    close.className = "ldm-close";
    close.type = "button";
    close.textContent = "✕";
    close.addEventListener("click", (e) => {
      e.stopPropagation();
      togglePanel();
    });
    head.appendChild(close);
    panel.appendChild(head);

    const pageBtn = document.createElement("button");
    pageBtn.className = "ldm-page-btn";
    pageBtn.type = "button";
    pageBtn.textContent = t("sendPage", "Send this page to LDM (yt-dlp)");
    pageBtn.addEventListener("click", (e) => {
      e.stopPropagation();
      send(location.href, "video");
    });
    panel.appendChild(pageBtn);

    if (!items.length) {
      const empty = document.createElement("div");
      empty.className = "ldm-empty";
      empty.textContent = t("noMedia", "No media detected on this page");
      panel.appendChild(empty);
    } else {
      const list = document.createElement("div");
      list.className = "ldm-list";
      items.slice(0, 8).forEach((item) => {
        const row = document.createElement("div");
        row.className = "ldm-row";

        const label = document.createElement("span");
        label.className = "ldm-name";
        label.textContent = shortUrl(item.url);
        label.title = item.url;

        const badge = document.createElement("span");
        badge.className = "ldm-badge";
        badge.textContent = isStreamUrl(item.url) ? "HLS" : item.source;

        const btn = document.createElement("button");
        btn.className = "ldm-row-btn";
        btn.type = "button";
        btn.textContent = t("download", "Download");
        btn.addEventListener("click", (e) => {
          e.stopPropagation();
          send(item.url, item.score >= 100 ? "video" : "file");
        });

        row.appendChild(label);
        row.appendChild(badge);
        row.appendChild(btn);
        list.appendChild(row);
      });
      panel.appendChild(list);
    }

    document.documentElement.appendChild(panel);
  }

  function send(url, kind) {
    chrome.runtime.sendMessage({ type: "ldm-add", url, kind }, (res) => {
      if (chrome.runtime.lastError) return;
    });
  }

  function toast(ok, error) {
    const el = document.createElement("div");
    el.id = "ldm-toast";
    el.className = ok ? "ldm-ok" : "ldm-err";
    el.textContent = ok
      ? t("toastAdded", "Added to LDM Mac")
      : t("toastFailed", "Failed to reach LDM Mac") + (error === "app-unreachable" ? " (app not running?)" : "");
    document.documentElement.appendChild(el);
    setTimeout(() => el.remove(), 2600);
  }

  chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
    if (!msg) return;
    if (msg.type === "ldm-toast") {
      toast(msg.ok, msg.error);
      if (msg.ok) flashFab("✓");
      sendResponse({ ok: true });
    } else if (msg.type === "ldm-list") {
      sendResponse({ ok: true, items: detect(), top: isTopFrame });
    }
    return true;
  });

  // ------------------------------------------------------------ 刷新循环

  function update() {
    const items = detect();
    if (!isTopFrame) {
      // iframe 只上报数量，不显示界面
      if (items.length) chrome.runtime.sendMessage({ type: "ldm-badge", count: items.length });
      return;
    }
    const n = items.length;
    if (n === lastCount) return;
    lastCount = n;

    if (n > 0) {
      const el = buildFab();
      el.querySelector(".ldm-count").textContent = String(n);
      el.classList.add("ldm-show");
      chrome.runtime.sendMessage({ type: "ldm-badge", count: n });
    } else if (fab) {
      fab.classList.remove("ldm-show");
      chrome.runtime.sendMessage({ type: "ldm-badge", count: 0 });
    }
  }

  let scheduled = null;
  function scheduleUpdate() {
    if (scheduled) return;
    scheduled = setTimeout(() => {
      scheduled = null;
      update();
    }, 800);
  }

  update();
  setInterval(update, 4000);

  const observer = new MutationObserver(scheduleUpdate);
  try {
    observer.observe(document.documentElement, { childList: true, subtree: true });
  } catch (e) {
    /* ignore */
  }

  // 暴露给自动化测试
  window.__ldmDetect = detect;
})();

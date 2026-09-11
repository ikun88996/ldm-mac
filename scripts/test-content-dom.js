#!/usr/bin/env node
/**
 * 用 jsdom 在真实 DOM 环境里验证 content.js（扩展的页面嗅探脚本）
 *
 * 覆盖：媒体识别 → 浮动按钮显示 → 打开候选面板 → 点击下载 → 真的进了 LDM Mac
 *
 * jsdom 只是开发期测试依赖，不随扩展分发：
 *   mkdir -p /tmp/ldm-ext-test && npm install --prefix /tmp/ldm-ext-test jsdom
 *   node scripts/test-content-dom.js
 */

const fs = require("fs");
const path = require("path");

const EXT = path.resolve(__dirname, "../build/extensions/chrome");
if (!fs.existsSync(path.join(EXT, "content.js"))) {
  console.log("请先构建扩展：VERSION=1.0.2 ./make_extension.sh");
  process.exit(0);
}
const JSDOM_PATH = process.env.JSDOM_PATH || "/tmp/ldm-ext-test/node_modules";
const API = "http://127.0.0.1:47823";

let { JSDOM } = {};
try {
  ({ JSDOM } = require(path.join(JSDOM_PATH, "jsdom")));
} catch (e) {
  console.log("跳过：未安装 jsdom（npm install --prefix /tmp/ldm-ext-test jsdom）");
  process.exit(0);
}

let failures = 0;
const check = (name, cond, detail = "") => {
  if (!cond) failures++;
  console.log(`${cond ? "  ✓" : "  ✗"} ${name}${detail ? "  (" + detail + ")" : ""}`);
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const PAGE = `<!DOCTYPE html><html><head><meta charset="utf-8"><title>LDM 测试页</title></head><body>
<h1>LDM Mac 扩展测试页</h1>
<video id="v1" src="https://www.w3schools.com/html/mov_bbb.mp4" controls></video>
<audio id="a1" src="https://www.w3schools.com/html/horse.mp3" controls></audio>
<script>var hlsSource = "https://cdn.example.com/hls/master.m3u8?token=abc123";</script>
</body></html>`;

(async () => {
  console.log("content.js DOM 级测试（jsdom）\n");

  const contentSrc = fs.readFileSync(path.join(EXT, "content.js"), "utf8");
  const contentCss = fs.readFileSync(path.join(EXT, "content.css"), "utf8");

  const dom = new JSDOM(PAGE, {
    runScripts: "outside-only",
    pretendToBeVisual: true,
    url: "http://127.0.0.1:8899/test-page.html"
  });
  const { window } = dom;

  // 记录扩展发出的消息，并把下载请求转发给真实的本机接口
  const sent = [];
  window.fetch = (url, opts) => fetch(url, opts);
  window.chrome = {
    i18n: { getMessage: (k, f) => f || k },
    runtime: {
      lastError: null,
      onMessage: { addListener: () => {} },
      sendMessage: (msg, cb) => {
        sent.push(msg);
        const map = { "ldm-add": "/add", "ldm-ping": "/ping", "ldm-tasks": "/tasks" };
        const p = map[msg.type];
        if (!p) {
          if (cb) cb({ ok: true });
          return;
        }
        const opts =
          msg.type === "ldm-add"
            ? {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ url: msg.url, kind: msg.kind, referer: window.location.href })
              }
            : {};
        window
          .fetch(API + p, opts)
          .then((r) => r.json())
          .then((j) => cb && cb(j))
          .catch(() => cb && cb({ ok: false, error: "unreachable" }));
      }
    }
  };

  const style = window.document.createElement("style");
  style.textContent = contentCss;
  window.document.head.appendChild(style);

  window.eval(contentSrc);
  await sleep(300);

  // ---- 检测
  const items = window.__ldmDetect ? window.__ldmDetect() : [];
  check("嗅探到页面媒体", items.length >= 2, `${items.length} 条`);
  check("mp4 被识别", items.some((i) => i.url.endsWith("mov_bbb.mp4")));
  check("mp3 被识别", items.some((i) => i.url.endsWith("horse.mp3")));
  check("源码里的 m3u8 被识别且排最前", items[0] && items[0].url.includes("master.m3u8"), items[0] && items[0].url);

  // ---- 浮层
  const fab = window.document.getElementById("ldm-fab");
  check("右下角浮动按钮已注入", !!fab);
  check("按钮可见（数量 > 0）", fab && window.getComputedStyle(fab).display === "inline-flex", fab && window.getComputedStyle(fab).display);
  check("按钮上显示了媒体数量", fab && fab.querySelector(".ldm-count").textContent === String(items.length),
        fab && fab.querySelector(".ldm-count").textContent);
  check("向后台上报了角标数量", sent.some((m) => m.type === "ldm-badge" && m.count === items.length));

  // ---- 打开面板
  fab.dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
  await sleep(100);
  const panel = window.document.getElementById("ldm-panel");
  check("点击后弹出候选面板", !!panel);
  check("面板里有「整页交给 yt-dlp」入口", !!panel && !!panel.querySelector(".ldm-page-btn"));
  const rows = panel ? Array.from(panel.querySelectorAll(".ldm-row")) : [];
  check("面板列出了候选媒体", rows.length === items.length, `${rows.length} 行`);
  console.log("    面板行：" + rows.map((r) => r.querySelector(".ldm-name").textContent).join(" | "));

  // ---- 点下载 → 真的进 LDM Mac
  const before = await (await fetch(API + "/tasks")).json();
  const beforeCount = (before.tasks || []).length;

  const mp4Row = rows.find((r) => r.querySelector(".ldm-name").textContent.includes("mov_bbb"));
  check("找到 mp4 那一行", !!mp4Row);
  if (mp4Row) {
    mp4Row.querySelector(".ldm-row-btn").dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
    await sleep(1500);
    const after = await (await fetch(API + "/tasks")).json();
    const tasks = after.tasks || [];
    check("点击后任务真的进了 App", tasks.length > beforeCount, `任务数 ${beforeCount} → ${tasks.length}`);
    const mine = tasks.find((t) => (t.url || "").includes("mov_bbb.mp4"));
    check("任务 URL 正确", !!mine, mine ? `${mine.name} · ${mine.status}` : "未找到");
    if (mine) await fetch(API + "/task", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ id: mine.id, action: "remove" })
    });
  }

  console.log(`\n结果：${failures === 0 ? "全部通过" : failures + " 项失败"}`);
  process.exit(failures === 0 ? 0 : 1);
})();

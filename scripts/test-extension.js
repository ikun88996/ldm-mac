#!/usr/bin/env node
/**
 * LDM Mac 扩展集成测试
 *
 * 1. 用 mock 的 do 环境加载 content.js 的纯函数，验证媒体识别/排序逻辑
 * 2. 用 mock 的 chrome API 加载 background.js，通过它调用**真实的** LDM Mac 本机接口，
 *    验证「扩展消息 → 本机接口 → aria2 任务」整条链路（需要 LDM Mac 正在运行）
 *
 * 用法：node scripts/test-extension.js [--url <用于测试的文件直链>]
 */

const fs = require("fs");
const path = require("path");
const vm = require("vm");

const ROOT = path.resolve(__dirname, "..");
const EXT = path.join(ROOT, "build/extensions/chrome");
if (!fs.existsSync(path.join(EXT, "background.js"))) {
  console.log("请先构建扩展：VERSION=1.0.2 ./make_extension.sh");
  process.exit(0);
}
const TEST_URL = (() => {
  const i = process.argv.indexOf("--url");
  return i > -1 ? process.argv[i + 1] : "https://npmmirror.com/mirrors/node/v20.11.0/node-v20.11.0-linux-x64.tar.gz";
})();

let failures = 0;
const results = [];

function check(name, cond, detail = "") {
  results.push({ name, ok: !!cond, detail });
  if (!cond) failures++;
  console.log(`${cond ? "  ✓" : "  ✗"} ${name}${detail ? "  (" + detail + ")" : ""}`);
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ---------------------------------------------------------------- 1. 纯函数

function testPureFunctions() {
  console.log("\n[1/2] content.js 媒体识别逻辑");
  const src = fs.readFileSync(path.join(EXT, "content.js"), "utf8");
  const ctx = { module: { exports: {} }, console };
  vm.createContext(ctx);
  vm.runInContext(src, ctx);
  const core = ctx.module.exports;

  check("能识别 m3u8 分片流", core.isMediaUrl("https://cdn.example.com/hls/index.m3u8?sign=abc"));
  check("能识别 mp4", core.isMediaUrl("https://cdn.example.com/video.mp4"));
  check("普通网页不算媒体", !core.isMediaUrl("https://example.com/article.html"));
  check("忽略非 http 协议", !core.isMediaUrl("blob:https://example.com/1234"));

  const ranked = core.rank([
    { url: "https://c/a/video.mp4", source: "dom" },
    { url: "https://c/a/index.m3u8", source: "network" },
    { url: "https://c/a/video.mp4?token=1", source: "page-source" },
    { url: "https://c/a/page.html", source: "dom" }
  ]);
  check("去重后只剩 2 条", ranked.length === 2, `实际 ${ranked.length}`);
  check("分片流排第一（优先交给 yt-dlp）", ranked[0].url.endsWith(".m3u8"));
  check("mp4 排第二", ranked[1].url.endsWith(".mp4"));
}

// ---------------------------------------------------------------- 2. background + 真实接口

function loadBackground() {
  const listeners = {};
  const badge = { text: "" };
  const chrome = {
    i18n: { getMessage: (k) => k },
    runtime: {
      onInstalled: { addListener: () => {} },
      onStartup: { addListener: () => {} },
      onMessage: { addListener: (fn) => { listeners.message = fn; } },
      lastError: null
    },
    contextMenus: {
      removeAll: (cb) => cb && cb(),
      create: () => {},
      onClicked: { addListener: (fn) => { listeners.click = fn; } }
    },
    action: {
      setBadgeText: (o) => { badge.text = o.text; },
      setBadgeBackgroundColor: () => {}
    },
    tabs: { sendMessage: () => Promise.resolve() },
    cookies: { getAll: async () => [{ name: "SESSDATA", value: "test-cookie" }] }
  };

  const ctx = { chrome, fetch, AbortSignal, setTimeout, clearTimeout, console, JSON, URL, Promise, module: { exports: {} } };
  vm.createContext(ctx);
  vm.runInContext(fs.readFileSync(path.join(EXT, "background.js"), "utf8"), ctx);
  return { listeners, badge, chrome };
}

function callListener(listener, msg) {
  return new Promise((resolve) => {
    const sender = { tab: { id: 1, url: "https://example.com/page", title: "Test Page" } };
    const ret = listener(msg, sender, (res) => resolve(res));
    if (ret !== true) resolve(ret);
  });
}

async function testBackgroundIntegration() {
  console.log("\n[2/2] background.js → LDM Mac 本机接口（需要 App 正在运行）");
  const { listeners } = loadBackground();
  check("已注册 onMessage 监听", typeof listeners.message === "function");
  check("已注册右键菜单监听", typeof listeners.click === "function");
  if (typeof listeners.message !== "function") return;

  const ping = await callListener(listeners.message, { type: "ldm-ping" });
  check("扩展能连上 App", ping && ping.ok, ping ? `版本 ${ping.version}` : "无响应");
  if (!ping || !ping.ok) {
    console.log("    ⚠️  App 未运行，跳过接口相关断言");
    return;
  }

  const added = await callListener(listeners.message, { type: "ldm-add", url: TEST_URL, kind: "file" });
  check("ldm-add 返回任务 id", added && added.ok && added.id, JSON.stringify(added));
  if (!added || !added.ok) return;

  await sleep(1200);
  let tasks = await callListener(listeners.message, { type: "ldm-tasks" });
  const mine = (tasks.tasks || []).find((t) => t.id === added.id);
  check("任务出现在 /tasks 列表", !!mine, mine ? `${mine.name} ${mine.status}` : "未找到");

  // 暂停 / 继续 / 删除
  await callListener(listeners.message, { type: "ldm-task-action", id: added.id, action: "pause" });
  await sleep(1200);
  tasks = await callListener(listeners.message, { type: "ldm-tasks" });
  let t = (tasks.tasks || []).find((x) => x.id === added.id);
  check("暂停生效", t && (t.status === "paused" || t.status === "complete"), t && t.status);

  await callListener(listeners.message, { type: "ldm-task-action", id: added.id, action: "resume" });
  await sleep(1200);

  await callListener(listeners.message, { type: "ldm-task-action", id: added.id, action: "remove" });
  await sleep(1200);
  tasks = await callListener(listeners.message, { type: "ldm-tasks" });
  t = (tasks.tasks || []).find((x) => x.id === added.id);
  check("删除生效", !t);

  // 视频类型走 yt-dlp 分支（用 B 站链接，无需代理）
  const video = await callListener(listeners.message, {
    type: "ldm-add",
    url: "https://www.bilibili.com/video/BV1GJ411x7h7",
    kind: "video"
  });
  check("视频任务创建成功", video && video.ok, JSON.stringify(video));
}

(async () => {
  console.log("LDM Mac 扩展测试\n测试文件直链:", TEST_URL);
  testPureFunctions();
  await testBackgroundIntegration();

  console.log(`\n结果：${results.length - failures}/${results.length} 通过`);
  process.exit(failures === 0 ? 0 : 1);
})();

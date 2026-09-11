#!/bin/bash
# LDM Mac 功能体检脚本
#
# 用途：发布前把「文件下载 / 视频下载 / 唯一化路由 / 失败可见 / 删除与清除 / 引擎」这些
#       容易出事的功能项跑一遍真实验证（不是只看编译通过）。
#
# 用法：bash scripts/audit-features.sh
#   - 会把下载目录临时改到 /tmp/ldm-audit（不污染你的 ~/Downloads），体检结束后自动还原
#   - 体检期间会重启 App 两次（开始时为了生效临时下载目录，结束时为了还原）
#   - 需要 App 正在使用（或可被启动）；Apple 芯片 macOS 14+
#
# 依赖：aria2c / yt-dlp / ffmpeg（brew 安装），以及本机接口可用（默认 47823）

set -u
APP="$HOME/Applications/LDM Mac.app"
[ -d "$APP" ] || APP="/Applications/LDM Mac.app"
API="http://127.0.0.1:47823"
TMPDIR_DL=/tmp/ldm-audit
DOMAIN=com.ldmmac.app
PASS=0; FAIL=0
ok()  { echo "  ✅ $1"; PASS=$((PASS+1)); }
bad() { echo "  ❌ $1"; FAIL=$((FAIL+1)); }

add()   { curl -s -m 20 -X POST -H "Content-Type: application/json" -d "$1" $API/add; }
tasksj(){ curl -s -m 6 $API/tasks; }
act()   { curl -s -m 8 -X POST -H "Content-Type: application/json" -d "{\"id\":\"$1\",\"action\":\"$2\"}" $API/task; }
findid(){ tasksj | python3 -c "
import json,sys
m=[t for t in json.load(sys.stdin)['tasks'] if '$1' in t['url'] or '$1' in t['name']]
print(m[-1]['id'] if m else '')
"; }

restart_app() {
  pkill -f "LDM Mac.app/Contents/MacOS/LdmMac" 2>/dev/null; sleep 3
  open -a "$APP"
  for _ in $(seq 1 25); do curl -s -m 2 $API/ping >/dev/null 2>&1 && return 0; sleep 1; done
  return 1
}

# 记忆原设置，结束时还原
ORIG_DL=$(defaults read $DOMAIN downloadDir 2>/dev/null || echo "__none__")

echo "=== 体检开始：下载目录临时指向 $TMPDIR_DL ==="
mkdir -p "$TMPDIR_DL"
defaults write $DOMAIN downloadDir -string "$TMPDIR_DL"
restart_app || { echo "❌ App 启动失败"; exit 1; }
curl -s -m 5 $API/ping | python3 -c "import json,sys;d=json.load(sys.stdin);print('  版本',d['version'])" 2>/dev/null

echo "=== T1 多线程直链下载（校验大小）==="
add '{"url":"https://npmmirror.com/mirrors/node/v20.11.0/node-v20.11.0-darwin-arm64.tar.gz","kind":"file"}' >/dev/null
sleep 8
S=$(stat -f%z "$TMPDIR_DL/node-v20.11.0-darwin-arm64.tar.gz" 2>/dev/null || echo 0)
[ "$S" = "41896143" ] && ok "40MB 下载完成且大小一致" || bad "大小=$S"

echo "=== T2 暂停 / 继续 ==="
add '{"url":"https://npmmirror.com/mirrors/node/v22.9.0/node-v22.9.0-darwin-arm64.tar.gz","kind":"file"}' >/dev/null
sleep 0.6
GID=$(findid v22.9.0)
if [ -n "$GID" ]; then
  act "$GID" pause >/dev/null; sleep 1.5
  S1=$(tasksj | python3 -c "
import json,sys
m=[t for t in json.load(sys.stdin)['tasks'] if t['id']=='$GID']
print(m[0]['status'] if m else 'gone')")
  act "$GID" resume >/dev/null; sleep 3
  S2=$(tasksj | python3 -c "
import json,sys
m=[t for t in json.load(sys.stdin)['tasks'] if t['id']=='$GID']
print(m[0]['status'] if m else 'gone')")
  [ "$S1" = "paused" ] && ok "暂停生效（${S1}）" || bad "暂停无效（${S1}）"
  case "$S2" in active|complete) ok "继续生效（${S2}）";; *) bad "继续无效（${S2}）";; esac
else
  bad "没抓到任务"
fi

echo "=== T3 删除「下载中」任务：应立刻消失且不再回来 ==="
add '{"url":"https://npmmirror.com/mirrors/node/v20.11.0/node-v20.11.0-linux-x64.tar.gz","kind":"file"}' >/dev/null
sleep 2
GID=$(findid linux-x64)
[ -n "$GID" ] && act "$GID" remove >/dev/null
sleep 4
ST=$(tasksj | python3 -c "
import json,sys
m=[t for t in json.load(sys.stdin)['tasks'] if t['id']=='$GID']
print('GONE' if not m else m[0]['status'])")
[ "$ST" = "GONE" ] && ok "删除后 4 秒仍未回来" || bad "删除后仍在（${ST}）"

echo "=== T4 B站视频（验证 ffmpeg 合并）==="
add '{"url":"https://www.bilibili.com/video/BV1GJ411x7h7","kind":"video"}' >/dev/null
sleep 30
ST=$(tasksj | python3 -c "
import json,sys
m=[t for t in json.load(sys.stdin)['tasks'] if t['kind']=='video' and 'bilibili' in t['url']]
print(m[-1]['status'] if m else 'none')")
[ "$ST" = "complete" ] && ok "B站视频完成" || bad "B站视频状态=$ST"

echo "=== T5 微博短链 t.cn ×2：应全部完成、0 条失败 ==="
add '{"url":"http://t.cn/AX0DIvkB","kind":"video"}' >/dev/null; sleep 8
add '{"url":"http://t.cn/AX0DIvkB","kind":"video"}' >/dev/null; sleep 25
python3 - "$API" <<'PY'
import json, sys, urllib.request
d = json.load(urllib.request.urlopen(sys.argv[1] + "/tasks", timeout=5))
mine = [t for t in d['tasks'] if 't.cn' in t['url'] or '5341781726789638' in t['url']]
bad = [t for t in mine if t['status'] == 'error']
print(f"  {'✅' if (not bad and len(mine) >= 2) else '❌'} 相关任务 {len(mine)} 条，失败 {len(bad)} 条")
PY

echo "=== T6 微博访客跳转地址（直接粘贴，应被解包）==="
add '{"url":"https://passport.weibo.com/visitor/visitor?entry=krvideo&a=enter&url=https%3A%2F%2Fweibo.com%2Ftv%2Fshow%2F1034%3A5341943773986851%3Ffrom%3Dold_pc_videoshow&domain=.weibo.com","kind":"video"}' >/dev/null
sleep 25
ST=$(tasksj | python3 -c "
import json,sys
m=[t for t in json.load(sys.stdin)['tasks'] if '一个字' in t['name']]
print(m[-1]['status'] if m else 'none')")
[ "$ST" = "complete" ] && ok "访客地址解包并完成" || bad "状态=$ST"

echo "=== T7 普通网页按「多线程」提交：留在列表为失败 + 磁盘无垃圾 ==="
add '{"url":"https://www.baidu.com/","kind":"file"}' >/dev/null
sleep 8
python3 - "$API" "$TMPDIR_DL" <<'PY'
import json, sys, urllib.request, glob, os
api, dl = sys.argv[1], sys.argv[2]
d = json.load(urllib.request.urlopen(api + "/tasks", timeout=5))
r = [t for t in d['tasks'] if 'baidu' in t['url']]
junk = glob.glob(os.path.join(dl, 'index.html')) + glob.glob(os.path.join(dl, '*baidu*'))
good = bool(r) and r[-1]['status'] == 'error' and not junk
print(f"  {'✅' if good else '❌'} 状态={r[-1]['status'] if r else 'missing'}，垃圾文件={junk or '无'}")
PY

echo "=== T8 删除已完成的视频任务（以前会自己回到列表）==="
GID=$(tasksj | python3 -c "
import json,sys
m=[t for t in json.load(sys.stdin)['tasks'] if '5341781726789638' in t['url'] or '一个字' in t['name']]
print(m[-1]['id'] if m else '')")
if [ -n "$GID" ]; then
  act "$GID" remove >/dev/null; sleep 5
  ST=$(tasksj | python3 -c "
import json,sys
m=[t for t in json.load(sys.stdin)['tasks'] if t['id']=='$GID']
print('GONE' if not m else 'STILL')")
  [ "$ST" = "GONE" ] && ok "视频任务删除后未回到列表" || bad "又回来了"
else
  bad "没找到可删的已完成视频任务"
fi

echo "=== 还原设置并重启 ==="
if [ "$ORIG_DL" = "__none__" ]; then defaults delete $DOMAIN downloadDir 2>/dev/null
else defaults write $DOMAIN downloadDir -string "$ORIG_DL"; fi
restart_app && echo "  已还原（下载目录：${ORIG_DL}）"
rm -rf "$TMPDIR_DL"

echo
echo "=== 体检结束：通过 $PASS 项，失败 $FAIL 项 ==="
[ "$FAIL" = "0" ]

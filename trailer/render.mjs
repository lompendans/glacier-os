// Renders the trailer frame-by-frame with headless Chrome/Edge (Chrome DevTools Protocol)
// and pipes the frames into ffmpeg.
//   node render.mjs                     -> glacier-trailer.mp4 (1920x1080, 30 fps, with music if present)
//   node render.mjs --stills 3.6,21.5   -> stills/frame-<t>.png only
import { spawn } from "node:child_process";
import { existsSync, mkdirSync, writeFileSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const FPS = 30, DUR = 50, W = 1920, H = 1080, PORT = 9333;
const args = process.argv.slice(2);
const stillsArg = args.includes("--stills") ? args[args.indexOf("--stills") + 1] : null;

const browsers = [
  "C:/Program Files/Google/Chrome/Application/chrome.exe",
  "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe",
  "/usr/bin/google-chrome", "/usr/bin/chromium",
];
const exe = browsers.find(existsSync);
if (!exe) throw new Error("no Chrome/Edge/Chromium found");

const profile = mkdtempSync(join(tmpdir(), "glacier-render-"));
const chrome = spawn(exe, [
  "--headless=new", `--remote-debugging-port=${PORT}`, `--user-data-dir=${profile}`,
  `--window-size=${W},${H}`, "--hide-scrollbars", "--force-device-scale-factor=1",
  "--no-first-run", "--no-default-browser-check", "--mute-audio", "about:blank",
], { stdio: "ignore" });

const sleep = ms => new Promise(r => setTimeout(r, ms));
async function json(url, method = "GET") {
  for (let i = 0; i < 50; i++) {
    try { const r = await fetch(url, { method }); if (r.ok) return r.json(); } catch {}
    await sleep(200);
  }
  throw new Error("browser did not start");
}

const target = await json(`http://127.0.0.1:${PORT}/json/new?about:blank`, "PUT");
const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
let nextId = 1; const pending = new Map();
ws.onmessage = ev => {
  const m = JSON.parse(ev.data);
  if (m.id && pending.has(m.id)) { const { res, rej } = pending.get(m.id); pending.delete(m.id); m.error ? rej(new Error(m.error.message)) : res(m.result); }
};
const send = (method, params = {}) => new Promise((res, rej) => { const id = nextId++; pending.set(id, { res, rej }); ws.send(JSON.stringify({ id, method, params })); });
const evaluate = async expr => {
  const r = await send("Runtime.evaluate", { expression: expr, awaitPromise: true, returnByValue: true });
  if (r.exceptionDetails) throw new Error(r.exceptionDetails.exception?.description || "evaluate failed");
  return r.result.value;
};

await send("Page.enable");
await send("Emulation.setDeviceMetricsOverride", { width: W, height: H, deviceScaleFactor: 1, mobile: false });
const url = pathToFileURL(join(here, "index.html")).href + "?render=1";
await send("Page.navigate", { url });
for (let i = 0; i < 100 && !(await evaluate("!!window.__ready").catch(() => false)); i++) await sleep(200);
if (!(await evaluate("!!window.__ready"))) throw new Error("trailer page never became ready");

const frameAt = async t => {
  await evaluate(`seek(${t}); new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r)))`);
  const { data } = await send("Page.captureScreenshot", { format: stillsArg ? "png" : "jpeg", quality: stillsArg ? undefined : 95, captureBeyondViewport: false });
  return Buffer.from(data, "base64");
};

try {
  if (stillsArg) {
    mkdirSync(join(here, "stills"), { recursive: true });
    for (const t of stillsArg.split(",").map(Number)) {
      writeFileSync(join(here, "stills", `frame-${t.toFixed(1)}.png`), await frameAt(t));
      console.log("still", t);
    }
  } else {
    const music = join(here, "glacier-trailer-music.m4a");
    const out = join(here, "glacier-trailer.mp4");
    const ff = spawn("ffmpeg", [
      "-y", "-hide_banner", "-loglevel", "error",
      "-f", "image2pipe", "-framerate", String(FPS), "-c:v", "mjpeg", "-i", "-",
      ...(existsSync(music) ? ["-i", music, "-c:a", "aac", "-b:a", "192k", "-shortest"] : []),
      "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p", "-movflags", "+faststart", out,
    ], { stdio: ["pipe", "inherit", "inherit"] });
    const total = FPS * DUR;
    for (let f = 0; f < total; f++) {
      const buf = await frameAt(f / FPS);
      if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once("drain", r));
      if (f % 150 === 0) console.log(`frame ${f}/${total}`);
    }
    ff.stdin.end();
    const code = await new Promise(r => ff.on("close", r));
    if (code !== 0) throw new Error("ffmpeg failed with code " + code);
    console.log("wrote", out);
  }
} finally {
  ws.close(); chrome.kill();
  await sleep(500);
  try { rmSync(profile, { recursive: true, force: true }); } catch {}
}

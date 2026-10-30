#!/usr/bin/env node

/**
 * mstack 3D Dashboard HTTP & Live API Server
 * Lightweight, zero-dependency Node.js server to host the 3D hologram dashboard
 * and stream migration state updates.
 */

const http = require("node:http");
const fs = require("node:fs");
const path = require("node:path");
const { spawn } = require("node:child_process");
const { generateDashboard } = require("./generate-dashboard");

const WORKSPACE_ROOT = process.cwd();
const PLAN_FILE = path.resolve(WORKSPACE_ROOT, ".mstack/migration-plan.json");
const PROFILE_FILE = path.resolve(WORKSPACE_ROOT, ".mstack/target-profile.json");
const DASHBOARD_DIR = path.resolve(WORKSPACE_ROOT, ".mstack/dashboard");
const PID_FILE = path.resolve(WORKSPACE_ROOT, ".mstack/automation.pid");
const URL_FILE = path.resolve(WORKSPACE_ROOT, ".mstack/dashboard.url");

let activePort = 3333;
let shouldOpenBrowser = false;

// Parse args
const args = process.argv.slice(2);
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--port" && args[i + 1]) {
    activePort = parseInt(args[i + 1], 10) || 3333;
    i++;
  } else if (args[i] === "--open") {
    shouldOpenBrowser = true;
  }
}

// Ensure initial dashboard files exist
generateDashboard();

function getMimeType(filePath) {
  const ext = path.extname(filePath).toLowerCase();
  switch (ext) {
    case ".html": return "text/html; charset=utf-8";
    case ".js": return "application/javascript; charset=utf-8";
    case ".json": return "application/json; charset=utf-8";
    case ".css": return "text/css; charset=utf-8";
    case ".svg": return "image/svg+xml";
    case ".png": return "image/png";
    default: return "application/octet-stream";
  }
}

function getLatestPlanData() {
  let plan = { version: "2.0", executionMode: "sequential-substep-handoff", steps: [] };
  let targetProfile = {};

  if (fs.existsSync(PLAN_FILE)) {
    try {
      plan = JSON.parse(fs.readFileSync(PLAN_FILE, "utf8"));
    } catch (e) {}
  }
  if (fs.existsSync(PROFILE_FILE)) {
    try {
      targetProfile = JSON.parse(fs.readFileSync(PROFILE_FILE, "utf8"));
    } catch (e) {}
  }

  let isAutomationRunning = false;
  let runnerPid = null;
  if (fs.existsSync(PID_FILE)) {
    try {
      runnerPid = parseInt(fs.readFileSync(PID_FILE, "utf8").trim(), 10);
      if (runnerPid && !isNaN(runnerPid)) {
        // Check if process is alive
        process.kill(runnerPid, 0);
        isAutomationRunning = true;
      }
    } catch (e) {
      isAutomationRunning = false;
    }
  }

  return {
    ...plan,
    targetProfile,
    automationState: {
      isRunning: isAutomationRunning,
      pid: runnerPid
    },
    serverTime: new Date().toISOString()
  };
}

function openBrowser(targetUrl) {
  const startCmd = process.platform === "darwin" ? "open" :
                   process.platform === "win32" ? "start" : "xdg-open";
  try {
    spawn(startCmd, [targetUrl], { detached: true, stdio: "ignore" }).unref();
  } catch (e) {}
}

const server = http.createServer((req, res) => {
  // Enable CORS for API requests
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");

  if (req.method === "OPTIONS") {
    res.writeHead(204);
    res.end();
    return;
  }

  const reqUrl = new URL(req.url, `http://${req.headers.host || "localhost"}`);
  const pathname = reqUrl.pathname;

  if (pathname === "/api/plan" || pathname === "/api/live-state.json") {
    const data = getLatestPlanData();
    res.writeHead(200, { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-cache" });
    res.end(JSON.stringify(data, null, 2));
    return;
  }

  if (pathname === "/api/status") {
    const data = getLatestPlanData();
    const counts = { COMPLETED: 0, IN_PROGRESS: 0, NEEDS_MORE_WORK: 0, PENDING: 0, FAILED: 0 };
    for (const s of data.steps || []) counts[s.status] = (counts[s.status] || 0) + 1;
    res.writeHead(200, { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-cache" });
    res.end(JSON.stringify({
      automationState: data.automationState,
      counts,
      totalSteps: (data.steps || []).length,
      updatedAt: data.updatedAt
    }, null, 2));
    return;
  }

  // Serve static dashboard files
  let safeRelPath = pathname === "/" ? "index.html" : pathname.replace(/^\/+/, "");
  const targetFile = path.resolve(DASHBOARD_DIR, safeRelPath);

  // Security check to ensure requested file is inside DASHBOARD_DIR
  if (!targetFile.startsWith(DASHBOARD_DIR)) {
    res.writeHead(403);
    res.end("Forbidden");
    return;
  }

  if (fs.existsSync(targetFile) && fs.statSync(targetFile).isFile()) {
    res.writeHead(200, {
      "Content-Type": getMimeType(targetFile),
      "Cache-Control": targetFile.endsWith(".html") ? "no-cache" : "public, max-age=60"
    });
    fs.createReadStream(targetFile).pipe(res);
  } else {
    // Fallback to index.html for SPA-style routing
    const indexFile = path.join(DASHBOARD_DIR, "index.html");
    if (fs.existsSync(indexFile)) {
      res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
      fs.createReadStream(indexFile).pipe(res);
    } else {
      res.writeHead(404);
      res.end("404 Not Found");
    }
  }
});

function startServer(portToTry) {
  server.listen(portToTry, () => {
    const localUrl = `http://localhost:${portToTry}`;
    fs.mkdirSync(path.dirname(URL_FILE), { recursive: true });
    fs.writeFileSync(URL_FILE, localUrl + "\n", "utf8");

    console.log(`\n🌌 [mstack dashboard] 3D Migration Pipeline Hologram Live at:`);
    console.log(`   🌐 URL  : ${localUrl}`);
    console.log(`   📁 File : file://${path.join(DASHBOARD_DIR, "index.html")}\n`);

    if (shouldOpenBrowser) {
      openBrowser(localUrl);
    }

    // Watch migration-plan.json for disk updates to auto-regenerate dashboard data
    if (fs.existsSync(PLAN_FILE)) {
      try {
        let timer = null;
        fs.watch(PLAN_FILE, () => {
          clearTimeout(timer);
          timer = setTimeout(() => {
            try {
              generateDashboard();
            } catch (e) {}
          }, 300);
        });
      } catch (e) {}
    }
  });

  server.on("error", (err) => {
    if (err.code === "EADDRINUSE") {
      console.log(`[mstack dashboard] Port ${portToTry} in use, trying ${portToTry + 1}...`);
      startServer(portToTry + 1);
    } else {
      console.error("[mstack dashboard] Server error:", err.message);
    }
  });
}

startServer(activePort);


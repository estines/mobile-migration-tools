#!/usr/bin/env node

/**
 * mstack 3D Migration Pipeline Dashboard Generator
 *
 * Generates:
 * 1. .mstack/dashboard/index.html — Full Three.js 3D spatial interactive dashboard
 * 2. .mstack/dashboard/dashboard-data.js — JSONP data bundle for zero-CORS file:// viewing
 * 3. .mstack/dashboard/live-state.json — Standalone API state representation
 */

const fs = require("node:fs");
const path = require("node:path");

const PKG_ROOT = path.resolve(__dirname, "..");
const WORKSPACE_ROOT = process.cwd();

function resolvePath(relPath) {
  return path.resolve(WORKSPACE_ROOT, relPath);
}

function loadJson(filePath, fallback = {}) {
  try {
    if (fs.existsSync(filePath)) {
      return JSON.parse(fs.readFileSync(filePath, "utf8"));
    }
  } catch (err) {
    console.warn(`[mstack dashboard] Warning reading ${filePath}:`, err.message);
  }
  return fallback;
}

function generateDashboardHtml() {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>mstack 3D Migration Pipeline Hologram</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;700;800&family=Space+Grotesk:wght@400;600;700&display=swap" rel="stylesheet">
  <style>
    :root {
      --bg: #07090e;
      --panel-bg: rgba(13, 17, 26, 0.78);
      --panel-border: rgba(56, 189, 248, 0.22);
      --panel-glow: rgba(56, 189, 248, 0.12);
      --text: #e2e8f0;
      --text-muted: #94a3b8;
      --text-dim: #64748b;
      --accent: #38bdf8;
      --accent-glow: #0284c7;
      --completed: #10b981;
      --completed-glow: rgba(16, 185, 129, 0.4);
      --in-progress: #06b6d4;
      --in-progress-glow: rgba(6, 182, 212, 0.5);
      --needs-work: #f59e0b;
      --needs-work-glow: rgba(245, 158, 11, 0.4);
      --failed: #ef4444;
      --failed-glow: rgba(239, 68, 68, 0.5);
      --pending: #475569;
    }

    * {
      box-sizing: border-box;
      margin: 0;
      padding: 0;
      user-select: none;
    }

    body, html {
      width: 100%;
      height: 100%;
      overflow: hidden;
      background-color: var(--bg);
      color: var(--text);
      font-family: 'Space Grotesk', -apple-system, BlinkMacSystemFont, sans-serif;
    }

    #webgl-canvas {
      position: absolute;
      top: 0;
      left: 0;
      width: 100%;
      height: 100%;
      z-index: 1;
      outline: none;
    }

    /* Scanline & Holographic Vignette Effect */
    .holo-overlay {
      position: absolute;
      top: 0;
      left: 0;
      width: 100%;
      height: 100%;
      z-index: 2;
      pointer-events: none;
      background: radial-gradient(circle at 50% 50%, transparent 65%, rgba(0, 0, 0, 0.8) 100%),
                  linear-gradient(rgba(18, 16, 16, 0) 50%, rgba(0, 0, 0, 0.25) 50%);
      background-size: 100% 100%, 100% 4px;
    }

    /* Top HUD Navigation Bar */
    header.hud-header {
      position: absolute;
      top: 16px;
      left: 20px;
      right: 20px;
      z-index: 10;
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: 12px 24px;
      background: var(--panel-bg);
      backdrop-filter: blur(16px);
      -webkit-backdrop-filter: blur(16px);
      border: 1px solid var(--panel-border);
      border-radius: 14px;
      box-shadow: 0 8px 32px rgba(0, 0, 0, 0.5), inset 0 0 16px var(--panel-glow);
    }

    .brand-section {
      display: flex;
      align-items: center;
      gap: 14px;
    }

    .logo-badge {
      display: flex;
      align-items: center;
      justify-content: center;
      width: 38px;
      height: 38px;
      border-radius: 10px;
      background: linear-gradient(135deg, #0284c7, #38bdf8);
      box-shadow: 0 0 20px rgba(56, 189, 248, 0.6);
      font-weight: 800;
      font-size: 18px;
      color: #030712;
      font-family: 'JetBrains Mono', monospace;
    }

    .brand-title {
      font-weight: 700;
      font-size: 16px;
      letter-spacing: 0.5px;
      display: flex;
      flex-direction: column;
    }

    .brand-title span.sub {
      font-size: 11px;
      color: var(--accent);
      font-weight: 500;
      font-family: 'JetBrains Mono', monospace;
      text-transform: uppercase;
      letter-spacing: 1px;
    }

    .progress-stats {
      display: flex;
      align-items: center;
      gap: 20px;
    }

    .stat-pill {
      display: flex;
      align-items: center;
      gap: 8px;
      padding: 6px 14px;
      background: rgba(15, 23, 42, 0.6);
      border: 1px solid rgba(255, 255, 255, 0.08);
      border-radius: 8px;
      font-size: 13px;
      font-family: 'JetBrains Mono', monospace;
    }

    .stat-pill .dot {
      width: 8px;
      height: 8px;
      border-radius: 50%;
    }

    .dot.completed { background: var(--completed); box-shadow: 0 0 10px var(--completed); }
    .dot.in-progress { background: var(--in-progress); box-shadow: 0 0 10px var(--in-progress); animation: pulse 1.5s infinite; }
    .dot.needs-work { background: var(--needs-work); box-shadow: 0 0 10px var(--needs-work); }
    .dot.failed { background: var(--failed); box-shadow: 0 0 10px var(--failed); }
    .dot.pending { background: var(--pending); }

    .header-actions {
      display: flex;
      align-items: center;
      gap: 10px;
    }

    button.hud-btn {
      background: rgba(30, 41, 59, 0.7);
      border: 1px solid rgba(56, 189, 248, 0.3);
      color: var(--text);
      padding: 8px 14px;
      border-radius: 8px;
      cursor: pointer;
      font-family: 'JetBrains Mono', monospace;
      font-size: 12px;
      font-weight: 600;
      display: flex;
      align-items: center;
      gap: 6px;
      transition: all 0.2s cubic-bezier(0.16, 1, 0.3, 1);
    }

    button.hud-btn:hover {
      background: rgba(56, 189, 248, 0.2);
      border-color: var(--accent);
      box-shadow: 0 0 14px rgba(56, 189, 248, 0.4);
      transform: translateY(-1px);
    }

    button.hud-btn.active {
      background: var(--accent);
      color: #0f172a;
      border-color: var(--accent);
      box-shadow: 0 0 16px rgba(56, 189, 248, 0.6);
    }

    /* Left Floating Control Deck */
    .control-deck {
      position: absolute;
      top: 96px;
      left: 20px;
      z-index: 10;
      display: flex;
      flex-direction: column;
      gap: 12px;
      width: 220px;
    }

    .hud-card {
      background: var(--panel-bg);
      backdrop-filter: blur(16px);
      -webkit-backdrop-filter: blur(16px);
      border: 1px solid var(--panel-border);
      border-radius: 12px;
      padding: 14px;
      box-shadow: 0 8px 24px rgba(0, 0, 0, 0.4);
    }

    .card-title {
      font-size: 11px;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 1px;
      color: var(--accent);
      font-family: 'JetBrains Mono', monospace;
      margin-bottom: 10px;
      display: flex;
      justify-content: space-between;
      align-items: center;
    }

    .view-btns {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 6px;
    }

    .view-btns button {
      padding: 6px 8px;
      font-size: 11px;
      text-align: center;
      justify-content: center;
    }

    .filter-list {
      display: flex;
      flex-direction: column;
      gap: 4px;
    }

    .filter-item {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 6px 10px;
      border-radius: 6px;
      font-size: 12px;
      color: var(--text-muted);
      cursor: pointer;
      transition: background 0.15s;
    }

    .filter-item:hover, .filter-item.active {
      background: rgba(56, 189, 248, 0.15);
      color: var(--text);
    }

    .filter-item.active {
      font-weight: 600;
      border-left: 2px solid var(--accent);
    }

    /* Right Node Inspector Drawer */
    .inspector-panel {
      position: absolute;
      top: 96px;
      right: 20px;
      bottom: 60px;
      width: 380px;
      z-index: 10;
      background: var(--panel-bg);
      backdrop-filter: blur(20px);
      -webkit-backdrop-filter: blur(20px);
      border: 1px solid var(--panel-border);
      border-radius: 14px;
      box-shadow: 0 12px 40px rgba(0, 0, 0, 0.6), inset 0 0 20px var(--panel-glow);
      display: flex;
      flex-direction: column;
      transform: translateX(410px);
      transition: transform 0.35s cubic-bezier(0.16, 1, 0.3, 1);
    }

    .inspector-panel.open {
      transform: translateX(0);
    }

    .inspector-header {
      padding: 16px 20px;
      border-bottom: 1px solid rgba(255, 255, 255, 0.08);
      display: flex;
      align-items: flex-start;
      justify-content: space-between;
    }

    .node-badge-code {
      font-size: 11px;
      font-family: 'JetBrains Mono', monospace;
      padding: 3px 8px;
      background: rgba(56, 189, 248, 0.2);
      color: var(--accent);
      border-radius: 6px;
      display: inline-block;
      margin-bottom: 6px;
      font-weight: 700;
    }

    .node-title {
      font-size: 16px;
      font-weight: 700;
      line-height: 1.3;
      color: var(--text);
    }

    .close-btn {
      background: none;
      border: none;
      color: var(--text-muted);
      font-size: 18px;
      cursor: pointer;
      padding: 4px;
      line-height: 1;
    }

    .close-btn:hover {
      color: var(--text);
    }

    .inspector-content {
      flex: 1;
      overflow-y: auto;
      padding: 20px;
      display: flex;
      flex-direction: column;
      gap: 16px;
    }

    .inspector-content::-webkit-scrollbar {
      width: 5px;
    }
    .inspector-content::-webkit-scrollbar-thumb {
      background: rgba(56, 189, 248, 0.25);
      border-radius: 4px;
    }

    .field-group {
      display: flex;
      flex-direction: column;
      gap: 6px;
    }

    .field-label {
      font-size: 11px;
      text-transform: uppercase;
      font-family: 'JetBrains Mono', monospace;
      color: var(--accent);
      letter-spacing: 0.5px;
      font-weight: 700;
    }

    .field-val {
      font-size: 13px;
      color: var(--text);
      line-height: 1.45;
      background: rgba(15, 23, 42, 0.6);
      padding: 10px 12px;
      border-radius: 8px;
      border: 1px solid rgba(255, 255, 255, 0.05);
    }

    .field-val.code {
      font-family: 'JetBrains Mono', monospace;
      font-size: 11.5px;
      white-space: pre-wrap;
      word-break: break-all;
    }

    .status-badge {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      padding: 4px 10px;
      border-radius: 6px;
      font-family: 'JetBrains Mono', monospace;
      font-size: 12px;
      font-weight: 700;
    }

    .status-badge.COMPLETED { background: rgba(16, 185, 129, 0.2); color: var(--completed); border: 1px solid var(--completed); }
    .status-badge.IN_PROGRESS { background: rgba(6, 182, 212, 0.2); color: var(--in-progress); border: 1px solid var(--in-progress); animation: pulse 1.5s infinite; }
    .status-badge.NEEDS_MORE_WORK { background: rgba(245, 158, 11, 0.2); color: var(--needs-work); border: 1px solid var(--needs-work); }
    .status-badge.FAILED { background: rgba(239, 68, 68, 0.2); color: var(--failed); border: 1px solid var(--failed); }
    .status-badge.PENDING { background: rgba(100, 116, 139, 0.2); color: var(--text-muted); border: 1px solid var(--pending); }

    /* Bottom Circuit Breaker Status Bar */
    footer.hud-footer {
      position: absolute;
      bottom: 14px;
      left: 20px;
      right: 20px;
      z-index: 10;
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: 8px 20px;
      background: var(--panel-bg);
      backdrop-filter: blur(14px);
      -webkit-backdrop-filter: blur(14px);
      border: 1px solid var(--panel-border);
      border-radius: 10px;
      font-family: 'JetBrains Mono', monospace;
      font-size: 11.5px;
      color: var(--text-muted);
    }

    .cb-shields {
      display: flex;
      align-items: center;
      gap: 16px;
    }

    .cb-item {
      display: flex;
      align-items: center;
      gap: 6px;
    }

    .cb-item.active {
      color: var(--completed);
    }

    .live-heartbeat {
      display: flex;
      align-items: center;
      gap: 8px;
      color: var(--accent);
    }

    .live-dot {
      width: 7px;
      height: 7px;
      border-radius: 50%;
      background: var(--accent);
      box-shadow: 0 0 8px var(--accent);
      animation: pulse 1.5s infinite;
    }

    @keyframes pulse {
      0% { opacity: 0.4; transform: scale(0.9); }
      50% { opacity: 1; transform: scale(1.15); }
      100% { opacity: 0.4; transform: scale(0.9); }
    }

    /* 3D Model Floating Labels */
    .node-label-3d {
      position: absolute;
      z-index: 5;
      padding: 4px 8px;
      background: rgba(15, 23, 42, 0.85);
      border: 1px solid rgba(56, 189, 248, 0.35);
      border-radius: 6px;
      font-family: 'JetBrains Mono', monospace;
      font-size: 10.5px;
      color: #f1f5f9;
      pointer-events: none;
      transform: translate(-50%, -120%);
      white-space: nowrap;
      box-shadow: 0 4px 12px rgba(0,0,0,0.5);
      transition: opacity 0.2s;
    }

    /* Fallback / Offline Notice */
    #no-webgl {
      position: absolute;
      top: 50%;
      left: 50%;
      transform: translate(-50%, -50%);
      background: var(--panel-bg);
      border: 1px solid var(--failed);
      padding: 30px;
      border-radius: 12px;
      z-index: 100;
      text-align: center;
      display: none;
    }
  </style>

  <!-- Load Three.js and OrbitControls from reliable CDNs with local graceful fallback -->
  <script src="https://cdnjs.cloudflare.com/ajax/libs/three.js/r128/three.min.js"></script>
  <script src="https://cdn.jsdelivr.net/npm/three@0.128.0/examples/js/controls/OrbitControls.js"></script>
</head>
<body>
  <div class="holo-overlay"></div>
  <canvas id="webgl-canvas"></canvas>

  <header class="hud-header">
    <div class="brand-section">
      <div class="logo-badge">m</div>
      <div class="brand-title">
        <span>mstack 3D Pipeline</span>
        <span class="sub" id="hdr-target-platform">KMP + Compose Multiplatform</span>
      </div>
    </div>

    <div class="progress-stats">
      <div class="stat-pill"><div class="dot completed"></div> <span id="stat-completed">0</span> Done</div>
      <div class="stat-pill"><div class="dot in-progress"></div> <span id="stat-in-progress">0</span> Running</div>
      <div class="stat-pill"><div class="dot needs-work"></div> <span id="stat-needs-work">0</span> Handoffs</div>
      <div class="stat-pill"><div class="dot pending"></div> <span id="stat-pending">0</span> Queued</div>
      <div class="stat-pill" id="pill-failed" style="display:none;"><div class="dot failed"></div> <span id="stat-failed">0</span> Failed</div>
    </div>

    <div class="header-actions">
      <button class="hud-btn" id="btn-focus-active" title="Focus camera on current running step">🎯 Focus Active</button>
      <button class="hud-btn" id="btn-reset-cam" title="Reset Camera to Overview">🔭 Overview</button>
      <button class="hud-btn" id="btn-auto-rotate">🔄 Orbit</button>
      <button class="hud-btn" id="btn-audio" title="Toggle Synthesized Audio Chimes">🔊 SFX: Off</button>
      <button class="hud-btn active" id="btn-refresh" title="Force Refresh State">⚡ Refresh</button>
    </div>
  </header>

  <div class="control-deck">
    <div class="hud-card">
      <div class="card-title">
        <span>Camera Presets</span>
      </div>
      <div class="view-btns">
        <button class="hud-btn" onclick="setCameraAngle('iso')">Isometric</button>
        <button class="hud-btn" onclick="setCameraAngle('top')">Top-Down</button>
        <button class="hud-btn" onclick="setCameraAngle('side')">Side Flyby</button>
        <button class="hud-btn" onclick="setCameraAngle('front')">Front Grid</button>
      </div>
    </div>

    <div class="hud-card">
      <div class="card-title">
        <span>Feature Pipelines</span>
      </div>
      <div class="filter-list" id="feature-filter-list">
        <div class="filter-item active" onclick="filterByFeature('ALL')">All Pipelines</div>
      </div>
    </div>

    <div class="hud-card">
      <div class="card-title">
        <span>Phase Filter</span>
      </div>
      <div class="filter-list">
        <div class="filter-item active" onclick="filterByPhase('ALL')">All Phases (1-4)</div>
        <div class="filter-item" onclick="filterByPhase('step1')">Step 1: Logic & Storage</div>
        <div class="filter-item" onclick="filterByPhase('step2')">Step 2: UI Parity</div>
        <div class="filter-item" onclick="filterByPhase('step3')">Step 3: Nav & Adaptive</div>
        <div class="filter-item" onclick="filterByPhase('step4')">Step 4: Greenfield/Cutover</div>
      </div>
    </div>
  </div>

  <aside class="inspector-panel" id="inspector-panel">
    <div class="inspector-header">
      <div>
        <div class="node-badge-code" id="insp-code">SUB-STEP 1.1</div>
        <div class="node-title" id="insp-title">Select a 3D Node to Inspect</div>
      </div>
      <button class="close-btn" onclick="closeInspector()">✕</button>
    </div>
    <div class="inspector-content">
      <div class="field-group">
        <div class="field-label">Current State</div>
        <div><span class="status-badge PENDING" id="insp-status">PENDING</span></div>
      </div>

      <div class="field-group">
        <div class="field-label">Goal & Mandate</div>
        <div class="field-val" id="insp-goal">Click any 3D node in the hologram pipeline to view its real-time verification details, verified files, golden locks, and handoff history.</div>
      </div>

      <div class="field-group">
        <div class="field-label">Required Principles</div>
        <div class="field-val code" id="insp-principles">principle-always-compile</div>
      </div>

      <div class="field-group">
        <div class="field-label">Last Agent Handoff Summary</div>
        <div class="field-val" id="insp-handoff">No handoff recorded yet.</div>
      </div>

      <div class="field-group">
        <div class="field-label">Verified Files Touched</div>
        <div class="field-val code" id="insp-files">none</div>
      </div>

      <div class="field-group">
        <div class="field-label">Next Agent Todo / Continuations</div>
        <div class="field-val" id="insp-remaining">none</div>
      </div>

      <div class="field-group" id="group-golden-locks" style="display:none;">
        <div class="field-label">Locked Golden Master Baselines</div>
        <div class="field-val code" id="insp-locks">none</div>
      </div>

      <div class="field-group" id="group-attempts" style="display:none;">
        <div class="field-label">Failure / Retry History</div>
        <div class="field-val code" id="insp-attempts">none</div>
      </div>
    </div>
  </aside>

  <footer class="hud-footer">
    <div class="cb-shields">
      <div class="cb-item active">🛡️ Golden SHA-256 Lock: <span id="lbl-locks-count">0 locked</span></div>
      <div class="cb-item active">⚡ Non-Empty Diff Guard</div>
      <div class="cb-item active">🛑 Ping-Pong Guard</div>
      <div class="cb-item active">🔄 Max Continuations: <span id="lbl-max-cont">3</span></div>
    </div>
    <div class="live-heartbeat">
      <div class="live-dot"></div>
      <span id="lbl-live-status">LIVE STREAM POLLING (1.5s)</span>
    </div>
  </footer>

  <div id="no-webgl">
    <h3>WebGL Acceleration Required</h3>
    <p>Please enable WebGL in your browser or run in Chrome/Safari/Firefox to render the 3D pipeline hologram.</p>
  </div>

  <!-- Dynamic data loader fallback for file:// without server CORS -->
  <script id="mstack-data-script" src="./dashboard-data.js"></script>

  <script>
    // --- 3D Hologram Pipeline Engine ---
    let scene, camera, renderer, controls;
    let nodeObjects = []; // Holds 3D meshes and their step data
    let pipelineConduits = []; // Holds tube connections between nodes
    let energyPulses = []; // Animated laser energy particles
    let activeFilterFeature = 'ALL';
    let activeFilterPhase = 'ALL';
    let autoRotate = false;
    let sfxEnabled = false;
    let audioCtx = null;
    let lastKnownStepStates = {};

    let currentPlan = null;
    let currentProfile = null;
    let selectedStepId = null;

    // Node state color palettes & glow configs
    const STATE_CONFIGS = {
      COMPLETED: {
        color: 0x10b981,
        emissive: 0x059669,
        wireColor: 0x34d399,
        scale: 1.0,
        height: 1.0,
        name: 'COMPLETED'
      },
      IN_PROGRESS: {
        color: 0x06b6d4,
        emissive: 0x0891b2,
        wireColor: 0x38bdf8,
        scale: 1.25,
        height: 1.6,
        name: 'IN_PROGRESS'
      },
      NEEDS_MORE_WORK: {
        color: 0xf59e0b,
        emissive: 0xd97706,
        wireColor: 0xfbbf24,
        scale: 1.1,
        height: 1.2,
        name: 'NEEDS_MORE_WORK'
      },
      FAILED: {
        color: 0xef4444,
        emissive: 0xb91c1c,
        wireColor: 0xf87171,
        scale: 1.15,
        height: 0.4,
        name: 'FAILED'
      },
      PENDING: {
        color: 0x475569,
        emissive: 0x1e293b,
        wireColor: 0x64748b,
        scale: 0.85,
        height: 0.2,
        name: 'PENDING'
      }
    };

    function initAudio() {
      if (!audioCtx && (window.AudioContext || window.webkitAudioContext)) {
        audioCtx = new (window.AudioContext || window.webkitAudioContext)();
      }
    }

    function playSound(type) {
      if (!sfxEnabled || !audioCtx) return;
      try {
        if (audioCtx.state === 'suspended') audioCtx.resume();
        const osc = audioCtx.createOscillator();
        const gain = audioCtx.createGain();
        osc.connect(gain);
        gain.connect(audioCtx.destination);
        const now = audioCtx.currentTime;

        if (type === 'select') {
          osc.type = 'sine';
          osc.frequency.setValueAtTime(540, now);
          osc.frequency.exponentialRampToValueAtTime(880, now + 0.1);
          gain.gain.setValueAtTime(0.08, now);
          gain.gain.exponentialRampToValueAtTime(0.001, now + 0.1);
          osc.start(now);
          osc.stop(now + 0.1);
        } else if (type === 'complete') {
          osc.type = 'triangle';
          osc.frequency.setValueAtTime(440, now);
          osc.frequency.exponentialRampToValueAtTime(880, now + 0.2);
          gain.gain.setValueAtTime(0.12, now);
          gain.gain.exponentialRampToValueAtTime(0.001, now + 0.35);
          osc.start(now);
          osc.stop(now + 0.35);
        } else if (type === 'fail') {
          osc.type = 'sawtooth';
          osc.frequency.setValueAtTime(220, now);
          osc.frequency.exponentialRampToValueAtTime(110, now + 0.3);
          gain.gain.setValueAtTime(0.12, now);
          gain.gain.exponentialRampToValueAtTime(0.001, now + 0.3);
          osc.start(now);
          osc.stop(now + 0.3);
        }
      } catch (e) {}
    }

    // --- Three.js Initialization ---
    function initThreeScene() {
      if (typeof THREE === 'undefined') {
        document.getElementById('no-webgl').style.display = 'block';
        return;
      }

      const canvas = document.getElementById('webgl-canvas');
      const width = window.innerWidth;
      const height = window.innerHeight;

      scene = new THREE.Scene();
      scene.background = new THREE.Color(0x06090e);
      scene.fog = new THREE.FogExp2(0x06090e, 0.012);

      camera = new THREE.PerspectiveCamera(50, width / height, 0.5, 1000);
      camera.position.set(0, 32, 54);

      renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: false });
      renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
      renderer.setSize(width, height);
      renderer.shadowMap.enabled = true;

      if (typeof THREE.OrbitControls !== 'undefined') {
        controls = new THREE.OrbitControls(camera, renderer.domElement);
        controls.enableDamping = true;
        controls.dampingFactor = 0.06;
        controls.maxPolarAngle = Math.PI / 2 - 0.02; // Don't go below floor
        controls.minDistance = 8;
        controls.maxDistance = 180;
      }

      // Dynamic Holographic Lights
      const ambientLight = new THREE.AmbientLight(0x0f172a, 1.8);
      scene.add(ambientLight);

      const dirLight = new THREE.DirectionalLight(0x38bdf8, 1.5);
      dirLight.position.set(25, 50, 30);
      scene.add(dirLight);

      const floorLight = new THREE.DirectionalLight(0x10b981, 0.8);
      floorLight.position.set(-25, -20, -30);
      scene.add(floorLight);

      // Cyber Grid Floor
      const gridHelper = new THREE.GridHelper(260, 65, 0x0284c7, 0x1e293b);
      gridHelper.position.y = -0.05;
      scene.add(gridHelper);

      // Raycaster for mouse clicks & hover
      const raycaster = new THREE.Raycaster();
      const mouse = new THREE.Vector2();

      window.addEventListener('click', (event) => {
        // Prevent clicking through HUD elements
        if (event.target.closest('.hud-header, .control-deck, .inspector-panel, .hud-footer')) return;

        mouse.x = (event.clientX / window.innerWidth) * 2 - 1;
        mouse.y = -(event.clientY / window.innerHeight) * 2 + 1;
        raycaster.setFromCamera(mouse, camera);

        const meshes = nodeObjects.map(n => n.mesh);
        const intersects = raycaster.intersectObjects(meshes, true);

        if (intersects.length > 0) {
          let hit = intersects[0].object;
          while (hit.parent && !hit.userData.stepData) {
            hit = hit.parent;
          }
          if (hit.userData && hit.userData.stepData) {
            selectNode(hit.userData.stepData.id);
            playSound('select');
          }
        }
      });

      window.addEventListener('resize', () => {
        camera.aspect = window.innerWidth / window.innerHeight;
        camera.updateProjectionMatrix();
        renderer.setSize(window.innerWidth, window.innerHeight);
      });

      animate();
    }

    // --- Node 3D Mesh Generator ---
    function create3DNode(stepData, x, z) {
      const group = new THREE.Group();
      group.userData = { stepData, targetX: x, targetZ: z };

      const cfg = STATE_CONFIGS[stepData.status] || STATE_CONFIGS.PENDING;

      // Outer Geometry based on status
      let geom;
      if (stepData.status === 'COMPLETED') {
        geom = new THREE.OctahedronGeometry(1.6, 0);
      } else if (stepData.status === 'IN_PROGRESS') {
        geom = new THREE.IcosahedronGeometry(1.8, 1);
      } else if (stepData.status === 'NEEDS_MORE_WORK') {
        geom = new THREE.DodecahedronGeometry(1.6, 0);
      } else if (stepData.status === 'FAILED') {
        geom = new THREE.TetrahedronGeometry(1.7, 0);
      } else {
        geom = new THREE.BoxGeometry(2.0, 2.0, 2.0);
      }

      // Material
      const mat = new THREE.MeshStandardMaterial({
        color: cfg.color,
        emissive: cfg.emissive,
        emissiveIntensity: stepData.status === 'IN_PROGRESS' ? 0.9 : 0.4,
        roughness: 0.25,
        metalness: 0.85,
        wireframe: false,
        transparent: true,
        opacity: stepData.status === 'PENDING' ? 0.55 : 0.95
      });

      const coreMesh = new THREE.Mesh(geom, mat);
      group.add(coreMesh);

      // Wireframe cage
      const wireMat = new THREE.MeshBasicMaterial({
        color: cfg.wireColor,
        wireframe: true,
        transparent: true,
        opacity: 0.6
      });
      const wireMesh = new THREE.Mesh(geom, wireMat);
      wireMesh.scale.set(1.08, 1.08, 1.08);
      group.add(wireMesh);

      // Orbiting Holographic Rings for Active / Completed nodes
      if (stepData.status === 'IN_PROGRESS' || stepData.status === 'COMPLETED') {
        const ringGeom = new THREE.TorusGeometry(2.6, 0.08, 8, 32);
        const ringMat = new THREE.MeshBasicMaterial({
          color: cfg.wireColor,
          transparent: true,
          opacity: 0.8
        });
        const ringMesh = new THREE.Mesh(ringGeom, ringMat);
        ringMesh.rotation.x = Math.PI / 2;
        group.add(ringMesh);
        group.userData.ring = ringMesh;

        if (stepData.status === 'IN_PROGRESS') {
          const ring2 = ringMesh.clone();
          ring2.rotation.y = Math.PI / 3;
          ring2.scale.set(1.2, 1.2, 1.2);
          group.add(ring2);
          group.userData.ring2 = ring2;
        }
      }

      // 3D Text Badge via Canvas Sprite
      const sprite = createTextSprite(stepData.substepCode || stepData.phase, cfg.wireColor);
      sprite.position.y = 3.2;
      group.add(sprite);

      group.position.set(x, cfg.height, z);
      scene.add(group);

      return { mesh: group, data: stepData, config: cfg, x, z };
    }

    function createTextSprite(text, colorHex) {
      const canvas = document.createElement('canvas');
      canvas.width = 256;
      canvas.height = 128;
      const ctx = canvas.getContext('2d');

      ctx.fillStyle = 'rgba(15, 23, 42, 0.85)';
      ctx.strokeStyle = '#' + (colorHex.toString(16).padStart(6, '0'));
      ctx.lineWidth = 4;
      ctx.beginPath();
      ctx.roundRect(10, 10, 236, 108, 16);
      ctx.fill();
      ctx.stroke();

      ctx.font = 'bold 44px "JetBrains Mono", monospace';
      ctx.fillStyle = '#ffffff';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(text, 128, 64);

      const texture = new THREE.CanvasTexture(canvas);
      const spriteMat = new THREE.SpriteMaterial({ map: texture, transparent: true });
      const sprite = new THREE.Sprite(spriteMat);
      sprite.scale.set(4, 2, 1);
      return sprite;
    }

    // --- Pipeline Conduit Laser Beams ---
    function buildPipelineConduits(features) {
      // Clear existing conduits
      for (const c of pipelineConduits) scene.remove(c);
      pipelineConduits = [];
      energyPulses = [];

      for (const feature of features) {
        const featureNodes = nodeObjects.filter(n => n.data.feature === feature);
        for (let i = 0; i < featureNodes.length - 1; i++) {
          const n1 = featureNodes[i];
          const n2 = featureNodes[i + 1];

          const p1 = new THREE.Vector3(n1.x, 0.6, n1.z);
          const p2 = new THREE.Vector3(n2.x, 0.6, n2.z);

          const distance = p1.distanceTo(p2);
          const tubeGeom = new THREE.CylinderGeometry(0.12, 0.12, distance, 8);
          
          let color = 0x334155;
          let opacity = 0.4;
          if (n1.data.status === 'COMPLETED' && n2.data.status === 'COMPLETED') {
            color = 0x10b981;
            opacity = 0.85;
          } else if (n1.data.status === 'COMPLETED' && n2.data.status === 'IN_PROGRESS') {
            color = 0x06b6d4;
            opacity = 0.95;
          }

          const tubeMat = new THREE.MeshBasicMaterial({
            color,
            transparent: true,
            opacity
          });

          const cylinder = new THREE.Mesh(tubeGeom, tubeMat);
          cylinder.position.copy(p1).lerp(p2, 0.5);
          cylinder.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), p2.clone().sub(p1).normalize());
          scene.add(cylinder);
          pipelineConduits.push(cylinder);

          // If conduit is active, add traveling energy laser pulse
          if (n1.data.status === 'COMPLETED' && (n2.data.status === 'IN_PROGRESS' || n2.data.status === 'COMPLETED')) {
            const pulseGeom = new THREE.SphereGeometry(0.35, 12, 12);
            const pulseMat = new THREE.MeshBasicMaterial({ color: 0x38bdf8 });
            const pulse = new THREE.Mesh(pulseGeom, pulseMat);
            scene.add(pulse);
            energyPulses.push({ mesh: pulse, start: p1, end: p2, progress: Math.random() });
          }
        }
      }
    }

    // --- Build Full 3D Scene from Plan ---
    function renderPlanTo3D(plan) {
      if (!scene) return;

      // Group steps by feature
      const features = [...new Set(plan.steps.map(s => s.feature))];

      // Update Filter UI
      const filterList = document.getElementById('feature-filter-list');
      if (filterList && filterList.children.length <= 1) {
        filterList.innerHTML = '<div class="filter-item active" onclick="filterByFeature(\\'ALL\\')">All Pipelines</div>';
        for (const f of features) {
          const item = document.createElement('div');
          item.className = 'filter-item';
          item.textContent = f;
          item.onclick = () => filterByFeature(f);
          filterList.appendChild(item);
        }
      }

      // Remove old 3D nodes
      for (const n of nodeObjects) scene.remove(n.mesh);
      nodeObjects = [];

      const xSpacing = 10.0;
      const zSpacing = 18.0;

      features.forEach((feature, fIdx) => {
        const featureSteps = plan.steps.filter(s => s.feature === feature);
        const z = (fIdx - (features.length - 1) / 2) * zSpacing;

        featureSteps.forEach((step, sIdx) => {
          const x = (sIdx - (featureSteps.length - 1) / 2) * xSpacing;
          const nodeObj = create3DNode(step, x, z);
          nodeObjects.push(nodeObj);

          // Detect status change for sound effect
          if (lastKnownStepStates[step.id] && lastKnownStepStates[step.id] !== step.status) {
            if (step.status === 'COMPLETED') playSound('complete');
            else if (step.status === 'FAILED') playSound('fail');
          }
          lastKnownStepStates[step.id] = step.status;
        });
      });

      buildPipelineConduits(features);
      updateFilterVisibility();

      // If a node was previously selected, refresh inspector
      if (selectedStepId) {
        selectNode(selectedStepId, false);
      }
    }

    function updateFilterVisibility() {
      for (const n of nodeObjects) {
        let matchFeature = (activeFilterFeature === 'ALL' || n.data.feature === activeFilterFeature);
        let matchPhase = (activeFilterPhase === 'ALL' || n.data.phase === activeFilterPhase || (n.data.substepCode && n.data.substepCode.startsWith(activeFilterPhase.replace('step', ''))));
        n.mesh.visible = matchFeature && matchPhase;
      }
    }

    function filterByFeature(featureName) {
      activeFilterFeature = featureName;
      document.querySelectorAll('#feature-filter-list .filter-item').forEach(el => {
        el.classList.toggle('active', el.textContent.trim() === (featureName === 'ALL' ? 'All Pipelines' : featureName));
      });
      updateFilterVisibility();
    }

    function filterByPhase(phaseName) {
      activeFilterPhase = phaseName;
      document.querySelectorAll('.filter-list .filter-item').forEach(el => {
        if (el.parentElement.previousElementSibling.textContent.includes('Phase')) {
          el.classList.toggle('active', el.getAttribute('onclick').includes(phaseName));
        }
      });
      updateFilterVisibility();
    }

    // --- Animation Loop ---
    let clock = new THREE.Clock();

    function animate() {
      requestAnimationFrame(animate);

      const delta = clock.getDelta();
      const elapsed = clock.getElapsedTime();

      if (controls) {
        controls.autoRotate = autoRotate;
        controls.update();
      }

      // Rotate nodes and rings dynamically
      for (const n of nodeObjects) {
        if (n.data.status === 'IN_PROGRESS') {
          n.mesh.children[0].rotation.y += delta * 1.5;
          n.mesh.children[0].rotation.x += delta * 0.8;
          n.mesh.position.y = n.config.height + Math.sin(elapsed * 4) * 0.3;
          if (n.mesh.userData.ring) n.mesh.userData.ring.rotation.z += delta * 2.2;
          if (n.mesh.userData.ring2) n.mesh.userData.ring2.rotation.x -= delta * 1.8;
        } else if (n.data.status === 'COMPLETED') {
          n.mesh.children[0].rotation.y += delta * 0.4;
          n.mesh.position.y = n.config.height + Math.sin(elapsed * 2 + n.x) * 0.12;
          if (n.mesh.userData.ring) n.mesh.userData.ring.rotation.z += delta * 0.6;
        } else if (n.data.status === 'NEEDS_MORE_WORK') {
          n.mesh.children[0].rotation.y += delta * 0.8;
          n.mesh.position.y = n.config.height + Math.sin(elapsed * 3) * 0.18;
        }
      }

      // Animate energy laser pulses along conduits
      for (const p of energyPulses) {
        p.progress = (p.progress + delta * 0.75) % 1.0;
        p.mesh.position.copy(p.start).lerp(p.end, p.progress);
        p.mesh.position.y += Math.sin(p.progress * Math.PI) * 0.4;
      }

      renderer.render(scene, camera);
    }

    // --- Camera Control Helpers ---
    function setCameraAngle(type) {
      if (!controls) return;
      if (type === 'iso') {
        flyCameraTo(new THREE.Vector3(30, 28, 42), new THREE.Vector3(0, 0, 0));
      } else if (type === 'top') {
        flyCameraTo(new THREE.Vector3(0, 65, 0.1), new THREE.Vector3(0, 0, 0));
      } else if (type === 'side') {
        flyCameraTo(new THREE.Vector3(-45, 12, 0), new THREE.Vector3(0, 0, 0));
      } else if (type === 'front') {
        flyCameraTo(new THREE.Vector3(0, 14, 55), new THREE.Vector3(0, 0, 0));
      }
    }

    function flyCameraTo(targetPos, lookAtPos) {
      const startPos = camera.position.clone();
      const startLookAt = controls.target.clone();
      let startTime = performance.now();
      const duration = 800; // ms

      function stepFly(now) {
        const t = Math.min((now - startTime) / duration, 1.0);
        const ease = t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t;

        camera.position.lerpVectors(startPos, targetPos, ease);
        controls.target.lerpVectors(startLookAt, lookAtPos, ease);

        if (t < 1.0) requestAnimationFrame(stepFly);
      }
      requestAnimationFrame(stepFly);
    }

    function focusActiveStep() {
      const activeNode = nodeObjects.find(n => n.data.status === 'IN_PROGRESS') ||
                         nodeObjects.find(n => n.data.status === 'NEEDS_MORE_WORK') ||
                         nodeObjects.find(n => n.data.status === 'PENDING');
      if (activeNode) {
        selectNode(activeNode.data.id);
        const targetCam = new THREE.Vector3(activeNode.x + 8, activeNode.mesh.position.y + 7, activeNode.z + 14);
        flyCameraTo(targetCam, new THREE.Vector3(activeNode.x, activeNode.mesh.position.y, activeNode.z));
      }
    }

    function selectNode(stepId, doFly = true) {
      selectedStepId = stepId;
      const step = currentPlan && currentPlan.steps ? currentPlan.steps.find(s => s.id === stepId) : null;
      if (!step) return;

      const panel = document.getElementById('inspector-panel');
      panel.classList.add('open');

      document.getElementById('insp-code').textContent = (step.substepCode || step.phase).toUpperCase();
      document.getElementById('insp-title').textContent = step.title;

      const statusBadge = document.getElementById('insp-status');
      statusBadge.className = 'status-badge ' + step.status;
      statusBadge.textContent = step.status;

      document.getElementById('insp-goal').textContent = step.goal || step.title;
      document.getElementById('insp-principles').textContent = step.principles || 'principle-always-compile';

      const handoff = step.lastHandoff;
      document.getElementById('insp-handoff').textContent = (handoff && handoff.summary) ? handoff.summary : 'No handoff recorded yet.';

      const files = (handoff && handoff.verifiedFiles && handoff.verifiedFiles.length) ? handoff.verifiedFiles.join('\\n') : 'none';
      document.getElementById('insp-files').textContent = files;

      const contUsed = step.continuationsUsed || 0;
      const maxCont = (currentPlan && currentPlan.maxContinuationsPerSubstep) || 3;
      let remainingText = \`Continuations: \${contUsed}/\${maxCont}\`;
      if (Array.isArray(step.remainingTodo) && step.remainingTodo.length) {
        remainingText += '\\n\\nNext Agent Tasks:\\n' + step.remainingTodo.map((t, idx) => \`\${idx + 1}. \${t}\`).join('\\n');
      }
      document.getElementById('insp-remaining').textContent = remainingText;

      // Golden Locks
      const locks = (currentPlan.goldenLocks || []).filter(g => g.feature === step.feature);
      const locksDiv = document.getElementById('group-golden-locks');
      if (locks.length > 0) {
        locksDiv.style.display = 'flex';
        document.getElementById('insp-locks').textContent = locks.map(g => \`\${g.path}\\n  ↳ SHA-256: \${g.sha256.slice(0, 18)}... (locked by \${g.lockedByStep})\`).join('\\n\\n');
      } else {
        locksDiv.style.display = 'none';
      }

      // Failure history
      const attemptsDiv = document.getElementById('group-attempts');
      if (Array.isArray(step.attemptHistory) && step.attemptHistory.length > 0) {
        attemptsDiv.style.display = 'flex';
        document.getElementById('insp-attempts').textContent = step.attemptHistory.map(a => \`Attempt \${a.attempt}: \${a.reason} [hash: \${a.errorHash}]\\n\${a.errorTail || ''}\`).join('\\n---\\n');
      } else {
        attemptsDiv.style.display = 'none';
      }

      if (doFly) {
        const nodeObj = nodeObjects.find(n => n.data.id === stepId);
        if (nodeObj) {
          const targetCam = new THREE.Vector3(nodeObj.x + 8, nodeObj.mesh.position.y + 7, nodeObj.z + 14);
          flyCameraTo(targetCam, new THREE.Vector3(nodeObj.x, nodeObj.mesh.position.y, nodeObj.z));
        }
      }
    }

    function closeInspector() {
      selectedStepId = null;
      document.getElementById('inspector-panel').classList.remove('open');
    }

    // --- State Ingestion & Stats Update ---
    function updateStatsAndUI(plan, profile) {
      currentPlan = plan;
      currentProfile = profile;

      if (profile && profile.targetStack && profile.targetStack.platform) {
        document.getElementById('hdr-target-platform').textContent = profile.targetStack.platform;
      }

      const counts = { COMPLETED: 0, IN_PROGRESS: 0, NEEDS_MORE_WORK: 0, PENDING: 0, FAILED: 0 };
      for (const s of plan.steps || []) {
        counts[s.status] = (counts[s.status] || 0) + 1;
      }

      document.getElementById('stat-completed').textContent = counts.COMPLETED;
      document.getElementById('stat-in-progress').textContent = counts.IN_PROGRESS;
      document.getElementById('stat-needs-work').textContent = counts.NEEDS_MORE_WORK;
      document.getElementById('stat-pending').textContent = counts.PENDING;

      const pillFailed = document.getElementById('pill-failed');
      if (counts.FAILED > 0) {
        pillFailed.style.display = 'flex';
        document.getElementById('stat-failed').textContent = counts.FAILED;
      } else {
        pillFailed.style.display = 'none';
      }

      const goldenLocksCount = (plan.goldenLocks || []).length;
      document.getElementById('lbl-locks-count').textContent = \`\${goldenLocksCount} locked\`;
      document.getElementById('lbl-max-cont').textContent = plan.maxContinuationsPerSubstep || 3;

      renderPlanTo3D(plan);
    }

    // --- Live Poller Engine ---
    async function fetchLatestPlan() {
      // 1. Try server endpoint first (http://localhost:3333/api/plan)
      try {
        const res = await fetch('/api/plan', { cache: 'no-store' });
        if (res.ok) {
          const data = await res.json();
          if (data && data.steps) {
            updateStatsAndUI(data, data.targetProfile || {});
            document.getElementById('lbl-live-status').textContent = 'LIVE SSE/HTTP STREAM';
            return;
          }
        }
      } catch (e) {
        // Fallback to static data file
      }

      // 2. Try static file fetch (.mstack/migration-plan.json or live-state.json)
      try {
        const res = await fetch('./live-state.json', { cache: 'no-store' });
        if (res.ok) {
          const data = await res.json();
          if (data && data.steps) {
            updateStatsAndUI(data, data.targetProfile || {});
            document.getElementById('lbl-live-status').textContent = 'LIVE FILE STREAM (1.5s)';
            return;
          }
        }
      } catch (e) {}

      // 3. Fallback to dynamically reloading <script src="./dashboard-data.js">
      reloadDynamicScriptTag();
    }

    function reloadDynamicScriptTag() {
      const oldScript = document.getElementById('mstack-data-script');
      if (oldScript) oldScript.remove();

      const newScript = document.createElement('script');
      newScript.id = 'mstack-data-script';
      newScript.src = './dashboard-data.js?_t=' + Date.now();
      newScript.onload = () => {
        if (window.__MSTACK_DATA__ && window.__MSTACK_DATA__.plan) {
          updateStatsAndUI(window.__MSTACK_DATA__.plan, window.__MSTACK_DATA__.targetProfile || {});
          document.getElementById('lbl-live-status').textContent = 'LIVE JSONP (1.5s)';
        }
      };
      document.body.appendChild(newScript);
    }

    // Buttons Wiring
    document.getElementById('btn-focus-active').onclick = focusActiveStep;
    document.getElementById('btn-reset-cam').onclick = () => setCameraAngle('iso');
    document.getElementById('btn-auto-rotate').onclick = function() {
      autoRotate = !autoRotate;
      this.classList.toggle('active', autoRotate);
    };
    document.getElementById('btn-audio').onclick = function() {
      initAudio();
      sfxEnabled = !sfxEnabled;
      this.textContent = sfxEnabled ? '🔊 SFX: On' : '🔇 SFX: Off';
      this.classList.toggle('active', sfxEnabled);
      if (sfxEnabled) playSound('select');
    };
    document.getElementById('btn-refresh').onclick = () => {
      fetchLatestPlan();
      playSound('select');
    };

    // Auto-poll loop
    window.addEventListener('DOMContentLoaded', () => {
      initThreeScene();

      // Check initial payload from script tag if already loaded
      if (window.__MSTACK_DATA__ && window.__MSTACK_DATA__.plan) {
        updateStatsAndUI(window.__MSTACK_DATA__.plan, window.__MSTACK_DATA__.targetProfile || {});
      } else {
        fetchLatestPlan();
      }

      setInterval(fetchLatestPlan, 1500);
    });
  </script>
</body>
</html>
`;
}

function generateDashboard(planFile = ".mstack/migration-plan.json") {
  const resolvedPlanFile = resolvePath(planFile);
  const targetProfileFile = resolvePath(".mstack/target-profile.json");
  const dashboardDir = resolvePath(".mstack/dashboard");

  fs.mkdirSync(dashboardDir, { recursive: true });

  const plan = loadJson(resolvedPlanFile, {
    version: "2.0",
    executionMode: "sequential-substep-handoff",
    steps: []
  });

  const targetProfile = loadJson(targetProfileFile, {
    projectType: "auto-detected",
    targetStack: { platform: "Kotlin Multiplatform (KMP) + Compose Multiplatform" }
  });

  // 1. Write index.html
  const htmlPath = path.join(dashboardDir, "index.html");
  fs.writeFileSync(htmlPath, generateDashboardHtml(), "utf8");

  // 2. Write dashboard-data.js (JSONP for file:// compatibility)
  const dataJsPath = path.join(dashboardDir, "dashboard-data.js");
  const dataPayload = {
    generatedAt: new Date().toISOString(),
    plan,
    targetProfile
  };
  fs.writeFileSync(
    dataJsPath,
    `window.__MSTACK_DATA__ = ${JSON.stringify(dataPayload, null, 2)};\n`,
    "utf8"
  );

  // 3. Write live-state.json (for fetch)
  const liveStateJsonPath = path.join(dashboardDir, "live-state.json");
  fs.writeFileSync(
    liveStateJsonPath,
    JSON.stringify({ ...plan, targetProfile, generatedAt: new Date().toISOString() }, null, 2) + "\n",
    "utf8"
  );

  return { htmlPath, dataJsPath, liveStateJsonPath, stepCount: (plan.steps || []).length };
}

if (require.main === module) {
  const args = process.argv.slice(2);
  const planArg = args[0] || ".mstack/migration-plan.json";
  const result = generateDashboard(planArg);
  console.log(`[mstack dashboard] Generated 3D Hologram Dashboard (${result.stepCount} steps) -> ${result.htmlPath}`);
}

module.exports = { generateDashboard, generateDashboardHtml };


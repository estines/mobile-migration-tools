#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");
const { spawnSync } = require("node:child_process");

const PKG_ROOT = path.resolve(__dirname, "..");
const pkgJson = JSON.parse(
  fs.readFileSync(path.join(PKG_ROOT, "package.json"), "utf8")
);

function printHelp() {
  console.log(`
${pkgJson.name} v${pkgJson.version} (mstack)
${pkgJson.description}

Usage:
  npx mobile-migration-tools [command] [options]
  npx github:estines/mobile-migration-tools [command] [options]

Commands:
  init, install             Install mobile-migration-tools (skills, scripts, rules) into the workspace (default)
  detect [dir]              Run the workspace baseline detector (detect-project.sh)
  compile-gate <args...>    Run the Universal Always-Compile gate (compile-gate.sh)
  log-evidence <args...>    Append an evidence row to .mstack/audit.tsv (log-evidence.sh)

Options for init/install:
  --target <dir>            Target project root directory (default: current working directory)
  --root-agents             Also append/create AGENTS.md in the project root
  -h, --help                Show this help message
  -v, --version             Show version number

Examples:
  npx github:estines/mobile-migration-tools
  npx mobile-migration-tools init --root-agents
  npx mobile-migration-tools detect
  npx skills add estines/mobile-migration-tools
`.trim());
}

function copyDirRecursive(src, dest, makeScriptsExecutable = false) {
  fs.mkdirSync(dest, { recursive: true });
  const entries = fs.readdirSync(src, { withFileTypes: true });
  for (const entry of entries) {
    const srcPath = path.join(src, entry.name);
    const destPath = path.join(dest, entry.name);
    if (entry.isDirectory()) {
      copyDirRecursive(srcPath, destPath, makeScriptsExecutable);
    } else if (entry.isFile()) {
      fs.copyFileSync(srcPath, destPath);
      if (makeScriptsExecutable && entry.name.endsWith(".sh")) {
        fs.chmodSync(destPath, 0o755);
      }
    }
  }
}

function updateSkillsJson(workspaceRoot) {
  const agentsDir = path.join(workspaceRoot, ".agents");
  const skillsJsonPath = path.join(agentsDir, "skills.json");
  const targetSkillEntry = "mobile-migration-tools/skills";

  fs.mkdirSync(agentsDir, { recursive: true });

  let data = { entries: [] };
  if (fs.existsSync(skillsJsonPath)) {
    try {
      const parsed = JSON.parse(fs.readFileSync(skillsJsonPath, "utf8"));
      if (parsed && Array.isArray(parsed.entries)) {
        data = parsed;
      }
    } catch {
      // Backup malformed file before overwriting
      fs.copyFileSync(skillsJsonPath, `${skillsJsonPath}.bak`);
    }
  }

  const exists = data.entries.some(
    (e) => e && (e.path === targetSkillEntry || e.path === `./${targetSkillEntry}`)
  );
  if (!exists) {
    data.entries.push({ path: targetSkillEntry });
  }

  fs.writeFileSync(skillsJsonPath, JSON.stringify(data, null, 2) + "\n", "utf8");
  return skillsJsonPath;
}

function installRules(workspaceRoot, withRootAgents) {
  const srcRule = path.join(PKG_ROOT, "rules", "AGENTS.md");
  const rulesDir = path.join(workspaceRoot, ".agents", "rules");
  fs.mkdirSync(rulesDir, { recursive: true });

  const destRule = path.join(rulesDir, "mstack.md");
  fs.copyFileSync(srcRule, destRule);

  const installedPaths = [destRule];

  if (withRootAgents) {
    const rootAgentsPath = path.join(workspaceRoot, "AGENTS.md");
    const ruleContent = fs.readFileSync(srcRule, "utf8");
    if (fs.existsSync(rootAgentsPath)) {
      const existing = fs.readFileSync(rootAgentsPath, "utf8");
      if (!existing.includes("Mobile Migration Tools (`mstack`)")) {
        fs.writeFileSync(
          rootAgentsPath,
          existing.trimEnd() + "\n\n---\n\n" + ruleContent,
          "utf8"
        );
      }
    } else {
      fs.writeFileSync(rootAgentsPath, ruleContent, "utf8");
    }
    installedPaths.push(rootAgentsPath);
  }

  return installedPaths;
}

function runInit(args) {
  let targetDir = process.cwd();
  let withRootAgents = false;

  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--target" && args[i + 1]) {
      targetDir = path.resolve(args[i + 1]);
      i++;
    } else if (args[i] === "--root-agents") {
      withRootAgents = true;
    }
  }

  const destToolkitDir = path.join(targetDir, "mobile-migration-tools");

  console.log(`\n🚀 Installing mobile-migration-tools (mstack) into: ${targetDir}`);

  // Copy toolkit directory unless running inside the package repository itself
  if (path.resolve(PKG_ROOT) !== path.resolve(destToolkitDir) && path.resolve(PKG_ROOT) !== path.resolve(targetDir)) {
    fs.mkdirSync(destToolkitDir, { recursive: true });
    copyDirRecursive(path.join(PKG_ROOT, "skills"), path.join(destToolkitDir, "skills"), false);
    copyDirRecursive(path.join(PKG_ROOT, "scripts"), path.join(destToolkitDir, "scripts"), true);
    copyDirRecursive(path.join(PKG_ROOT, "rules"), path.join(destToolkitDir, "rules"), false);

    for (const file of ["plugin.json", "README.md"]) {
      const srcFile = path.join(PKG_ROOT, file);
      if (fs.existsSync(srcFile)) {
        fs.copyFileSync(srcFile, path.join(destToolkitDir, file));
      }
    }
    console.log(`  ✔ Installed toolkit files -> ${path.relative(targetDir, destToolkitDir)}/`);
  } else {
    // Ensure scripts are executable even if run in-place
    const scriptsDir = path.join(PKG_ROOT, "scripts");
    for (const f of fs.readdirSync(scriptsDir)) {
      if (f.endsWith(".sh")) {
        fs.chmodSync(path.join(scriptsDir, f), 0o755);
      }
    }
    console.log(`  ✔ Verified toolkit files in-place`);
  }

  const skillsJsonPath = updateSkillsJson(targetDir);
  console.log(`  ✔ Mounted skills in -> ${path.relative(targetDir, skillsJsonPath)}`);

  const rulePaths = installRules(targetDir, withRootAgents);
  for (const rp of rulePaths) {
    console.log(`  ✔ Installed agent rules -> ${path.relative(targetDir, rp)}`);
  }

  console.log(`
✅ mstack installation complete!

Next steps in your AI Coding Agent (Antigravity / Cursor / Claude):
  1. First-time setup:
     "Set up mobile-migration-tools for this project."
  2. Migrate a feature or screen:
     "Use mstack to migrate <FeatureOrScreenName>."
  3. Build a new parallel feature:
     "Use mstack greenfield workflow to build <NewFeatureName>."
`);
}

function runShellScript(scriptName, scriptArgs) {
  const localScript = path.join(process.cwd(), "mobile-migration-tools", "scripts", scriptName);
  const bundledScript = path.join(PKG_ROOT, "scripts", scriptName);
  const scriptToRun = fs.existsSync(localScript) ? localScript : bundledScript;

  const result = spawnSync("bash", [scriptToRun, ...scriptArgs], {
    stdio: "inherit",
    cwd: process.cwd(),
  });
  process.exit(result.status ?? 1);
}

function main() {
  const args = process.argv.slice(2);
  const first = args[0];

  if (first === "-h" || first === "--help" || first === "help") {
    printHelp();
    return;
  }

  if (first === "-v" || first === "--version" || first === "version") {
    console.log(pkgJson.version);
    return;
  }

  if (!first || first === "init" || first === "install" || first.startsWith("--")) {
    const initArgs = first && first.startsWith("--") ? args : args.slice(1);
    runInit(initArgs);
    return;
  }

  if (first === "detect") {
    runShellScript("detect-project.sh", args.slice(1));
    return;
  }

  if (first === "compile-gate") {
    runShellScript("compile-gate.sh", args.slice(1));
    return;
  }

  if (first === "log-evidence") {
    runShellScript("log-evidence.sh", args.slice(1));
    return;
  }

  console.error(`Unknown command: ${first}\n`);
  printHelp();
  process.exit(1);
}

main();


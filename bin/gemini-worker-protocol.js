#!/usr/bin/env node

const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const packageRoot = path.resolve(__dirname, '..');
const skillSource = path.join(packageRoot, 'gemini-worker-protocol');
const installerPath = path.join(skillSource, 'scripts', 'Install-GeminiWorkerSkill.ps1');
const optInSnippetPath = path.join(skillSource, 'references', 'AGENTS.md.snippet.md');
const optInStartMarker = '<!-- >>> gemini-worker-protocol project opt-in >>> -->';
const optInEndMarker = '<!-- <<< gemini-worker-protocol project opt-in <<< -->';
const disabledGlobalStartMarker = '# >>> gemini-worker-protocol project-only >>>';
const disabledGlobalEndMarker = '# <<< gemini-worker-protocol project-only <<<';

function printHelp() {
  console.log(`Gemini Worker Protocol installer (Windows only)

Usage:
  npx gemini-worker-protocol
  npx gemini-worker-protocol install [options]
  npx gemini-worker-protocol init --project <project-path> [--force]

Install options:
  --force       Replace this protocol's previously installed skill, wrappers, and profile block.
  --no-worker   Install only the Codex skill; do not install gemini-worker.ps1 or gemini-worker-session.ps1.
  --no-profile  Do not add the gw and gws functions to the PowerShell profile.
  --no-path     Do not add the Scripts folder to the current user's PATH.
  --dry-run     Print the PowerShell command without making changes.

Init options:
  --project     Existing project folder to enable. Use . for the current project.
  --force       Replace this protocol's existing project skill only.

  --help, -h    Show this help.
`);
}

function fail(message) {
  console.error(`gemini-worker-protocol: ${message}`);
  process.exitCode = 1;
}

function tomlPath(filePath) {
  return filePath.replace(/\\/g, '/').replace(/"/g, '\\"');
}

function appendOnce(filePath, startMarker, endMarker, content) {
  const existing = fs.existsSync(filePath) ? fs.readFileSync(filePath, 'utf8') : '';
  if (existing.includes(startMarker)) return false;

  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  const separator = existing.length > 0 && !existing.endsWith('\n') ? '\n\n' : existing.length > 0 ? '\n' : '';
  fs.writeFileSync(filePath, `${existing}${separator}${startMarker}\n${content.trim()}\n${endMarker}\n`, 'utf8');
  return true;
}

function initProject(args) {
  const force = args.includes('--force');
  const projectIndex = args.indexOf('--project');
  const unknown = args.find((arg, index) => arg !== '--force' && arg !== '--project' && index !== projectIndex + 1);
  if (unknown || projectIndex === -1 || !args[projectIndex + 1]) {
    fail('init requires --project <project-path>. Run \'gemini-worker-protocol --help\'.');
    return;
  }

  const projectRoot = path.resolve(args[projectIndex + 1]);
  if (!fs.existsSync(projectRoot) || !fs.statSync(projectRoot).isDirectory()) {
    fail(`project directory does not exist: ${projectRoot}`);
    return;
  }
  if (!fs.existsSync(skillSource) || !fs.existsSync(optInSnippetPath)) {
    fail('the bundled skill files are missing from this npm package.');
    return;
  }

  const targetSkill = path.join(projectRoot, '.agents', 'skills', 'gemini-worker-protocol');
  if (fs.existsSync(targetSkill) && !force) {
    fail(`project skill already exists: ${targetSkill}. Use --force only to replace this protocol's project copy.`);
    return;
  }
  if (fs.existsSync(targetSkill)) fs.rmSync(targetSkill, { recursive: true, force: true });
  fs.mkdirSync(path.dirname(targetSkill), { recursive: true });
  fs.cpSync(skillSource, targetSkill, { recursive: true });

  const snippet = fs.readFileSync(optInSnippetPath, 'utf8');
  const agentsPath = path.join(projectRoot, 'AGENTS.md');
  appendOnce(agentsPath, optInStartMarker, optInEndMarker, snippet);

  const codexHome = process.env.CODEX_HOME || path.join(os.homedir(), '.codex');
  const globalSkillPath = path.join(codexHome, 'skills', 'gemini-worker-protocol', 'SKILL.md');
  const globalConfigPath = path.join(codexHome, 'config.toml');
  appendOnce(
    globalConfigPath,
    disabledGlobalStartMarker,
    disabledGlobalEndMarker,
    `[[skills.config]]\npath = "${tomlPath(globalSkillPath)}"\nenabled = false`,
  );

  console.log(`Project skill installed: ${targetSkill}`);
  console.log(`Project opt-in added: ${agentsPath}`);
  console.log('The global copy of this skill is disabled. Restart Codex, then open this project.');
}

function install(args) {
  if (process.platform !== 'win32') {
    fail('this installer supports Windows only. Copy the portable package and follow INSTALL.md on another platform.');
  } else if (!fs.existsSync(installerPath)) {
    fail(`packaged PowerShell installer was not found: ${installerPath}`);
  } else {
    const recognized = new Set(['--force', '--no-worker', '--no-profile', '--no-path', '--dry-run']);
    const unknown = args.find((arg) => !recognized.has(arg));
    if (unknown) {
      fail(`unknown option '${unknown}'. Run 'gemini-worker-protocol --help'.`);
    } else {
      const installerArgs = ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', installerPath];
      if (!args.includes('--no-worker')) installerArgs.push('-InstallWorker');
      if (!args.includes('--no-profile')) installerArgs.push('-AddGwToProfile');
      if (!args.includes('--no-path')) installerArgs.push('-AddScriptsToUserPath');
      if (args.includes('--force')) installerArgs.push('-Force');

      if (args.includes('--dry-run')) {
        console.log(`Would run: powershell.exe ${installerArgs.map((arg) => JSON.stringify(arg)).join(' ')}`);
      } else {
        const result = spawnSync('powershell.exe', installerArgs, { stdio: 'inherit' });
        if (result.error) {
          fail(`could not start PowerShell: ${result.error.message}`);
        } else if (result.status !== 0) {
          process.exitCode = result.status || 1;
        } else {
          console.log('Installation complete. Open a new PowerShell window, then run gw (one turn) or gws (streaming).');
        }
      }
    }
  }
}

const args = process.argv.slice(2);
const command = args[0] && !args[0].startsWith('-') ? args.shift() : 'install';

if (command === 'help' || args.includes('--help') || args.includes('-h')) {
  printHelp();
} else if (command === 'init') {
  initProject(args);
} else if (command === 'install') {
  install(args);
} else {
  fail(`unknown command '${command}'. Run 'gemini-worker-protocol --help'.`);
}

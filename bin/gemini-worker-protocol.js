#!/usr/bin/env node

const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const packageRoot = path.resolve(__dirname, '..');
const installerPath = path.join(packageRoot, 'gemini-worker-protocol', 'scripts', 'Install-GeminiWorkerSkill.ps1');

function printHelp() {
  console.log(`Gemini Worker Protocol installer (Windows only)

Usage:
  npx gemini-worker-protocol
  npx gemini-worker-protocol install [options]

Options:
  --force       Replace this protocol's previously installed skill, wrappers, and profile block.
  --no-worker   Install only the Codex skill; do not install gemini-worker.ps1 or gemini-worker-session.ps1.
  --no-profile  Do not add the gw and gws functions to the PowerShell profile.
  --no-path     Do not add the Scripts folder to the current user's PATH.
  --dry-run     Print the PowerShell command without making changes.
  --help, -h    Show this help.
`);
}

function fail(message) {
  console.error(`gemini-worker-protocol: ${message}`);
  process.exitCode = 1;
}

const args = process.argv.slice(2);
const command = args[0] && !args[0].startsWith('-') ? args.shift() : 'install';

if (command === 'help' || args.includes('--help') || args.includes('-h')) {
  printHelp();
} else if (command !== 'install') {
  fail(`unknown command '${command}'. Run 'gemini-worker-protocol --help'.`);
} else if (process.platform !== 'win32') {
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

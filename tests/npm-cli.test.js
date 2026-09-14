const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const repositoryRoot = path.resolve(__dirname, '..');
const cliPath = path.join(repositoryRoot, 'bin', 'gemini-worker-protocol.js');

function makeSandbox(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'gemini-worker-protocol-test-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const project = path.join(root, 'project');
  fs.mkdirSync(project);
  return {
    codexHome: path.join(root, 'codex-home'),
    project,
  };
}

function runCli(args, sandbox) {
  return spawnSync(process.execPath, [cliPath, ...args], {
    cwd: repositoryRoot,
    encoding: 'utf8',
    env: { ...process.env, CODEX_HOME: sandbox.codexHome },
  });
}

test('dry-run prints the PowerShell installer command without changing the machine', () => {
  const result = spawnSync(process.execPath, [cliPath, 'install', '--dry-run'], {
    cwd: repositoryRoot,
    encoding: 'utf8',
  });

  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /Install-GeminiWorkerSkill\.ps1/);
  assert.match(result.stdout, /-InstallWorker/);
  assert.match(result.stdout, /-AddGwToProfile/);
  assert.match(result.stdout, /-AddScriptsToUserPath/);
});

test('dry-run can omit optional installer actions', () => {
  const result = spawnSync(process.execPath, [cliPath, 'install', '--dry-run', '--no-profile', '--no-path', '--no-worker'], {
    cwd: repositoryRoot,
    encoding: 'utf8',
  });

  assert.equal(result.status, 0, result.stderr);
  assert.doesNotMatch(result.stdout, /-InstallWorker/);
  assert.doesNotMatch(result.stdout, /-AddGwToProfile/);
  assert.doesNotMatch(result.stdout, /-AddScriptsToUserPath/);
});

test('init creates a project-scoped skill and project opt-in instructions', (t) => {
  const sandbox = makeSandbox(t);
  const result = runCli(['init', '--project', sandbox.project], sandbox);
  const skillPath = path.join(sandbox.project, '.agents', 'skills', 'gemini-worker-protocol', 'SKILL.md');
  const agentsPath = path.join(sandbox.project, 'AGENTS.md');

  assert.equal(result.status, 0, result.stderr);
  assert.ok(fs.existsSync(skillPath));
  assert.match(fs.readFileSync(agentsPath, 'utf8'), /This project may use the `gemini-worker-protocol` skill/);
});

test('init disables the global copy of this skill', (t) => {
  const sandbox = makeSandbox(t);
  const result = runCli(['init', '--project', sandbox.project], sandbox);
  const configPath = path.join(sandbox.codexHome, 'config.toml');

  assert.equal(result.status, 0, result.stderr);
  assert.match(fs.readFileSync(configPath, 'utf8'), /enabled = false/);
  assert.match(fs.readFileSync(configPath, 'utf8'), /gemini-worker-protocol\/SKILL\.md/);
});

test('init refuses to overwrite an existing project skill without --force', (t) => {
  const sandbox = makeSandbox(t);
  const target = path.join(sandbox.project, '.agents', 'skills', 'gemini-worker-protocol');
  fs.mkdirSync(target, { recursive: true });
  fs.writeFileSync(path.join(target, 'SKILL.md'), 'keep this skill');

  const result = runCli(['init', '--project', sandbox.project], sandbox);

  assert.equal(result.status, 1);
  assert.equal(fs.readFileSync(path.join(target, 'SKILL.md'), 'utf8'), 'keep this skill');
  assert.match(result.stderr, /already exists/);
});

const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const path = require('node:path');
const test = require('node:test');

const repositoryRoot = path.resolve(__dirname, '..');
const cliPath = path.join(repositoryRoot, 'bin', 'gemini-worker-protocol.js');

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

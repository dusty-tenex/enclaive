# Developer Tooling Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build three developer-facing tools (Dev Container config, CLI, VS Code extension) that make the claude-sandbox transparent and easy to use.

**Architecture:** Phase 1 creates `.devcontainer/` config pointing at existing `docker-compose.yml`. Phase 2 creates a Node.js CLI in `cli/` that wraps docker compose with rich output and JSONL parsing. Phase 3 creates a VS Code extension in `vscode-extension/` with status bar, notifications, and log viewer. Each phase is independently useful. No modifications to existing scripts or sidecar.

**Tech Stack:** Node.js (CLI: commander, chalk, ora, execa), TypeScript (VS Code extension: @types/vscode, esbuild)

---

## Phase 1: Dev Container Configuration

### Task 1: Create devcontainer.json

**Files:**
- Create: `.devcontainer/devcontainer.json`

**Step 1: Create the devcontainer config**

```jsonc
{
  "name": "Claude Code Secure Sandbox",
  "dockerComposeFile": "../docker-compose.yml",
  "service": "sandbox",
  "workspaceFolder": "/workspace",
  "overrideCommand": true,
  "shutdownAction": "stopCompose",
  "forwardPorts": [8000],
  "portsAttributes": {
    "8000": {
      "label": "Guardrails Sidecar",
      "onAutoForward": "silent"
    }
  },
  "customizations": {
    "vscode": {
      "extensions": [
        "tenexai.claude-sandbox"
      ],
      "settings": {
        "terminal.integrated.defaultProfile.linux": "bash",
        "claude-sandbox.sidecarUrl": "http://guardrails-sidecar:8000",
        "claude-sandbox.auditLogPath": ".audit-logs/security-guard.jsonl"
      }
    }
  },
  "postCreateCommand": "bash .devcontainer/postCreate.sh",
  "remoteUser": "sandbox"
}
```

**Step 2: Commit**

```bash
git add .devcontainer/devcontainer.json
git commit -m "feat: add devcontainer.json for VS Code Dev Containers"
```

---

### Task 2: Create postCreate.sh

**Files:**
- Create: `.devcontainer/postCreate.sh`

**Step 1: Write the post-create script**

```bash
#!/bin/bash
# Post-create script for Dev Containers.
# Runs after container build — verifies sidecar and prints status.
set -euo pipefail

SIDECAR="${GUARDRAILS_SIDECAR_URL:-http://guardrails-sidecar:8000}"

echo "--- Claude Code Secure Sandbox ---"
echo ""

# Check sidecar health
if curl -sf "${SIDECAR}/health" >/dev/null 2>&1; then
    echo "[OK] Sidecar healthy at ${SIDECAR}"
else
    echo "[WARN] Sidecar not reachable at ${SIDECAR} -- using inline fallback"
fi

# Count active hooks
if [ -f .claude/settings.json ]; then
    HOOK_COUNT=$(python3 -c "
import json, sys
try:
    s = json.load(open('.claude/settings.json'))
    hooks = s.get('hooks', {})
    count = sum(len(h) for matchers in hooks.values() for h in matchers for _ in h.get('hooks', []))
    print(count)
except: print('?')
" 2>/dev/null || echo "?")
    echo "[OK] ${HOOK_COUNT} security hooks active"
else
    echo "[WARN] .claude/settings.json not found"
fi

# Count scripts
SCRIPT_COUNT=$(ls scripts/*.sh 2>/dev/null | wc -l | tr -d ' ')
echo "[OK] ${SCRIPT_COUNT} guard scripts installed"

echo ""
echo "Run: claude"
echo ""
```

**Step 2: Make executable and commit**

```bash
chmod +x .devcontainer/postCreate.sh
git add .devcontainer/postCreate.sh
git commit -m "feat: add postCreate.sh for Dev Container setup verification"
```

---

## Phase 2: CLI Tool

### Task 3: Scaffold CLI package

**Files:**
- Create: `cli/package.json`
- Create: `cli/bin/claude-sandbox.js`
- Create: `cli/.eslintrc.json`

**Step 1: Create package.json**

```json
{
  "name": "@tenexai/claude-sandbox",
  "version": "0.1.0",
  "description": "CLI tool for Claude Code Secure Sandbox",
  "bin": {
    "claude-sandbox": "./bin/claude-sandbox.js"
  },
  "engines": {
    "node": ">=18"
  },
  "scripts": {
    "test": "node --test tests/",
    "lint": "eslint src/ bin/"
  },
  "keywords": ["claude", "sandbox", "security", "guardrails"],
  "license": "MIT",
  "dependencies": {
    "chalk": "^5.3.0",
    "commander": "^12.1.0",
    "execa": "^9.5.0",
    "ora": "^8.1.0"
  },
  "devDependencies": {
    "eslint": "^9.0.0"
  },
  "type": "module"
}
```

**Step 2: Create bin entry point (stub)**

```js
#!/usr/bin/env node
// @tenexai/claude-sandbox CLI entry point
import { program } from 'commander';

program
  .name('claude-sandbox')
  .description('CLI tool for Claude Code Secure Sandbox')
  .version('0.1.0');

program.parse();
```

**Step 3: Install dependencies**

```bash
cd cli && npm install
```

**Step 4: Verify it runs**

```bash
cd cli && node bin/claude-sandbox.js --help
```

Expected: Shows help text with name and description.

**Step 5: Commit**

```bash
git add cli/package.json cli/bin/claude-sandbox.js cli/package-lock.json
git commit -m "feat(cli): scaffold CLI package with commander"
```

---

### Task 4: Docker compose wrapper module

**Files:**
- Create: `cli/src/docker.js`
- Create: `cli/tests/docker.test.js`

**Step 1: Write the test**

```js
import { describe, it, mock } from 'node:test';
import assert from 'node:assert/strict';

// We test the helper functions that don't require docker
import { findComposeFile, parseComposeFile } from '../src/docker.js';
import { writeFileSync, mkdirSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

describe('findComposeFile', () => {
  const tmp = join(tmpdir(), 'claude-sandbox-test-' + Date.now());

  it('finds docker-compose.yml in given directory', () => {
    mkdirSync(tmp, { recursive: true });
    writeFileSync(join(tmp, 'docker-compose.yml'), 'services:\n  sandbox:\n    image: test\n');
    const result = findComposeFile(tmp);
    assert.ok(result);
    assert.ok(result.endsWith('docker-compose.yml'));
    rmSync(tmp, { recursive: true });
  });

  it('returns null when no compose file exists', () => {
    const empty = join(tmpdir(), 'empty-' + Date.now());
    mkdirSync(empty, { recursive: true });
    const result = findComposeFile(empty);
    assert.equal(result, null);
    rmSync(empty, { recursive: true });
  });
});
```

**Step 2: Run test to verify it fails**

```bash
cd cli && node --test tests/docker.test.js
```

Expected: FAIL — module not found.

**Step 3: Write docker.js**

```js
// Docker compose wrapper — shared by all commands
import { execa } from 'execa';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

/**
 * Find docker-compose.yml in the given directory.
 * Returns absolute path or null.
 */
export function findComposeFile(dir = process.cwd()) {
  for (const name of ['docker-compose.yml', 'docker-compose.yaml', 'compose.yml', 'compose.yaml']) {
    const p = join(dir, name);
    if (existsSync(p)) return p;
  }
  return null;
}

/**
 * Run a docker compose command. Streams output to stdout/stderr.
 * Returns the execa result.
 */
export async function compose(args, opts = {}) {
  const composeFile = findComposeFile(opts.cwd);
  const baseArgs = composeFile ? ['-f', composeFile, ...args] : args;

  return execa('docker', ['compose', ...baseArgs], {
    cwd: opts.cwd || process.cwd(),
    stdio: opts.stdio || 'inherit',
    reject: opts.reject !== undefined ? opts.reject : true,
  });
}

/**
 * Run a command inside the sandbox container.
 */
export async function execInSandbox(command, opts = {}) {
  const args = ['exec'];
  if (opts.interactive !== false) args.push('-it');
  args.push('sandbox', ...command);
  return compose(args, opts);
}

/**
 * Check if containers are running. Returns { sandbox, sidecar } booleans.
 */
export async function containerStatus(opts = {}) {
  try {
    const result = await compose(['ps', '--format', 'json'], {
      ...opts,
      stdio: 'pipe',
      reject: false,
    });
    const lines = result.stdout.trim().split('\n').filter(Boolean);
    const containers = lines.map(l => {
      try { return JSON.parse(l); } catch { return null; }
    }).filter(Boolean);

    return {
      sandbox: containers.some(c => c.Service === 'sandbox' && c.State === 'running'),
      sidecar: containers.some(c => c.Service === 'guardrails-sidecar' && c.State === 'running'),
      raw: containers,
    };
  } catch {
    return { sandbox: false, sidecar: false, raw: [] };
  }
}
```

**Step 4: Run test to verify it passes**

```bash
cd cli && node --test tests/docker.test.js
```

Expected: PASS

**Step 5: Commit**

```bash
git add cli/src/docker.js cli/tests/docker.test.js
git commit -m "feat(cli): add docker compose wrapper module"
```

---

### Task 5: Audit log parser module

**Files:**
- Create: `cli/src/logs.js`
- Create: `cli/tests/logs.test.js`

**Step 1: Write the test**

```js
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { parseLogLine, formatLogLine, filterLogs } from '../src/logs.js';

const SAMPLE_LINE = '{"timestamp": "2026-03-07T23:35:04Z", "mode": "memory", "file": "CLAUDE.md", "tool": "Write", "action": "BLOCKED", "reason": "Instruction override", "engine": "standalone"}';

describe('parseLogLine', () => {
  it('parses valid JSONL line', () => {
    const entry = parseLogLine(SAMPLE_LINE);
    assert.equal(entry.mode, 'memory');
    assert.equal(entry.action, 'BLOCKED');
    assert.equal(entry.file, 'CLAUDE.md');
  });

  it('returns null for invalid JSON', () => {
    assert.equal(parseLogLine('not json'), null);
    assert.equal(parseLogLine(''), null);
  });
});

describe('formatLogLine', () => {
  it('formats a log entry for display', () => {
    const entry = parseLogLine(SAMPLE_LINE);
    const formatted = formatLogLine(entry, { color: false });
    assert.ok(formatted.includes('BLOCKED'));
    assert.ok(formatted.includes('memory'));
    assert.ok(formatted.includes('CLAUDE.md'));
    assert.ok(formatted.includes('Instruction override'));
  });
});

describe('filterLogs', () => {
  it('filters by mode', () => {
    const entries = [
      { mode: 'memory', action: 'BLOCKED' },
      { mode: 'exfil', action: 'BLOCKED' },
      { mode: 'memory', action: 'BLOCKED' },
    ];
    const filtered = filterLogs(entries, { mode: 'memory' });
    assert.equal(filtered.length, 2);
  });

  it('returns all when no filter', () => {
    const entries = [
      { mode: 'memory', action: 'BLOCKED' },
      { mode: 'exfil', action: 'BLOCKED' },
    ];
    assert.equal(filterLogs(entries).length, 2);
  });
});
```

**Step 2: Run test to verify it fails**

```bash
cd cli && node --test tests/logs.test.js
```

Expected: FAIL

**Step 3: Write logs.js**

```js
// Audit log parser and formatter
import { createReadStream, existsSync, readFileSync, watch } from 'node:fs';
import { createInterface } from 'node:readline';
import chalk from 'chalk';

/**
 * Parse a single JSONL line into a log entry.
 */
export function parseLogLine(line) {
  if (!line || !line.trim()) return null;
  try {
    return JSON.parse(line.trim());
  } catch {
    return null;
  }
}

/**
 * Format a log entry for terminal display.
 * opts.color: boolean (default true)
 */
export function formatLogLine(entry, opts = {}) {
  const useColor = opts.color !== false;
  const time = entry.timestamp ? entry.timestamp.replace(/.*T/, '').replace('Z', '') : '??:??:??';
  const mode = (entry.mode || '?').padEnd(7);
  const file = entry.file || entry.tool || '?';
  const reason = entry.reason || '';
  const engine = entry.engine || '';

  if (useColor) {
    return `${chalk.dim(`[${time}]`)} ${chalk.red('BLOCKED')} ${chalk.yellow(mode)} ${chalk.white(file)}\n${' '.repeat(11)}Reason: ${reason}${engine ? chalk.dim(` (${engine})`) : ''}`;
  }
  return `[${time}] BLOCKED ${mode} ${file}\n           Reason: ${reason}${engine ? ` (${engine})` : ''}`;
}

/**
 * Filter log entries by mode.
 */
export function filterLogs(entries, opts = {}) {
  if (!opts.mode) return entries;
  return entries.filter(e => e.mode === opts.mode);
}

/**
 * Read all entries from an audit log file.
 */
export function readLogFile(logPath) {
  if (!existsSync(logPath)) return [];
  const content = readFileSync(logPath, 'utf-8');
  return content.split('\n').map(parseLogLine).filter(Boolean);
}

/**
 * Count blocks by mode from log entries.
 */
export function countByMode(entries) {
  const counts = {};
  for (const e of entries) {
    if (e.action === 'BLOCKED') {
      counts[e.mode] = (counts[e.mode] || 0) + 1;
    }
  }
  return counts;
}

/**
 * Tail a log file, calling onEntry for each new line.
 * Returns a cleanup function.
 */
export function tailLog(logPath, onEntry) {
  if (!existsSync(logPath)) return () => {};

  let position = 0;
  const stat = readFileSync(logPath, 'utf-8');
  position = Buffer.byteLength(stat, 'utf-8');

  const watcher = watch(logPath, () => {
    const content = readFileSync(logPath, 'utf-8');
    const bytes = Buffer.byteLength(content, 'utf-8');
    if (bytes > position) {
      const newContent = content.slice(position);
      position = bytes;
      for (const line of newContent.split('\n')) {
        const entry = parseLogLine(line);
        if (entry) onEntry(entry);
      }
    }
  });

  return () => watcher.close();
}
```

**Step 4: Run tests**

```bash
cd cli && node --test tests/logs.test.js
```

Expected: PASS

**Step 5: Commit**

```bash
git add cli/src/logs.js cli/tests/logs.test.js
git commit -m "feat(cli): add audit log parser and formatter"
```

---

### Task 6: Status and doctor module

**Files:**
- Create: `cli/src/status.js`
- Create: `cli/tests/status.test.js`

**Step 1: Write the test**

```js
import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { formatBlockSummary, doctorChecks } from '../src/status.js';

describe('formatBlockSummary', () => {
  it('formats block counts by mode', () => {
    const counts = { memory: 3, exfil: 2, write: 1 };
    const summary = formatBlockSummary(counts);
    assert.ok(summary.includes('6'));  // total
    assert.ok(summary.includes('memory'));
    assert.ok(summary.includes('exfil'));
  });

  it('handles empty counts', () => {
    const summary = formatBlockSummary({});
    assert.ok(summary.includes('0'));
  });
});

describe('doctorChecks', () => {
  it('exports an array of check definitions', () => {
    assert.ok(Array.isArray(doctorChecks));
    assert.ok(doctorChecks.length >= 5);
    for (const check of doctorChecks) {
      assert.ok(check.name);
      assert.ok(typeof check.run === 'function');
    }
  });
});
```

**Step 2: Run test to verify it fails**

```bash
cd cli && node --test tests/status.test.js
```

**Step 3: Write status.js**

```js
// Status display and doctor diagnostics
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import chalk from 'chalk';
import { compose, containerStatus } from './docker.js';

/**
 * Format block count summary for display.
 */
export function formatBlockSummary(counts) {
  const total = Object.values(counts).reduce((a, b) => a + b, 0);
  if (total === 0) return `${total} blocks`;
  const parts = Object.entries(counts)
    .sort((a, b) => b[1] - a[1])
    .map(([mode, count]) => `${count} ${mode}`)
    .join(', ');
  return `${total} blocks (${parts})`;
}

/**
 * Check sidecar health. Returns { healthy, message }.
 */
export async function checkSidecarHealth(url = 'http://localhost:8000') {
  try {
    const resp = await fetch(`${url}/health`);
    if (resp.ok) return { healthy: true, message: 'Sidecar healthy' };
    return { healthy: false, message: `Sidecar returned ${resp.status}` };
  } catch (e) {
    return { healthy: false, message: `Sidecar unreachable at ${url}` };
  }
}

/**
 * Print full status to console.
 */
export async function printStatus(opts = {}) {
  const cwd = opts.cwd || process.cwd();
  const sidecarUrl = opts.sidecarUrl || 'http://localhost:8000';

  // Container status
  const containers = await containerStatus({ cwd });
  const sandboxState = containers.sandbox ? chalk.green('running') : chalk.red('stopped');
  const sidecarState = containers.sidecar ? chalk.green('running') : chalk.red('stopped');

  console.log('Sandbox Status');
  console.log(`  Containers:     sandbox ${sandboxState} | sidecar ${sidecarState}`);

  // Sidecar health
  if (containers.sidecar) {
    const health = await checkSidecarHealth(sidecarUrl);
    console.log(`  Sidecar:        ${health.healthy ? chalk.green('[OK]') : chalk.red('[FAIL]')} ${health.message}`);
  }

  // Block stats from audit log
  const logPath = join(cwd, '.audit-logs', 'security-guard.jsonl');
  if (existsSync(logPath)) {
    const { readLogFile, countByMode } = await import('./logs.js');
    const entries = readLogFile(logPath);
    const counts = countByMode(entries);
    console.log(`  Blocks:         ${formatBlockSummary(counts)}`);

    // Last block
    const blocked = entries.filter(e => e.action === 'BLOCKED');
    if (blocked.length > 0) {
      const last = blocked[blocked.length - 1];
      console.log(`  Last block:     ${last.mode} -- ${last.reason}`);
    }
  } else {
    console.log('  Blocks:         no audit log found');
  }
}

/**
 * Doctor check definitions. Each has { name, run() } where run returns { ok, message }.
 */
export const doctorChecks = [
  {
    name: 'Docker installed',
    async run() {
      try {
        const { execa } = await import('execa');
        const result = await execa('docker', ['--version'], { reject: false });
        if (result.exitCode === 0) {
          const version = result.stdout.match(/Docker version ([\d.]+)/)?.[1] || 'unknown';
          return { ok: true, message: `Docker installed (${version})` };
        }
        return { ok: false, message: 'Docker not found in PATH' };
      } catch {
        return { ok: false, message: 'Docker not found in PATH' };
      }
    },
  },
  {
    name: 'Docker Compose v2',
    async run() {
      try {
        const { execa } = await import('execa');
        const result = await execa('docker', ['compose', 'version'], { reject: false });
        if (result.exitCode === 0) return { ok: true, message: 'Docker Compose v2 available' };
        return { ok: false, message: 'Docker Compose v2 not available' };
      } catch {
        return { ok: false, message: 'Docker Compose v2 not available' };
      }
    },
  },
  {
    name: 'docker-compose.yml exists',
    async run({ cwd } = {}) {
      const { findComposeFile } = await import('./docker.js');
      const file = findComposeFile(cwd || process.cwd());
      if (file) return { ok: true, message: 'docker-compose.yml found' };
      return { ok: false, message: 'docker-compose.yml not found' };
    },
  },
  {
    name: '.env configured',
    async run({ cwd } = {}) {
      const dir = cwd || process.cwd();
      const envPath = join(dir, '.env');
      if (!existsSync(envPath)) return { ok: false, message: '.env file not found' };
      const content = readFileSync(envPath, 'utf-8');
      const hasKey = content.includes('ANTHROPIC_API_KEY') && !content.includes('ANTHROPIC_API_KEY=sk-ant-...');
      if (hasKey) return { ok: true, message: '.env configured (ANTHROPIC_API_KEY set)' };
      return { ok: false, message: 'ANTHROPIC_API_KEY not set in .env', warn: true };
    },
  },
  {
    name: 'GUARDRAILS_TOKEN set',
    async run({ cwd } = {}) {
      const dir = cwd || process.cwd();
      const envPath = join(dir, '.env');
      if (!existsSync(envPath)) return { ok: false, message: 'GUARDRAILS_TOKEN not set', warn: true };
      const content = readFileSync(envPath, 'utf-8');
      if (content.match(/^GUARDRAILS_TOKEN=(?!gdk-\.\.\.)\S+/m)) {
        return { ok: true, message: 'GUARDRAILS_TOKEN set' };
      }
      return { ok: false, message: 'GUARDRAILS_TOKEN not set -- Hub validators will not install', warn: true };
    },
  },
  {
    name: 'Sidecar health',
    async run({ sidecarUrl } = {}) {
      const url = sidecarUrl || 'http://localhost:8000';
      const health = await checkSidecarHealth(url);
      return { ok: health.healthy, message: health.message };
    },
  },
  {
    name: 'Hook scripts executable',
    async run({ cwd } = {}) {
      const { readdirSync, statSync } = await import('node:fs');
      const dir = cwd || process.cwd();
      const scriptsDir = join(dir, 'scripts');
      if (!existsSync(scriptsDir)) return { ok: false, message: 'scripts/ directory not found' };
      try {
        const scripts = readdirSync(scriptsDir).filter(f => f.endsWith('.sh'));
        const execCount = scripts.filter(f => {
          const mode = statSync(join(scriptsDir, f)).mode;
          return (mode & 0o111) !== 0;
        }).length;
        if (execCount === scripts.length) return { ok: true, message: `Hook scripts executable (${scripts.length} scripts)` };
        return { ok: false, message: `${scripts.length - execCount}/${scripts.length} scripts not executable` };
      } catch {
        return { ok: false, message: 'Could not read scripts/' };
      }
    },
  },
  {
    name: 'settings.json valid',
    async run({ cwd } = {}) {
      const dir = cwd || process.cwd();
      const settingsPath = join(dir, '.claude', 'settings.json');
      if (!existsSync(settingsPath)) return { ok: false, message: '.claude/settings.json not found' };
      try {
        const settings = JSON.parse(readFileSync(settingsPath, 'utf-8'));
        const hooks = settings.hooks || {};
        const hookCount = Object.values(hooks)
          .flatMap(matchers => matchers)
          .flatMap(m => m.hooks || [])
          .length;
        return { ok: true, message: `settings.json valid (${hookCount} hooks)` };
      } catch {
        return { ok: false, message: 'settings.json is not valid JSON' };
      }
    },
  },
];

/**
 * Run all doctor checks and print results.
 */
export async function runDoctor(opts = {}) {
  let passed = 0;
  let warned = 0;
  let failed = 0;

  for (const check of doctorChecks) {
    const result = await check.run(opts);
    if (result.ok) {
      console.log(`  ${chalk.green('[OK]')}   ${result.message}`);
      passed++;
    } else if (result.warn) {
      console.log(`  ${chalk.yellow('[WARN]')} ${result.message}`);
      warned++;
    } else {
      console.log(`  ${chalk.red('[FAIL]')} ${result.message}`);
      failed++;
    }
  }

  const total = passed + warned + failed;
  console.log('');
  console.log(`  Summary: ${passed}/${total} passed${warned ? `, ${warned} warnings` : ''}${failed ? `, ${failed} failed` : ''}`);
  return { passed, warned, failed };
}
```

**Step 4: Run tests**

```bash
cd cli && node --test tests/status.test.js
```

Expected: PASS

**Step 5: Commit**

```bash
git add cli/src/status.js cli/tests/status.test.js
git commit -m "feat(cli): add status display and doctor diagnostics"
```

---

### Task 7: Init command

**Files:**
- Create: `cli/src/init.js`
- Create: `cli/templates/` (symlink or copy from project root)

**Step 1: Write init.js**

```js
// Project initialization — copies sandbox files into target directory
import { existsSync, mkdirSync, copyFileSync, readFileSync, writeFileSync, readdirSync, statSync } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import chalk from 'chalk';

const __dirname = dirname(fileURLToPath(import.meta.url));
const TEMPLATE_DIR = join(__dirname, '..', 'templates');

// Files that init copies from the claude-sandbox project root
const COPY_MAP = {
  'docker-compose.yml': 'docker-compose.yml',
  '.env.example': '.env.example',
  '.devcontainer/devcontainer.json': '.devcontainer/devcontainer.json',
  '.devcontainer/postCreate.sh': '.devcontainer/postCreate.sh',
};

// Directories to copy recursively
const COPY_DIRS = ['scripts', 'config'];

function copyDirRecursive(src, dest) {
  mkdirSync(dest, { recursive: true });
  for (const entry of readdirSync(src)) {
    const srcPath = join(src, entry);
    const destPath = join(dest, entry);
    if (statSync(srcPath).isDirectory()) {
      copyDirRecursive(srcPath, destPath);
    } else {
      copyFileSync(srcPath, destPath);
    }
  }
}

export async function initProject(targetDir) {
  const dir = resolve(targetDir || '.');

  if (!existsSync(dir)) {
    mkdirSync(dir, { recursive: true });
  }

  console.log(`[INFO] Initializing sandbox in ${dir}`);

  // Copy individual files
  let copied = 0;
  for (const [src, dest] of Object.entries(COPY_MAP)) {
    const srcPath = join(TEMPLATE_DIR, src);
    const destPath = join(dir, dest);
    if (!existsSync(srcPath)) {
      console.log(`  ${chalk.yellow('[WARN]')} Template not found: ${src}`);
      continue;
    }
    if (existsSync(destPath)) {
      console.log(`  ${chalk.dim('skip')}  ${dest} (already exists)`);
      continue;
    }
    mkdirSync(dirname(destPath), { recursive: true });
    copyFileSync(srcPath, destPath);
    console.log(`  ${chalk.green('[OK]')}   ${dest}`);
    copied++;
  }

  // Copy directories
  for (const dirName of COPY_DIRS) {
    const srcDir = join(TEMPLATE_DIR, dirName);
    const destDir = join(dir, dirName);
    if (!existsSync(srcDir)) {
      console.log(`  ${chalk.yellow('[WARN]')} Template dir not found: ${dirName}/`);
      continue;
    }
    if (existsSync(destDir)) {
      console.log(`  ${chalk.dim('skip')}  ${dirName}/ (already exists)`);
      continue;
    }
    copyDirRecursive(srcDir, destDir);
    console.log(`  ${chalk.green('[OK]')}   ${dirName}/`);
    copied++;
  }

  // Update .gitignore
  const gitignorePath = join(dir, '.gitignore');
  const ignoreEntries = ['.sandbox.json', '.audit-logs/', '.env', 'node_modules/'];
  let gitignore = existsSync(gitignorePath) ? readFileSync(gitignorePath, 'utf-8') : '';
  let added = 0;
  for (const entry of ignoreEntries) {
    if (!gitignore.includes(entry)) {
      gitignore += `${gitignore.endsWith('\n') ? '' : '\n'}${entry}\n`;
      added++;
    }
  }
  if (added > 0) {
    writeFileSync(gitignorePath, gitignore);
    console.log(`  ${chalk.green('[OK]')}   .gitignore updated (${added} entries)`);
  }

  console.log('');
  console.log(`[OK] Sandbox initialized in ${dir}`);
  console.log('');
  console.log('Next steps:');
  console.log(`  cd ${dir}`);
  console.log('  claude-sandbox up        # Start sandbox + sidecar');
  console.log('  claude-sandbox shell     # Enter sandbox');
  console.log('  claude                   # Run Claude Code');
}
```

**Step 2: Commit**

```bash
git add cli/src/init.js
git commit -m "feat(cli): add init command for project scaffolding"
```

---

### Task 8: Wire all commands in CLI entry point

**Files:**
- Modify: `cli/bin/claude-sandbox.js`

**Step 1: Wire all commands**

Replace the stub entry point with the full CLI:

```js
#!/usr/bin/env node
// @tenexai/claude-sandbox CLI
import { program } from 'commander';
import chalk from 'chalk';
import ora from 'ora';
import { compose, execInSandbox, containerStatus } from '../src/docker.js';
import { initProject } from '../src/init.js';
import { readLogFile, filterLogs, formatLogLine, countByMode, tailLog } from '../src/logs.js';
import { printStatus, runDoctor } from '../src/status.js';
import { join } from 'node:path';

program
  .name('claude-sandbox')
  .description('CLI tool for Claude Code Secure Sandbox')
  .version('0.1.0');

// ── init ─────────────────────────────────────────────────────
program
  .command('init [directory]')
  .description('Initialize sandbox in a project directory')
  .action(async (directory) => {
    await initProject(directory);
  });

// ── up ───────────────────────────────────────────────────────
program
  .command('up')
  .description('Start sandbox and sidecar')
  .action(async () => {
    const spinner = ora('[INFO] Starting containers...').start();
    try {
      await compose(['up', '-d', '--build'], { stdio: 'pipe' });
      spinner.succeed('[OK] Containers started');
    } catch (e) {
      spinner.fail('[FAIL] Failed to start containers');
      console.error(e.stderr || e.message);
      process.exit(1);
    }

    // Wait for sidecar health
    const healthSpinner = ora('[INFO] Waiting for sidecar...').start();
    let healthy = false;
    for (let i = 0; i < 30; i++) {
      try {
        const resp = await fetch('http://localhost:8000/health');
        if (resp.ok) { healthy = true; break; }
      } catch {}
      await new Promise(r => setTimeout(r, 1000));
    }

    if (healthy) {
      healthSpinner.succeed('[OK] Sidecar healthy');
    } else {
      healthSpinner.warn('[WARN] Sidecar not responding -- using inline fallback');
    }

    console.log('');
    console.log(`Run: ${chalk.bold('claude-sandbox shell')}`);
  });

// ── down ─────────────────────────────────────────────────────
program
  .command('down')
  .description('Stop sandbox and sidecar')
  .option('--clean', 'Also remove volumes')
  .action(async (opts) => {
    const args = ['down'];
    if (opts.clean) args.push('--volumes');
    await compose(args);
  });

// ── shell ────────────────────────────────────────────────────
program
  .command('shell')
  .description('Open a shell inside the sandbox')
  .action(async () => {
    try {
      await execInSandbox(['bash']);
    } catch (e) {
      if (e.exitCode !== 130) { // Ctrl-C is fine
        console.error(`${chalk.red('[FAIL]')} Could not connect to sandbox. Is it running?`);
        process.exit(1);
      }
    }
  });

// ── run ──────────────────────────────────────────────────────
program
  .command('run <command...>')
  .description('Run a command inside the sandbox')
  .action(async (command) => {
    try {
      await execInSandbox(command, { interactive: false });
    } catch (e) {
      process.exit(e.exitCode || 1);
    }
  });

// ── status ───────────────────────────────────────────────────
program
  .command('status')
  .description('Show sandbox and sidecar status')
  .action(async () => {
    await printStatus();
  });

// ── logs ─────────────────────────────────────────────────────
program
  .command('logs')
  .description('Show security guard audit log')
  .option('-f, --follow', 'Tail the log in real-time')
  .option('-m, --mode <mode>', 'Filter by guard mode (memory, exfil, write, inbound)')
  .option('-n, --lines <count>', 'Number of recent entries to show', '20')
  .action(async (opts) => {
    const logPath = join(process.cwd(), '.audit-logs', 'security-guard.jsonl');

    if (opts.follow) {
      // Print recent entries first
      const entries = filterLogs(readLogFile(logPath), { mode: opts.mode });
      const recent = entries.slice(-parseInt(opts.lines));
      for (const entry of recent) {
        console.log(formatLogLine(entry));
      }
      if (recent.length > 0) console.log(chalk.dim('--- live tail ---'));

      // Tail new entries
      tailLog(logPath, (entry) => {
        if (!opts.mode || entry.mode === opts.mode) {
          console.log(formatLogLine(entry));
        }
      });
      // Keep process alive
      await new Promise(() => {});
    } else {
      const entries = filterLogs(readLogFile(logPath), { mode: opts.mode });
      const recent = entries.slice(-parseInt(opts.lines));
      if (recent.length === 0) {
        console.log(chalk.dim('No blocks recorded.'));
        return;
      }
      for (const entry of recent) {
        console.log(formatLogLine(entry));
      }
    }
  });

// ── doctor ───────────────────────────────────────────────────
program
  .command('doctor')
  .description('Diagnose common issues')
  .action(async () => {
    console.log('Claude Sandbox Doctor');
    console.log('');
    const { failed } = await runDoctor();
    process.exit(failed > 0 ? 1 : 0);
  });

program.parse();
```

**Step 2: Verify all commands show in help**

```bash
cd cli && node bin/claude-sandbox.js --help
```

Expected: All 8 commands listed.

**Step 3: Run all tests**

```bash
cd cli && node --test tests/
```

Expected: All tests pass.

**Step 4: Commit**

```bash
git add cli/bin/claude-sandbox.js
git commit -m "feat(cli): wire all commands in CLI entry point"
```

---

### Task 9: Create CLI templates directory

**Files:**
- Create: `cli/templates/` (populated from project root files)
- Create: `cli/README.md`

**Step 1: Create templates by symlinking to project root**

Rather than duplicating files, the templates directory uses the actual project files. When packaging for npm, these get bundled.

```bash
mkdir -p cli/templates/.devcontainer cli/templates/scripts cli/templates/config
# Copy the essential files into templates
cp docker-compose.yml cli/templates/
cp .env.example cli/templates/
cp .devcontainer/devcontainer.json cli/templates/.devcontainer/
cp .devcontainer/postCreate.sh cli/templates/.devcontainer/
```

Note: For the `scripts/` and `config/` dirs, the init command copies from the project root. The templates dir holds files specific to the `init` scaffolding (compose, env, devcontainer). Scripts and config are copied from `../` relative to the CLI package when installed as part of the repo, or from templates when installed standalone.

Update `cli/src/init.js` to handle both cases: look in templates first, then fall back to project root.

**Step 2: Write CLI README**

```markdown
# @tenexai/claude-sandbox

CLI tool for Claude Code Secure Sandbox.

## Install

```bash
npm install -g @tenexai/claude-sandbox
```

Or use without installing:

```bash
npx @tenexai/claude-sandbox up
```

## Commands

| Command | Description |
|---------|-------------|
| `claude-sandbox init [dir]` | Initialize sandbox in a project |
| `claude-sandbox up` | Start sandbox + sidecar |
| `claude-sandbox down [--clean]` | Stop (optionally remove volumes) |
| `claude-sandbox shell` | Open shell in sandbox |
| `claude-sandbox run <cmd>` | Run command in sandbox |
| `claude-sandbox status` | Show status and block stats |
| `claude-sandbox logs [-f] [-m mode]` | View/tail audit log |
| `claude-sandbox doctor` | Diagnose issues |

## Output Style

All output uses plain text labels: `[OK]`, `[FAIL]`, `[WARN]`, `[INFO]`.
```

**Step 3: Commit**

```bash
git add cli/templates/ cli/README.md
git commit -m "feat(cli): add templates and README"
```

---

## Phase 3: VS Code Extension

### Task 10: Scaffold VS Code extension

**Files:**
- Create: `vscode-extension/package.json`
- Create: `vscode-extension/tsconfig.json`
- Create: `vscode-extension/esbuild.config.js`
- Create: `vscode-extension/.vscodeignore`
- Create: `vscode-extension/src/extension.ts`

**Step 1: Create package.json**

```json
{
  "name": "claude-sandbox",
  "displayName": "Claude Code Secure Sandbox",
  "description": "Security guard UI for Claude Code sandboxed environments",
  "version": "0.1.0",
  "publisher": "tenexai",
  "engines": {
    "vscode": "^1.85.0"
  },
  "categories": ["Other"],
  "activationEvents": [
    "workspaceContains:docker-compose.yml",
    "workspaceContains:.claude/settings.json"
  ],
  "main": "./out/extension.js",
  "contributes": {
    "commands": [
      { "command": "claude-sandbox.start", "title": "Claude Sandbox: Start" },
      { "command": "claude-sandbox.stop", "title": "Claude Sandbox: Stop" },
      { "command": "claude-sandbox.restartSidecar", "title": "Claude Sandbox: Restart Sidecar" },
      { "command": "claude-sandbox.showLog", "title": "Claude Sandbox: Show Security Log" },
      { "command": "claude-sandbox.doctor", "title": "Claude Sandbox: Run Doctor" },
      { "command": "claude-sandbox.openShell", "title": "Claude Sandbox: Open Shell" }
    ],
    "configuration": {
      "title": "Claude Sandbox",
      "properties": {
        "claude-sandbox.sidecarUrl": {
          "type": "string",
          "default": "http://localhost:8000",
          "description": "Guardrails sidecar endpoint URL"
        },
        "claude-sandbox.auditLogPath": {
          "type": "string",
          "default": ".audit-logs/security-guard.jsonl",
          "description": "Path to audit log (relative to workspace)"
        },
        "claude-sandbox.notifications.enabled": {
          "type": "boolean",
          "default": true,
          "description": "Show notifications when guards block actions"
        },
        "claude-sandbox.notifications.minInterval": {
          "type": "number",
          "default": 5000,
          "description": "Minimum milliseconds between notifications"
        },
        "claude-sandbox.statusBar.showBlockCount": {
          "type": "boolean",
          "default": true,
          "description": "Show block count in status bar"
        },
        "claude-sandbox.autoStart": {
          "type": "boolean",
          "default": false,
          "description": "Auto-start sandbox when workspace opens"
        }
      }
    }
  },
  "scripts": {
    "build": "node esbuild.config.js",
    "watch": "node esbuild.config.js --watch",
    "lint": "tsc --noEmit",
    "package": "vsce package"
  },
  "devDependencies": {
    "@types/node": "^20.0.0",
    "@types/vscode": "^1.85.0",
    "esbuild": "^0.24.0",
    "typescript": "^5.5.0"
  }
}
```

**Step 2: Create tsconfig.json**

```json
{
  "compilerOptions": {
    "module": "commonjs",
    "target": "ES2022",
    "lib": ["ES2022"],
    "outDir": "out",
    "rootDir": "src",
    "sourceMap": true,
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "declaration": true,
    "declarationMap": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules"]
}
```

**Step 3: Create esbuild.config.js**

```js
const esbuild = require('esbuild');

const watch = process.argv.includes('--watch');

const config = {
  entryPoints: ['src/extension.ts'],
  bundle: true,
  outfile: 'out/extension.js',
  external: ['vscode'],
  format: 'cjs',
  platform: 'node',
  target: 'node18',
  sourcemap: true,
  minify: !watch,
};

if (watch) {
  esbuild.context(config).then(ctx => ctx.watch());
} else {
  esbuild.build(config);
}
```

**Step 4: Create .vscodeignore**

```
src/**
node_modules/**
tsconfig.json
esbuild.config.js
.gitignore
```

**Step 5: Create extension.ts stub**

```typescript
import * as vscode from 'vscode';

export function activate(context: vscode.ExtensionContext) {
  console.log('Claude Sandbox extension activated');
}

export function deactivate() {}
```

**Step 6: Install deps and verify build**

```bash
cd vscode-extension && npm install && npm run build
```

**Step 7: Commit**

```bash
git add vscode-extension/
git commit -m "feat(vscode): scaffold VS Code extension"
```

---

### Task 11: Sidecar client

**Files:**
- Create: `vscode-extension/src/sidecarClient.ts`

**Step 1: Write sidecar client**

```typescript
import * as vscode from 'vscode';
import * as http from 'node:http';

export interface SidecarHealth {
  healthy: boolean;
  message: string;
}

export class SidecarClient {
  private url: string;

  constructor() {
    this.url = vscode.workspace.getConfiguration('claude-sandbox').get('sidecarUrl', 'http://localhost:8000');
  }

  async checkHealth(): Promise<SidecarHealth> {
    return new Promise((resolve) => {
      const timeout = setTimeout(() => {
        resolve({ healthy: false, message: 'Sidecar request timed out' });
      }, 5000);

      const req = http.get(`${this.url}/health`, (res) => {
        clearTimeout(timeout);
        if (res.statusCode === 200) {
          resolve({ healthy: true, message: 'Sidecar healthy' });
        } else {
          resolve({ healthy: false, message: `Sidecar returned ${res.statusCode}` });
        }
      });

      req.on('error', () => {
        clearTimeout(timeout);
        resolve({ healthy: false, message: `Sidecar unreachable at ${this.url}` });
      });
    });
  }

  refreshConfig() {
    this.url = vscode.workspace.getConfiguration('claude-sandbox').get('sidecarUrl', 'http://localhost:8000');
  }
}
```

**Step 2: Commit**

```bash
git add vscode-extension/src/sidecarClient.ts
git commit -m "feat(vscode): add sidecar health client"
```

---

### Task 12: Config helper

**Files:**
- Create: `vscode-extension/src/config.ts`

**Step 1: Write config helper**

```typescript
import * as vscode from 'vscode';
import * as path from 'node:path';

export function getConfig() {
  const config = vscode.workspace.getConfiguration('claude-sandbox');
  return {
    sidecarUrl: config.get<string>('sidecarUrl', 'http://localhost:8000'),
    auditLogPath: config.get<string>('auditLogPath', '.audit-logs/security-guard.jsonl'),
    notificationsEnabled: config.get<boolean>('notifications.enabled', true),
    notificationsMinInterval: config.get<number>('notifications.minInterval', 5000),
    showBlockCount: config.get<boolean>('statusBar.showBlockCount', true),
    autoStart: config.get<boolean>('autoStart', false),
  };
}

export function getAuditLogUri(): vscode.Uri | null {
  const folders = vscode.workspace.workspaceFolders;
  if (!folders || folders.length === 0) return null;
  const config = getConfig();
  return vscode.Uri.joinPath(folders[0].uri, config.auditLogPath);
}
```

**Step 2: Commit**

```bash
git add vscode-extension/src/config.ts
git commit -m "feat(vscode): add config helper"
```

---

### Task 13: Audit log watcher

**Files:**
- Create: `vscode-extension/src/auditLogWatcher.ts`

**Step 1: Write the watcher**

```typescript
import * as vscode from 'vscode';
import * as fs from 'node:fs';
import { getAuditLogUri } from './config';

export interface AuditEntry {
  timestamp: string;
  mode: string;
  file: string;
  tool: string;
  action: string;
  reason: string;
  engine: string;
}

export class AuditLogWatcher implements vscode.Disposable {
  private watcher: vscode.FileSystemWatcher | null = null;
  private lastSize = 0;
  private entries: AuditEntry[] = [];
  private readonly _onNewEntry = new vscode.EventEmitter<AuditEntry>();
  readonly onNewEntry = this._onNewEntry.event;

  start() {
    const logUri = getAuditLogUri();
    if (!logUri) return;

    const logPath = logUri.fsPath;

    // Read existing entries
    if (fs.existsSync(logPath)) {
      const content = fs.readFileSync(logPath, 'utf-8');
      this.lastSize = Buffer.byteLength(content, 'utf-8');
      this.entries = content.split('\n')
        .map(line => this.parseLine(line))
        .filter((e): e is AuditEntry => e !== null);
    }

    // Watch for changes
    const pattern = new vscode.RelativePattern(
      vscode.workspace.workspaceFolders![0],
      '.audit-logs/security-guard.jsonl'
    );
    this.watcher = vscode.workspace.createFileSystemWatcher(pattern);
    this.watcher.onDidChange(() => this.readNewEntries(logPath));
    this.watcher.onDidCreate(() => this.readNewEntries(logPath));
  }

  private readNewEntries(logPath: string) {
    if (!fs.existsSync(logPath)) return;
    const content = fs.readFileSync(logPath, 'utf-8');
    const currentSize = Buffer.byteLength(content, 'utf-8');

    if (currentSize > this.lastSize) {
      const newContent = content.slice(this.lastSize);
      this.lastSize = currentSize;

      for (const line of newContent.split('\n')) {
        const entry = this.parseLine(line);
        if (entry) {
          this.entries.push(entry);
          this._onNewEntry.fire(entry);
        }
      }
    }
  }

  private parseLine(line: string): AuditEntry | null {
    if (!line.trim()) return null;
    try {
      return JSON.parse(line.trim());
    } catch {
      return null;
    }
  }

  getEntries(): AuditEntry[] {
    return this.entries;
  }

  getBlockCount(): number {
    return this.entries.filter(e => e.action === 'BLOCKED').length;
  }

  getBlockCountToday(): number {
    const today = new Date().toISOString().split('T')[0];
    return this.entries.filter(e =>
      e.action === 'BLOCKED' && e.timestamp.startsWith(today)
    ).length;
  }

  getLastBlock(): AuditEntry | null {
    const blocked = this.entries.filter(e => e.action === 'BLOCKED');
    return blocked.length > 0 ? blocked[blocked.length - 1] : null;
  }

  dispose() {
    this.watcher?.dispose();
    this._onNewEntry.dispose();
  }
}
```

**Step 2: Commit**

```bash
git add vscode-extension/src/auditLogWatcher.ts
git commit -m "feat(vscode): add audit log file watcher"
```

---

### Task 14: Status bar

**Files:**
- Create: `vscode-extension/src/statusBar.ts`

**Step 1: Write status bar manager**

```typescript
import * as vscode from 'vscode';
import { SidecarClient } from './sidecarClient';
import { AuditLogWatcher } from './auditLogWatcher';
import { getConfig } from './config';

type SandboxState = 'off' | 'starting' | 'active' | 'sidecarDown';

export class StatusBarManager implements vscode.Disposable {
  private item: vscode.StatusBarItem;
  private state: SandboxState = 'off';
  private pollTimer: NodeJS.Timeout | null = null;

  constructor(
    private sidecar: SidecarClient,
    private logWatcher: AuditLogWatcher,
  ) {
    this.item = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 100);
    this.item.show();
    this.update();

    // Update on new blocks
    logWatcher.onNewEntry(() => this.update());
  }

  setState(state: SandboxState) {
    this.state = state;
    this.update();
  }

  startPolling(intervalMs = 10000) {
    this.stopPolling();
    this.pollTimer = setInterval(async () => {
      const health = await this.sidecar.checkHealth();
      if (health.healthy && this.state !== 'starting') {
        this.setState('active');
      } else if (!health.healthy && this.state === 'active') {
        this.setState('sidecarDown');
      }
    }, intervalMs);
  }

  stopPolling() {
    if (this.pollTimer) {
      clearInterval(this.pollTimer);
      this.pollTimer = null;
    }
  }

  private update() {
    const config = getConfig();
    const blockCount = this.logWatcher.getBlockCountToday();
    const lastBlock = this.logWatcher.getLastBlock();

    switch (this.state) {
      case 'off':
        this.item.text = '$(shield) Sandbox: Off';
        this.item.backgroundColor = undefined;
        this.item.color = new vscode.ThemeColor('disabledForeground');
        this.item.command = 'claude-sandbox.start';
        this.item.tooltip = 'Click to start Claude Code Secure Sandbox';
        break;

      case 'starting':
        this.item.text = '$(loading~spin) Sandbox: Starting...';
        this.item.backgroundColor = new vscode.ThemeColor('statusBarItem.warningBackground');
        this.item.color = undefined;
        this.item.command = undefined;
        this.item.tooltip = 'Starting containers...';
        break;

      case 'active': {
        const blockText = config.showBlockCount ? ` (${blockCount} blocks)` : '';
        this.item.text = `$(shield) Sandbox: Active${blockText}`;
        this.item.backgroundColor = undefined;
        this.item.color = new vscode.ThemeColor('testing.iconPassed');
        this.item.command = 'claude-sandbox.showLog';

        let tooltip = 'Claude Code Secure Sandbox\nSidecar: healthy';
        tooltip += `\nBlocks today: ${blockCount}`;
        if (lastBlock) {
          tooltip += `\nLast: ${lastBlock.mode} -- ${lastBlock.reason}`;
        }
        this.item.tooltip = tooltip;
        break;
      }

      case 'sidecarDown':
        this.item.text = '$(shield) Sandbox: Sidecar Down';
        this.item.backgroundColor = new vscode.ThemeColor('statusBarItem.errorBackground');
        this.item.color = undefined;
        this.item.command = 'claude-sandbox.doctor';
        this.item.tooltip = 'Sidecar not responding. Click to diagnose.';
        break;
    }
  }

  dispose() {
    this.stopPolling();
    this.item.dispose();
  }
}
```

**Step 2: Commit**

```bash
git add vscode-extension/src/statusBar.ts
git commit -m "feat(vscode): add status bar manager"
```

---

### Task 15: Notifications

**Files:**
- Create: `vscode-extension/src/notifications.ts`

**Step 1: Write notification handler**

```typescript
import * as vscode from 'vscode';
import { AuditEntry, AuditLogWatcher } from './auditLogWatcher';
import { getConfig } from './config';

export class NotificationHandler implements vscode.Disposable {
  private lastNotification = 0;
  private disposable: vscode.Disposable;

  constructor(private logWatcher: AuditLogWatcher) {
    this.disposable = logWatcher.onNewEntry((entry) => this.handleEntry(entry));
  }

  private async handleEntry(entry: AuditEntry) {
    if (entry.action !== 'BLOCKED') return;

    const config = getConfig();
    if (!config.notificationsEnabled) return;

    const now = Date.now();
    if (now - this.lastNotification < config.notificationsMinInterval) return;
    this.lastNotification = now;

    const msg = `[GUARD] ${entry.mode} guard blocked ${entry.file || entry.tool}: ${entry.reason}`;
    const action = await vscode.window.showWarningMessage(msg, 'View Log');
    if (action === 'View Log') {
      vscode.commands.executeCommand('claude-sandbox.showLog');
    }
  }

  dispose() {
    this.disposable.dispose();
  }
}
```

**Step 2: Commit**

```bash
git add vscode-extension/src/notifications.ts
git commit -m "feat(vscode): add block notification handler"
```

---

### Task 16: Commands and log output channel

**Files:**
- Create: `vscode-extension/src/commands.ts`

**Step 1: Write commands**

```typescript
import * as vscode from 'vscode';
import { AuditLogWatcher, AuditEntry } from './auditLogWatcher';
import { StatusBarManager } from './statusBar';

let outputChannel: vscode.OutputChannel | null = null;

function getOutputChannel(): vscode.OutputChannel {
  if (!outputChannel) {
    outputChannel = vscode.window.createOutputChannel('Security Guard');
  }
  return outputChannel;
}

function formatEntry(entry: AuditEntry): string {
  const time = entry.timestamp?.replace(/.*T/, '').replace('Z', '') || '??:??:??';
  const lines = [
    `[${time}] BLOCKED [${entry.mode}] ${entry.file || entry.tool || '?'}`,
    `           Reason: ${entry.reason || '?'}`,
    `           Engine: ${entry.engine || '?'}`,
  ];
  return lines.join('\n');
}

export function registerCommands(
  context: vscode.ExtensionContext,
  statusBar: StatusBarManager,
  logWatcher: AuditLogWatcher,
) {
  // Show Security Log
  context.subscriptions.push(
    vscode.commands.registerCommand('claude-sandbox.showLog', () => {
      const channel = getOutputChannel();
      channel.clear();

      // Print existing entries
      for (const entry of logWatcher.getEntries()) {
        if (entry.action === 'BLOCKED') {
          channel.appendLine(formatEntry(entry));
          channel.appendLine('');
        }
      }

      channel.show(true);
    })
  );

  // Stream new entries to output channel
  logWatcher.onNewEntry((entry) => {
    if (entry.action === 'BLOCKED' && outputChannel) {
      outputChannel.appendLine(formatEntry(entry));
      outputChannel.appendLine('');
    }
  });

  // Start
  context.subscriptions.push(
    vscode.commands.registerCommand('claude-sandbox.start', async () => {
      statusBar.setState('starting');
      const terminal = vscode.window.createTerminal({ name: 'Sandbox', hideFromUser: true });
      terminal.sendText('docker compose up -d');

      // Poll for sidecar health
      const { SidecarClient } = await import('./sidecarClient');
      const client = new SidecarClient();
      let healthy = false;
      for (let i = 0; i < 30; i++) {
        await new Promise(r => setTimeout(r, 1000));
        const result = await client.checkHealth();
        if (result.healthy) { healthy = true; break; }
      }

      if (healthy) {
        statusBar.setState('active');
        statusBar.startPolling();
        vscode.window.showInformationMessage('[OK] Sandbox started');
      } else {
        statusBar.setState('sidecarDown');
        vscode.window.showWarningMessage('[WARN] Sandbox started but sidecar not responding');
      }
      terminal.dispose();
    })
  );

  // Stop
  context.subscriptions.push(
    vscode.commands.registerCommand('claude-sandbox.stop', async () => {
      const terminal = vscode.window.createTerminal({ name: 'Sandbox', hideFromUser: true });
      terminal.sendText('docker compose down');
      statusBar.stopPolling();
      statusBar.setState('off');
      // Give compose time to stop, then clean up
      setTimeout(() => terminal.dispose(), 5000);
      vscode.window.showInformationMessage('[OK] Sandbox stopped');
    })
  );

  // Restart Sidecar
  context.subscriptions.push(
    vscode.commands.registerCommand('claude-sandbox.restartSidecar', async () => {
      const terminal = vscode.window.createTerminal({ name: 'Sandbox', hideFromUser: true });
      terminal.sendText('docker compose restart guardrails-sidecar');
      vscode.window.showInformationMessage('[INFO] Restarting sidecar...');
      setTimeout(() => terminal.dispose(), 10000);
    })
  );

  // Open Shell
  context.subscriptions.push(
    vscode.commands.registerCommand('claude-sandbox.openShell', () => {
      const terminal = vscode.window.createTerminal({ name: 'Sandbox Shell' });
      terminal.sendText('docker compose exec sandbox bash');
      terminal.show();
    })
  );

  // Doctor
  context.subscriptions.push(
    vscode.commands.registerCommand('claude-sandbox.doctor', () => {
      const terminal = vscode.window.createTerminal({ name: 'Sandbox Doctor' });
      terminal.sendText('npx @tenexai/claude-sandbox doctor');
      terminal.show();
    })
  );

  // Dispose output channel
  context.subscriptions.push({
    dispose: () => { outputChannel?.dispose(); outputChannel = null; },
  });
}
```

**Step 2: Commit**

```bash
git add vscode-extension/src/commands.ts
git commit -m "feat(vscode): add command palette commands and log output channel"
```

---

### Task 17: Wire extension activate/deactivate

**Files:**
- Modify: `vscode-extension/src/extension.ts`

**Step 1: Write full activation logic**

```typescript
import * as vscode from 'vscode';
import { SidecarClient } from './sidecarClient';
import { AuditLogWatcher } from './auditLogWatcher';
import { StatusBarManager } from './statusBar';
import { NotificationHandler } from './notifications';
import { registerCommands } from './commands';
import { getConfig } from './config';

export async function activate(context: vscode.ExtensionContext) {
  // Core components
  const sidecar = new SidecarClient();
  const logWatcher = new AuditLogWatcher();
  const statusBar = new StatusBarManager(sidecar, logWatcher);
  const notifications = new NotificationHandler(logWatcher);

  context.subscriptions.push(logWatcher, statusBar, notifications);

  // Register commands
  registerCommands(context, statusBar, logWatcher);

  // Refresh config on settings change
  context.subscriptions.push(
    vscode.workspace.onDidChangeConfiguration((e) => {
      if (e.affectsConfiguration('claude-sandbox')) {
        sidecar.refreshConfig();
      }
    })
  );

  // Check initial state
  const health = await sidecar.checkHealth();
  if (health.healthy) {
    statusBar.setState('active');
    statusBar.startPolling();
    logWatcher.start();
  } else {
    // Check if containers are running at all
    statusBar.setState('off');
    logWatcher.start(); // Start watching even if offline — picks up when started
  }

  // Auto-start if configured
  const config = getConfig();
  if (config.autoStart && !health.healthy) {
    vscode.commands.executeCommand('claude-sandbox.start');
  }
}

export function deactivate() {
  // All disposables are cleaned up via context.subscriptions
}
```

**Step 2: Build and verify**

```bash
cd vscode-extension && npm run build
```

Expected: Builds without errors, `out/extension.js` created.

**Step 3: Commit**

```bash
git add vscode-extension/src/extension.ts
git commit -m "feat(vscode): wire extension activation with all components"
```

---

### Task 18: Extension icons and final packaging

**Files:**
- Create: `vscode-extension/resources/icons/shield-active.svg`
- Create: `vscode-extension/resources/icons/shield-inactive.svg`
- Create: `vscode-extension/README.md`

**Step 1: Create shield icons (simple SVGs)**

shield-active.svg:
```svg
<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
  <path d="M8 1L2 3.5v4c0 3.5 2.6 6.4 6 7.5 3.4-1.1 6-4 6-7.5v-4L8 1z" fill="#4caf50" stroke="#388e3c" stroke-width="0.5"/>
  <path d="M6.5 8.5l1.5 1.5 3-3" fill="none" stroke="#fff" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
```

shield-inactive.svg:
```svg
<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 16 16">
  <path d="M8 1L2 3.5v4c0 3.5 2.6 6.4 6 7.5 3.4-1.1 6-4 6-7.5v-4L8 1z" fill="#9e9e9e" stroke="#757575" stroke-width="0.5"/>
</svg>
```

**Step 2: Write extension README**

```markdown
# Claude Code Secure Sandbox

VS Code extension for monitoring Claude Code's security sandbox.

## Features

- **Status Bar** — See sandbox state, sidecar health, and block count at a glance
- **Block Notifications** — Get alerted when security guards block an action
- **Security Log** — View all blocked actions in the Output panel
- **Command Palette** — Start, stop, restart, and diagnose from VS Code

## Commands

Open Command Palette (Cmd+Shift+P) and type "Claude Sandbox":

- **Start** — Start sandbox and sidecar containers
- **Stop** — Stop all containers
- **Restart Sidecar** — Restart the guardrails sidecar
- **Show Security Log** — Open the Security Guard output channel
- **Run Doctor** — Diagnose common issues
- **Open Shell** — Open terminal inside sandbox

## Settings

| Setting | Default | Description |
|---------|---------|-------------|
| `claude-sandbox.sidecarUrl` | `http://localhost:8000` | Sidecar endpoint |
| `claude-sandbox.auditLogPath` | `.audit-logs/security-guard.jsonl` | Audit log path |
| `claude-sandbox.notifications.enabled` | `true` | Show block notifications |
| `claude-sandbox.notifications.minInterval` | `5000` | Min ms between notifications |
| `claude-sandbox.statusBar.showBlockCount` | `true` | Show block count |
| `claude-sandbox.autoStart` | `false` | Auto-start on workspace open |
```

**Step 3: Build final extension**

```bash
cd vscode-extension && npm run build
```

**Step 4: Commit**

```bash
git add vscode-extension/resources/ vscode-extension/README.md
git commit -m "feat(vscode): add icons, README, and finalize extension"
```

---

### Task 19: Update project .gitignore and root README

**Files:**
- Modify: `.gitignore`
- Modify: `README.md`

**Step 1: Add new directories to .gitignore**

Append to `.gitignore`:
```
# CLI
cli/node_modules/

# VS Code Extension
vscode-extension/node_modules/
vscode-extension/out/
*.vsix
```

**Step 2: Update README.md**

Add a "Developer Tools" section to the existing README:

```markdown
## Developer Tools

### Dev Container (VS Code)

Open this project in VS Code and accept "Reopen in Container" to launch directly into the sandbox with all guards active.

### CLI

```bash
cd cli && npm install && npm link    # Install locally
claude-sandbox up                     # Start everything
claude-sandbox status                 # Check health + block stats
claude-sandbox logs --follow          # Tail security log
claude-sandbox doctor                 # Diagnose issues
```

### VS Code Extension

Install from `vscode-extension/`:

```bash
cd vscode-extension && npm install && npm run build
code --install-extension .            # Install locally
```

The extension adds a status bar item, block notifications, and security log viewer.
```

**Step 3: Commit**

```bash
git add .gitignore README.md
git commit -m "docs: update gitignore and README for developer tools"
```

---

### Task 20: Run all tests and final verification

**Step 1: Run CLI tests**

```bash
cd cli && node --test tests/
```

Expected: All tests pass.

**Step 2: Verify CLI help**

```bash
cd cli && node bin/claude-sandbox.js --help
```

Expected: All 8 commands listed.

**Step 3: Verify extension builds**

```bash
cd vscode-extension && npm run build
```

Expected: No errors, `out/extension.js` created.

**Step 4: Verify devcontainer.json is valid JSON**

```bash
python3 -c "import json; json.load(open('.devcontainer/devcontainer.json'))"
```

Expected: No errors.

**Step 5: Final commit (if any fixups needed)**

```bash
git add -A && git commit -m "chore: final verification fixes"
```

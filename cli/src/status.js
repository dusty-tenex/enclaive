import { containerStatus } from './docker.js';
import { readLogFile, countByMode } from './logs.js';
import { existsSync, readFileSync, accessSync, constants } from 'node:fs';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';

/**
 * Format a counts object as a human-readable summary.
 * e.g. "6 blocks (3 memory, 2 exfil, 1 write)"
 */
export function formatBlockSummary(counts) {
  const entries = Object.entries(counts);
  if (entries.length === 0) return '0 blocks';

  const total = entries.reduce((sum, [, v]) => sum + v, 0);
  const details = entries
    .sort((a, b) => b[1] - a[1])
    .map(([mode, count]) => `${count} ${mode}`)
    .join(', ');

  return `${total} blocks (${details})`;
}

/**
 * Check sidecar health endpoint.
 * Returns { healthy: bool, message: string }.
 */
export async function checkSidecarHealth(url) {
  try {
    const response = await fetch(url, { signal: AbortSignal.timeout(3000) });
    if (response.ok) {
      return { healthy: true, message: 'Sidecar is healthy' };
    }
    return { healthy: false, message: `Sidecar returned status ${response.status}` };
  } catch (err) {
    return { healthy: false, message: `Sidecar unreachable: ${err.message}` };
  }
}

/**
 * Print full status to the console.
 */
export async function printStatus(opts = {}) {
  const cwd = opts.cwd || process.cwd();
  const logPath = opts.logPath || join(cwd, '.audit-logs', 'security-guard.jsonl');
  const sidecarUrl = opts.sidecarUrl || 'http://localhost:8000/health-check';

  console.log('\n=== enclAIve Status ===\n');

  // Container status
  const status = await containerStatus({ cwd });
  const label = (running) => (running ? '[OK] running' : '[FAIL] not running');
  console.log(`  Sandbox:   ${label(status.sandbox)} (${status.sandboxName})`);
  console.log(`  Sidecar:   ${label(status.sidecar)}`);

  // Sidecar health
  const health = await checkSidecarHealth(sidecarUrl);
  console.log(`  Health:    ${health.healthy ? '[OK]' : '[FAIL]'} ${health.message}`);

  // Block stats
  const entries = readLogFile(logPath);
  const counts = countByMode(entries);
  console.log(`  Blocks:    ${formatBlockSummary(counts)}`);

  // Last block
  const blocked = entries.filter((e) => e.action === 'BLOCKED');
  if (blocked.length > 0) {
    const last = blocked[blocked.length - 1];
    console.log(`  Last:      ${last.timestamp} [${last.mode}] ${last.file}`);
  }

  console.log('');
}

/**
 * Array of doctor checks. Each has { name, run(opts) }.
 * run returns { ok: bool, message: string, warn?: bool }.
 */
export const doctorChecks = [
  {
    name: 'Docker installed',
    run: async () => {
      try {
        const out = execFileSync('docker', ['--version'], { encoding: 'utf-8', stdio: 'pipe' });
        const match = out.match(/Docker version ([\d.]+)/);
        if (match) {
          return { ok: true, message: `Docker ${match[1]}` };
        }
        return { ok: true, message: out.trim() };
      } catch {
        return { ok: false, message: 'Docker not found in PATH' };
      }
    },
  },
  {
    name: 'docker sandbox available',
    run: async () => {
      try {
        execFileSync('docker', ['sandbox', 'ls'], { encoding: 'utf-8', stdio: 'pipe' });
        return { ok: true, message: 'docker sandbox command available' };
      } catch {
        return { ok: false, message: 'docker sandbox not available (requires Docker Desktop 4.62+)' };
      }
    },
  },
  {
    name: 'Sidecar Dockerfile exists',
    run: async (opts = {}) => {
      const cwd = opts.cwd || process.cwd();
      const dockerfilePath = join(cwd, 'config', 'guardrails-server', 'Dockerfile');
      if (existsSync(dockerfilePath)) {
        return { ok: true, message: 'config/guardrails-server/Dockerfile found' };
      }
      return { ok: false, message: 'config/guardrails-server/Dockerfile not found' };
    },
  },
  {
    name: '.env configured',
    run: async (opts = {}) => {
      const cwd = opts.cwd || process.cwd();
      const envPath = join(cwd, '.env');
      if (!existsSync(envPath)) {
        return { ok: false, message: '.env file not found' };
      }
      try {
        const content = readFileSync(envPath, 'utf-8');
        if (!content.includes('ANTHROPIC_API_KEY')) {
          return { ok: false, message: 'ANTHROPIC_API_KEY not set in .env' };
        }
        if (
          content.includes('ANTHROPIC_API_KEY=your-') ||
          content.includes('ANTHROPIC_API_KEY=sk-placeholder')
        ) {
          return { ok: false, message: 'ANTHROPIC_API_KEY is still a placeholder' };
        }
        return { ok: true, message: 'ANTHROPIC_API_KEY configured' };
      } catch {
        return { ok: false, message: 'Cannot read .env file' };
      }
    },
  },
  {
    name: 'GUARDRAILS_TOKEN set',
    run: async (opts = {}) => {
      const cwd = opts.cwd || process.cwd();
      const envPath = join(cwd, '.env');
      if (!existsSync(envPath)) {
        return { ok: true, warn: true, message: 'No .env file (GUARDRAILS_TOKEN not set)' };
      }
      try {
        const content = readFileSync(envPath, 'utf-8');
        if (
          !content.includes('GUARDRAILS_TOKEN') ||
          content.includes('GUARDRAILS_TOKEN=\n') ||
          content.includes('GUARDRAILS_TOKEN=\r')
        ) {
          return { ok: true, warn: true, message: 'GUARDRAILS_TOKEN not set (optional)' };
        }
        return { ok: true, message: 'GUARDRAILS_TOKEN configured' };
      } catch {
        return { ok: true, warn: true, message: 'Cannot read .env' };
      }
    },
  },
  {
    name: 'Sidecar health',
    run: async (opts = {}) => {
      const url = opts.sidecarUrl || 'http://localhost:8000/health-check';
      const result = await checkSidecarHealth(url);
      return { ok: result.healthy, message: result.message };
    },
  },
  {
    name: 'Hook scripts executable',
    run: async (opts = {}) => {
      const cwd = opts.cwd || process.cwd();
      const scriptsDir = join(cwd, 'scripts');
      if (!existsSync(scriptsDir)) {
        return { ok: false, message: 'scripts/ directory not found' };
      }
      const guards = [
        'memory-guard.sh',
        'exfil-guard.sh',
        'write-guard.sh',
        'secret-guard.sh',
        'runtime-audit-gate.sh',
      ];
      const notExec = [];
      for (const name of guards) {
        const path = join(scriptsDir, name);
        if (existsSync(path)) {
          try {
            accessSync(path, constants.X_OK);
          } catch {
            notExec.push(name);
          }
        }
      }
      if (notExec.length > 0) {
        return { ok: false, message: `Not executable: ${notExec.join(', ')}` };
      }
      return { ok: true, message: 'All guard scripts are executable' };
    },
  },
  {
    name: 'settings.json valid',
    run: async (opts = {}) => {
      const cwd = opts.cwd || process.cwd();
      const settingsPath = join(cwd, 'config', 'settings.json');
      if (!existsSync(settingsPath)) {
        return { ok: false, message: 'config/settings.json not found' };
      }
      try {
        const content = readFileSync(settingsPath, 'utf-8');
        const settings = JSON.parse(content);
        let hookCount = 0;
        if (settings.hooks) {
          for (const phase of Object.values(settings.hooks)) {
            if (Array.isArray(phase)) {
              for (const group of phase) {
                if (group.hooks && Array.isArray(group.hooks)) {
                  hookCount += group.hooks.length;
                }
              }
            }
          }
        }
        return { ok: true, message: `Valid JSON, ${hookCount} hooks configured` };
      } catch (err) {
        return { ok: false, message: `Invalid JSON: ${err.message}` };
      }
    },
  },
];

/**
 * Run all doctor checks and print results.
 * Returns { passed, failed, warned }.
 */
export async function runDoctor(opts = {}) {
  console.log('\n=== enclAIve Doctor ===\n');

  let passed = 0;
  let failed = 0;
  let warned = 0;

  for (const check of doctorChecks) {
    const result = await check.run(opts);
    let prefix;
    if (!result.ok) {
      prefix = '[FAIL]';
      failed++;
    } else if (result.warn) {
      prefix = '[WARN]';
      warned++;
    } else {
      prefix = '[OK]';
      passed++;
    }
    console.log(`  ${prefix} ${check.name}: ${result.message}`);
  }

  console.log(`\n  Summary: ${passed} passed, ${failed} failed, ${warned} warnings\n`);

  return { passed, failed, warned };
}

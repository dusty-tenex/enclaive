import { execa } from 'execa';
import { existsSync } from 'node:fs';
import { join, basename } from 'node:path';

// Sidecar container config
const SIDECAR_CONTAINER = 'guardrails-sidecar';
const SIDECAR_IMAGE = 'guardrails-sidecar';
const SIDECAR_PORT = 8000;

/**
 * Derive the sandbox name from a project directory.
 * Convention: claude-<basename> (matches Makefile convention).
 */
export function sandboxName(projectDir) {
  return `claude-${basename(projectDir)}`;
}

/**
 * Find a docker-compose file in the given directory (used by sidecar build).
 */
export function findComposeFile(dir) {
  for (const name of ['docker-compose.yml', 'docker-compose.yaml', 'compose.yml', 'compose.yaml']) {
    const candidate = join(dir, name);
    if (existsSync(candidate)) return candidate;
  }
  return null;
}

// -- Sidecar (standalone container on host) -------------------

/**
 * Build the sidecar image from config/guardrails-server/.
 */
export async function buildSidecar(opts = {}) {
  const cwd = opts.cwd || process.cwd();
  return execa('docker', [
    'build', '-t', SIDECAR_IMAGE, join(cwd, 'config', 'guardrails-server'),
  ], { cwd, stdio: opts.stdio || 'inherit' });
}

/**
 * Start the sidecar container with validator mounts.
 */
export async function startSidecar(opts = {}) {
  const cwd = opts.cwd || process.cwd();
  // Remove existing sidecar if present
  await execa('docker', ['rm', '-f', SIDECAR_CONTAINER], { reject: false, stdio: 'pipe' });

  return execa('docker', [
    'run', '-d',
    '--name', SIDECAR_CONTAINER,
    '-p', `${SIDECAR_PORT}:${SIDECAR_PORT}`,
    '--read-only',
    '--tmpfs', '/tmp:size=100M',
    '-v', `${join(cwd, 'scripts', 'validators.py')}:/app/shared/validators.py:ro`,
    '-v', `${join(cwd, 'scripts', 'guard_definitions.py')}:/app/shared/guard_definitions.py:ro`,
    '--restart', 'unless-stopped',
    SIDECAR_IMAGE,
  ], { cwd, stdio: opts.stdio || 'pipe' });
}

/**
 * Stop and remove the sidecar container.
 */
export async function stopSidecar() {
  return execa('docker', ['rm', '-f', SIDECAR_CONTAINER], { reject: false, stdio: 'pipe' });
}

/**
 * Check if the sidecar container is running.
 */
export async function isSidecarRunning() {
  try {
    const result = await execa('docker', [
      'inspect', '-f', '{{.State.Running}}', SIDECAR_CONTAINER,
    ], { stdio: 'pipe' });
    return result.stdout.trim() === 'true';
  } catch {
    return false;
  }
}

// -- Sandbox (docker sandbox microVM) -------------------------

/**
 * Start/enter the sandbox microVM.
 */
export async function startSandbox(opts = {}) {
  const cwd = opts.cwd || process.cwd();
  const name = opts.name || sandboxName(cwd);
  return execa('docker', ['sandbox', 'run', name], {
    cwd,
    stdio: opts.stdio || 'inherit',
  });
}

/**
 * Execute a command inside the sandbox.
 */
export async function execInSandbox(command, opts = {}) {
  const cwd = opts.cwd || process.cwd();
  const name = opts.name || sandboxName(cwd);
  const args = ['sandbox', 'exec', name];
  if (Array.isArray(command)) {
    args.push(...command);
  } else {
    args.push(command);
  }
  return execa('docker', args, { stdio: opts.stdio || 'inherit' });
}

/**
 * Stop the sandbox.
 */
export async function stopSandbox(opts = {}) {
  const cwd = opts.cwd || process.cwd();
  const name = opts.name || sandboxName(cwd);
  return execa('docker', ['sandbox', 'stop', name], {
    reject: false, stdio: opts.stdio || 'inherit',
  });
}

/**
 * Destroy the sandbox (stop + remove).
 */
export async function destroySandbox(opts = {}) {
  const cwd = opts.cwd || process.cwd();
  const name = opts.name || sandboxName(cwd);
  await execa('docker', ['sandbox', 'stop', name], { reject: false, stdio: 'pipe' });
  return execa('docker', ['sandbox', 'rm', name], { reject: false, stdio: 'pipe' });
}

// -- Status ---------------------------------------------------

/**
 * Get sandbox and sidecar status.
 * Returns { sandbox: bool, sidecar: bool, sandboxName: string }.
 */
export async function containerStatus(opts = {}) {
  const cwd = opts.cwd || process.cwd();
  const name = opts.name || sandboxName(cwd);

  const sidecar = await isSidecarRunning();

  let sandbox = false;
  try {
    const result = await execa('docker', ['sandbox', 'ls'], { stdio: 'pipe' });
    sandbox = result.stdout.split('\n').some(
      line => line.includes(name) && line.toLowerCase().includes('running')
    );
  } catch {
    sandbox = false;
  }

  return { sandbox, sidecar, sandboxName: name };
}

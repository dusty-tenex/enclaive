#!/usr/bin/env node

import { Command } from 'commander';
import { resolve, join } from 'node:path';
import {
  buildSidecar, startSidecar, stopSidecar, startSandbox,
  execInSandbox, stopSandbox, destroySandbox, sandboxName,
  composeBuild, composeUp, composeDown, composeExec,
} from '../src/docker.js';
import { initProject } from '../src/init.js';
import { printStatus, runDoctor, checkSidecarHealth } from '../src/status.js';
import { readLogFile, filterLogs, formatLogLine, tailLog } from '../src/logs.js';

const program = new Command();

program
  .name('enclaive')
  .description('CLI tool for enclAIve — defense-in-depth for AI coding assistants')
  .version('0.1.0');

// init
program
  .command('init')
  .argument('[directory]', 'target directory', '.')
  .description('Initialize a new enclaive project')
  .action((directory) => {
    const targetDir = resolve(directory);
    initProject(targetDir);
  });

// up
program
  .command('up')
  .argument('[project-dir]', 'project directory to mount at /workspace')
  .description('Start sidecar + sandbox (optionally mounting a project)')
  .action(async (projectDir) => {
    const ora = (await import('ora')).default;
    const resolvedDir = projectDir ? resolve(projectDir) : undefined;

    if (resolvedDir) {
      const { existsSync } = await import('node:fs');
      if (!existsSync(resolvedDir)) {
        console.error(`[FAIL] Project directory does not exist: ${resolvedDir}`);
        process.exit(1);
      }
      console.log(`[INFO] Mounting project: ${resolvedDir}`);
    }

    // Build services
    let spinner = ora('[INFO] Building services...').start();
    try {
      await composeBuild({ projectDir: resolvedDir, stdio: 'pipe' });
      spinner.succeed('[OK] Services built');
    } catch (err) {
      spinner.fail(`[FAIL] Build failed: ${err.message}`);
      process.exit(1);
    }

    // Start all services (sidecar + proxy + sandbox)
    spinner = ora('[INFO] Starting services...').start();
    try {
      await composeUp({ projectDir: resolvedDir, stdio: 'pipe' });
      spinner.succeed('[OK] Services started');
    } catch (err) {
      spinner.fail(`[FAIL] Start failed: ${err.message}`);
      process.exit(1);
    }

    // Wait for sidecar health
    spinner = ora('[INFO] Waiting for sidecar health...').start();
    let healthy = false;
    for (let i = 0; i < 60; i++) {
      const result = await checkSidecarHealth('http://localhost:8000/health-check');
      if (result.healthy) { healthy = true; break; }
      await new Promise((r) => setTimeout(r, 2000));
    }

    if (healthy) {
      spinner.succeed('[OK] Sidecar healthy');
    } else {
      spinner.warn('[WARN] Sidecar started but health check failed -- run "enclaive doctor" to diagnose');
    }

    // Attach to sandbox
    const project = resolvedDir || process.cwd();
    console.log(`\n[INFO] Attaching to sandbox...`);
    console.log(`[INFO] Project mounted at /workspace: ${project}`);
    console.log('[INFO] Sidecar: http://guardrails-sidecar:8000 (inside sandbox)\n');

    try {
      await composeExec('sandbox', ['bash'], { stdio: 'inherit' });
    } catch (err) {
      if (err.exitCode !== 130) {
        console.error(`[FAIL] ${err.message}`);
        process.exit(1);
      }
    }
  });

// down
program
  .command('down')
  .description('Stop all services (sidecar + proxy + sandbox)')
  .action(async () => {
    try {
      await composeDown({ stdio: 'inherit' });
      console.log('[OK] All services stopped');
    } catch (err) {
      console.error(`[FAIL] ${err.message}`);
      process.exit(1);
    }
  });

// shell
program
  .command('shell')
  .description('Open a shell in the sandbox')
  .action(async () => {
    try {
      await composeExec('sandbox', ['bash'], { stdio: 'inherit' });
    } catch (err) {
      if (err.exitCode !== 130) {
        console.error(`[FAIL] ${err.message}`);
        process.exit(1);
      }
    }
  });

// run
program
  .command('run')
  .argument('<command...>', 'command to run in sandbox')
  .description('Run a command in the sandbox')
  .action(async (command) => {
    try {
      await composeExec('sandbox', command, { stdio: 'inherit' });
    } catch (err) {
      console.error(`[FAIL] ${err.message}`);
      process.exit(1);
    }
  });

// status
program
  .command('status')
  .description('Show sandbox status')
  .action(async () => {
    await printStatus();
  });

// logs
program
  .command('logs')
  .description('View audit logs')
  .option('-f, --follow', 'Follow log output')
  .option('-m, --mode <mode>', 'Filter by guard mode')
  .option('-n, --lines <count>', 'Number of lines to show', '20')
  .action(async (options) => {
    const logPath = join(process.cwd(), '.audit-logs', 'security-guard.jsonl');

    if (options.follow) {
      console.log('[INFO] Tailing audit log (Ctrl+C to stop)...\n');
      tailLog(logPath, (entry) => {
        if (options.mode && entry.mode !== options.mode) return;
        console.log(formatLogLine(entry));
      });
      // Keep process alive
      process.on('SIGINT', () => {
        console.log('\n[INFO] Stopped tailing.');
        process.exit(0);
      });
      return;
    }

    let entries = readLogFile(logPath);
    entries = filterLogs(entries, { mode: options.mode });

    const count = parseInt(options.lines, 10);
    if (entries.length > count) {
      entries = entries.slice(-count);
    }

    if (entries.length === 0) {
      console.log('[INFO] No log entries found.');
      return;
    }

    for (const entry of entries) {
      console.log(formatLogLine(entry));
    }
  });

// doctor
program
  .command('doctor')
  .description('Run diagnostic checks')
  .action(async () => {
    const result = await runDoctor();
    if (result.failed > 0) {
      process.exit(1);
    }
  });

program.parse();

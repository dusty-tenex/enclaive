#!/usr/bin/env node

import { Command } from 'commander';
import { resolve, join } from 'node:path';
import {
  buildSidecar, startSidecar, stopSidecar, startSandbox,
  execInSandbox, stopSandbox, destroySandbox, sandboxName,
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
  .description('Start sidecar + sandbox')
  .action(async () => {
    const ora = (await import('ora')).default;

    // Build and start sidecar
    let spinner = ora('[INFO] Building sidecar image...').start();
    try {
      await buildSidecar({ stdio: 'pipe' });
      spinner.succeed('[OK] Sidecar image built');
    } catch (err) {
      spinner.fail(`[FAIL] Sidecar build failed: ${err.message}`);
      process.exit(1);
    }

    spinner = ora('[INFO] Starting sidecar container...').start();
    try {
      await startSidecar({ stdio: 'pipe' });
      spinner.text = '[INFO] Waiting for sidecar health...';

      let healthy = false;
      for (let i = 0; i < 30; i++) {
        const result = await checkSidecarHealth('http://localhost:8000/health');
        if (result.healthy) { healthy = true; break; }
        await new Promise((r) => setTimeout(r, 1000));
      }

      if (healthy) {
        spinner.succeed('[OK] Sidecar healthy');
      } else {
        spinner.warn('[WARN] Sidecar started but health check failed');
      }
    } catch (err) {
      spinner.fail(`[FAIL] Sidecar start failed: ${err.message}`);
      process.exit(1);
    }

    // Launch sandbox
    const name = sandboxName(process.cwd());
    console.log(`\n[INFO] Launching sandbox "${name}"...`);
    console.log('[INFO] This will open an interactive sandbox session.');
    console.log('[INFO] The sidecar is running at http://localhost:8000');
    console.log('[INFO] Inside the sandbox, sidecar is at http://host.docker.internal:8000\n');

    try {
      await startSandbox({ stdio: 'inherit' });
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
  .description('Stop sandbox and sidecar')
  .option('--clean', 'Destroy sandbox entirely (remove VM)')
  .action(async (options) => {
    try {
      if (options.clean) {
        await destroySandbox({ stdio: 'pipe' });
        console.log('[OK] Sandbox destroyed');
      } else {
        await stopSandbox({ stdio: 'pipe' });
        console.log('[OK] Sandbox stopped');
      }
      await stopSidecar();
      console.log('[OK] Sidecar stopped');
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
      await execInSandbox(['bash']);
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
      await execInSandbox(command, { interactive: false });
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

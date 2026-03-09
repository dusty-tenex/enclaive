import * as vscode from "vscode";
import { StatusBarManager } from "./statusBar";
import { AuditLogWatcher, AuditEntry } from "./auditLogWatcher";
import { SidecarClient } from "./sidecarClient";

function formatEntry(entry: AuditEntry): string {
  const ts = entry.timestamp;
  // Extract HH:MM:SS from ISO timestamp
  let timeStr = ts;
  const match = ts.match(/T(\d{2}:\d{2}:\d{2})/);
  if (match) {
    timeStr = match[1];
  }
  const lines = [
    `[${timeStr}] ${entry.action} [${entry.mode}] ${entry.file}`,
    `           Reason: ${entry.reason}`,
    `           Engine: ${entry.engine}`,
  ];
  return lines.join("\n");
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export function registerCommands(
  context: vscode.ExtensionContext,
  statusBar: StatusBarManager,
  logWatcher: AuditLogWatcher,
  sidecarClient: SidecarClient,
): void {
  let outputChannel: vscode.OutputChannel | undefined;
  let logStreamSub: vscode.Disposable | undefined;

  // --- showLog ---
  context.subscriptions.push(
    vscode.commands.registerCommand("enclaive.showLog", () => {
      if (!outputChannel) {
        outputChannel = vscode.window.createOutputChannel("Security Guard");
        context.subscriptions.push(outputChannel);
      }
      outputChannel.clear();

      // Print all existing BLOCKED entries
      const blocked = logWatcher
        .getEntries()
        .filter((e) => e.action === "BLOCKED");
      for (const entry of blocked) {
        outputChannel.appendLine(formatEntry(entry));
        outputChannel.appendLine("");
      }

      if (blocked.length === 0) {
        outputChannel.appendLine("[INFO] No blocked entries recorded.");
      }

      // Stream new blocked entries
      logStreamSub?.dispose();
      logStreamSub = logWatcher.onNewEntry((entry) => {
        if (entry.action === "BLOCKED") {
          outputChannel!.appendLine(formatEntry(entry));
          outputChannel!.appendLine("");
        }
      });
      context.subscriptions.push(logStreamSub);

      outputChannel.show(true);
    }),
  );

  // --- start ---
  context.subscriptions.push(
    vscode.commands.registerCommand("enclaive.start", async () => {
      statusBar.setState("starting");

      const terminal = vscode.window.createTerminal({
        name: "enclAIve",
        hideFromUser: true,
      });
      // Start sidecar (standalone container) then sandbox (microVM)
      terminal.sendText("docker rm -f guardrails-sidecar 2>/dev/null; docker run -d --name guardrails-sidecar -p 8000:8000 --read-only --tmpfs /tmp:size=100M --restart unless-stopped guardrails-sidecar");

      // Poll sidecar health up to 30 times (roughly 30s)
      let healthy = false;
      for (let i = 0; i < 30; i++) {
        await delay(1000);
        const result = await sidecarClient.checkHealth();
        if (result.healthy) {
          healthy = true;
          break;
        }
      }

      terminal.dispose();

      if (healthy) {
        statusBar.setState("active");
        statusBar.startPolling();
        logWatcher.start();
      } else {
        statusBar.setState("sidecarDown");
      }
    }),
  );

  // --- stop ---
  context.subscriptions.push(
    vscode.commands.registerCommand("enclaive.stop", () => {
      const terminal = vscode.window.createTerminal({
        name: "enclAIve",
        hideFromUser: true,
      });
      // Stop sandbox and sidecar
      terminal.sendText("docker sandbox stop enclaive 2>/dev/null; docker rm -f guardrails-sidecar 2>/dev/null");
      statusBar.stopPolling();
      statusBar.setState("off");
      // Clean up terminal after a short delay
      setTimeout(() => terminal.dispose(), 5000);
    }),
  );

  // --- restartSidecar ---
  context.subscriptions.push(
    vscode.commands.registerCommand("enclaive.restartSidecar", () => {
      const terminal = vscode.window.createTerminal({
        name: "enclAIve",
        hideFromUser: true,
      });
      terminal.sendText("docker restart guardrails-sidecar");
      setTimeout(() => terminal.dispose(), 10000);
    }),
  );

  // --- openShell ---
  context.subscriptions.push(
    vscode.commands.registerCommand("enclaive.openShell", () => {
      const terminal = vscode.window.createTerminal({
        name: "Sandbox Shell",
      });
      terminal.sendText("docker sandbox exec enclaive bash");
      terminal.show();
    }),
  );

  // --- doctor ---
  context.subscriptions.push(
    vscode.commands.registerCommand("enclaive.doctor", () => {
      const terminal = vscode.window.createTerminal({
        name: "Sandbox Doctor",
      });
      terminal.sendText("npx enclaive doctor");
      terminal.show();
    }),
  );
}

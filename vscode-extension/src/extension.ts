import * as vscode from "vscode";
import { SidecarClient } from "./sidecarClient";
import { AuditLogWatcher } from "./auditLogWatcher";
import { StatusBarManager } from "./statusBar";
import { NotificationHandler } from "./notifications";
import { registerCommands } from "./commands";
import { getConfig } from "./config";

export function activate(context: vscode.ExtensionContext): void {
  const sidecarClient = new SidecarClient();
  const logWatcher = new AuditLogWatcher();
  const statusBar = new StatusBarManager(sidecarClient, logWatcher);
  const notificationHandler = new NotificationHandler(logWatcher);

  context.subscriptions.push(logWatcher);
  context.subscriptions.push(statusBar);
  context.subscriptions.push(notificationHandler);

  registerCommands(context, statusBar, logWatcher, sidecarClient);

  // Refresh sidecar URL when configuration changes
  context.subscriptions.push(
    vscode.workspace.onDidChangeConfiguration((e) => {
      if (e.affectsConfiguration("enclaive.sidecarUrl")) {
        sidecarClient.refreshConfig();
      }
    }),
  );

  // Always start the log watcher so it picks up entries when containers start
  logWatcher.start();

  // Check initial sidecar health
  sidecarClient.checkHealth().then((result) => {
    if (result.healthy) {
      statusBar.setState("active");
      statusBar.startPolling();
    } else {
      statusBar.setState("off");
      // Auto-start if configured
      const cfg = getConfig();
      if (cfg.autoStart) {
        vscode.commands.executeCommand("enclaive.start");
      }
    }
  });
}

export function deactivate(): void {
  // Cleanup handled by context.subscriptions
}

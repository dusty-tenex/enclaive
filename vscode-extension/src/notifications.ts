import * as vscode from "vscode";
import { AuditLogWatcher, AuditEntry } from "./auditLogWatcher";
import { getConfig } from "./config";

export class NotificationHandler implements vscode.Disposable {
  private _lastNotificationTime = 0;
  private readonly _sub: vscode.Disposable;

  constructor(logWatcher: AuditLogWatcher) {
    this._sub = logWatcher.onNewEntry((entry) => this._onEntry(entry));
  }

  private _onEntry(entry: AuditEntry): void {
    if (entry.action !== "BLOCKED") {
      return;
    }

    const cfg = getConfig();
    if (!cfg.notificationsEnabled) {
      return;
    }

    const now = Date.now();
    if (now - this._lastNotificationTime < cfg.notificationsMinInterval) {
      return;
    }
    this._lastNotificationTime = now;

    const msg = `[BLOCKED] ${entry.tool} on ${entry.file}: ${entry.reason}`;
    vscode.window.showWarningMessage(msg, "View Log").then((choice) => {
      if (choice === "View Log") {
        vscode.commands.executeCommand("enclaive.showLog");
      }
    });
  }

  dispose(): void {
    this._sub.dispose();
  }
}

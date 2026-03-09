import * as vscode from "vscode";

export interface SandboxConfig {
  sidecarUrl: string;
  auditLogPath: string;
  notificationsEnabled: boolean;
  notificationsMinInterval: number;
  showBlockCount: boolean;
  autoStart: boolean;
}

export function getConfig(): SandboxConfig {
  const cfg = vscode.workspace.getConfiguration("enclaive");
  return {
    sidecarUrl: cfg.get<string>("sidecarUrl", "http://localhost:8000"),
    auditLogPath: cfg.get<string>(
      "auditLogPath",
      ".audit-logs/security-guard.jsonl",
    ),
    notificationsEnabled: cfg.get<boolean>("notifications.enabled", true),
    notificationsMinInterval: cfg.get<number>(
      "notifications.minInterval",
      5000,
    ),
    showBlockCount: cfg.get<boolean>("statusBar.showBlockCount", true),
    autoStart: cfg.get<boolean>("autoStart", false),
  };
}

export function getAuditLogUri(): vscode.Uri | undefined {
  const folders = vscode.workspace.workspaceFolders;
  if (!folders || folders.length === 0) {
    return undefined;
  }
  const cfg = getConfig();
  return vscode.Uri.joinPath(folders[0].uri, cfg.auditLogPath);
}

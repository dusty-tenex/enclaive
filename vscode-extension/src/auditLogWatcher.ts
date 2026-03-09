import * as vscode from "vscode";
import * as fs from "node:fs";
import { getAuditLogUri } from "./config";

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
  private readonly _onNewEntry = new vscode.EventEmitter<AuditEntry>();
  public readonly onNewEntry = this._onNewEntry.event;

  private _entries: AuditEntry[] = [];
  private _watcher: vscode.FileSystemWatcher | undefined;
  private _lastByteOffset = 0;
  private _logPath: string | undefined;

  start(): void {
    const uri = getAuditLogUri();
    if (!uri) {
      return;
    }
    this._logPath = uri.fsPath;

    // Read existing entries
    this._readExisting();

    // Watch for changes
    const pattern = new vscode.RelativePattern(
      vscode.workspace.workspaceFolders![0],
      ".audit-logs/security-guard.jsonl",
    );
    this._watcher = vscode.workspace.createFileSystemWatcher(pattern);
    this._watcher.onDidChange(() => this._readNewEntries());
    this._watcher.onDidCreate(() => {
      this._lastByteOffset = 0;
      this._readNewEntries();
    });
  }

  private _readExisting(): void {
    if (!this._logPath) {
      return;
    }
    try {
      const content = fs.readFileSync(this._logPath, "utf-8");
      this._lastByteOffset = Buffer.byteLength(content, "utf-8");
      const lines = content.split("\n").filter((l) => l.trim().length > 0);
      for (const line of lines) {
        const entry = this.parseLine(line);
        if (entry) {
          this._entries.push(entry);
        }
      }
    } catch {
      // File may not exist yet -- that is fine
      this._lastByteOffset = 0;
    }
  }

  private _readNewEntries(): void {
    if (!this._logPath) {
      return;
    }
    try {
      const stat = fs.statSync(this._logPath);
      if (stat.size <= this._lastByteOffset) {
        // File was truncated or unchanged
        if (stat.size < this._lastByteOffset) {
          this._lastByteOffset = 0;
          this._entries = [];
        }
        return;
      }
      const fd = fs.openSync(this._logPath, "r");
      const buf = Buffer.alloc(stat.size - this._lastByteOffset);
      fs.readSync(fd, buf, 0, buf.length, this._lastByteOffset);
      fs.closeSync(fd);
      this._lastByteOffset = stat.size;

      const newContent = buf.toString("utf-8");
      const lines = newContent.split("\n").filter((l) => l.trim().length > 0);
      for (const line of lines) {
        const entry = this.parseLine(line);
        if (entry) {
          this._entries.push(entry);
          this._onNewEntry.fire(entry);
        }
      }
    } catch {
      // Ignore read errors; file may be in flux
    }
  }

  parseLine(line: string): AuditEntry | null {
    try {
      const obj = JSON.parse(line);
      if (
        typeof obj.timestamp === "string" &&
        typeof obj.action === "string"
      ) {
        return {
          timestamp: obj.timestamp ?? "",
          mode: obj.mode ?? "",
          file: obj.file ?? "",
          tool: obj.tool ?? "",
          action: obj.action ?? "",
          reason: obj.reason ?? "",
          engine: obj.engine ?? "",
        };
      }
      return null;
    } catch {
      return null;
    }
  }

  getEntries(): readonly AuditEntry[] {
    return this._entries;
  }

  getBlockCount(): number {
    return this._entries.filter((e) => e.action === "BLOCKED").length;
  }

  getBlockCountToday(): number {
    const todayPrefix = new Date().toISOString().slice(0, 10);
    return this._entries.filter(
      (e) => e.action === "BLOCKED" && e.timestamp.startsWith(todayPrefix),
    ).length;
  }

  getLastBlock(): AuditEntry | undefined {
    for (let i = this._entries.length - 1; i >= 0; i--) {
      if (this._entries[i].action === "BLOCKED") {
        return this._entries[i];
      }
    }
    return undefined;
  }

  dispose(): void {
    this._watcher?.dispose();
    this._onNewEntry.dispose();
  }
}

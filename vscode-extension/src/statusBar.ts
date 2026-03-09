import * as vscode from "vscode";
import { SidecarClient } from "./sidecarClient";
import { AuditLogWatcher } from "./auditLogWatcher";
import { getConfig } from "./config";

export type SandboxState = "off" | "starting" | "active" | "sidecarDown";

export class StatusBarManager implements vscode.Disposable {
  private readonly _item: vscode.StatusBarItem;
  private readonly _client: SidecarClient;
  private readonly _logWatcher: AuditLogWatcher;
  private _state: SandboxState = "off";
  private _pollTimer: ReturnType<typeof setInterval> | undefined;
  private _logSub: vscode.Disposable | undefined;

  constructor(client: SidecarClient, logWatcher: AuditLogWatcher) {
    this._client = client;
    this._logWatcher = logWatcher;
    this._item = vscode.window.createStatusBarItem(
      vscode.StatusBarAlignment.Left,
      100,
    );
    this._item.show();
    this.setState("off");

    this._logSub = logWatcher.onNewEntry(() => {
      if (this._state === "active") {
        this._updateActiveText();
      }
    });
  }

  get state(): SandboxState {
    return this._state;
  }

  setState(state: SandboxState): void {
    this._state = state;
    switch (state) {
      case "off":
        this._item.text = "$(shield) Sandbox: Off";
        this._item.color = new vscode.ThemeColor(
          "statusBar.foreground",
        );
        this._item.backgroundColor = undefined;
        this._item.command = "enclaive.start";
        this._item.tooltip = "enclAIve -- Click to start";
        break;

      case "starting":
        this._item.text = "$(loading~spin) Sandbox: Starting...";
        this._item.color = undefined;
        this._item.backgroundColor = new vscode.ThemeColor(
          "statusBarItem.warningBackground",
        );
        this._item.command = undefined;
        this._item.tooltip = "enclAIve -- Starting containers...";
        break;

      case "active":
        this._updateActiveText();
        this._item.color = new vscode.ThemeColor(
          "testing.iconPassed",
        );
        this._item.backgroundColor = undefined;
        this._item.command = "enclaive.showLog";
        break;

      case "sidecarDown":
        this._item.text = "$(shield) Sandbox: Sidecar Down";
        this._item.color = undefined;
        this._item.backgroundColor = new vscode.ThemeColor(
          "statusBarItem.errorBackground",
        );
        this._item.command = "enclaive.doctor";
        this._item.tooltip =
          "enclAIve -- Sidecar unreachable. Click to run doctor.";
        break;
    }
  }

  private _updateActiveText(): void {
    const cfg = getConfig();
    const blockCount = this._logWatcher.getBlockCount();
    const blocksToday = this._logWatcher.getBlockCountToday();
    const lastBlock = this._logWatcher.getLastBlock();

    if (cfg.showBlockCount) {
      this._item.text = `$(shield) Sandbox: Active (${blockCount} blocks)`;
    } else {
      this._item.text = "$(shield) Sandbox: Active";
    }

    let tooltip = `enclAIve\nSidecar: healthy\nBlocks today: ${blocksToday}`;
    if (lastBlock) {
      tooltip += `\nLast: ${lastBlock.mode} -- ${lastBlock.reason}`;
    }
    this._item.tooltip = tooltip;
  }

  startPolling(intervalMs = 10000): void {
    this.stopPolling();
    this._pollTimer = setInterval(async () => {
      const result = await this._client.checkHealth();
      if (result.healthy && this._state !== "active") {
        this.setState("active");
      } else if (!result.healthy && this._state === "active") {
        this.setState("sidecarDown");
      }
    }, intervalMs);
  }

  stopPolling(): void {
    if (this._pollTimer !== undefined) {
      clearInterval(this._pollTimer);
      this._pollTimer = undefined;
    }
  }

  dispose(): void {
    this.stopPolling();
    this._logSub?.dispose();
    this._item.dispose();
  }
}

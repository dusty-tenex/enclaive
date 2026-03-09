"use strict";
var __create = Object.create;
var __defProp = Object.defineProperty;
var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
var __getOwnPropNames = Object.getOwnPropertyNames;
var __getProtoOf = Object.getPrototypeOf;
var __hasOwnProp = Object.prototype.hasOwnProperty;
var __export = (target, all) => {
  for (var name in all)
    __defProp(target, name, { get: all[name], enumerable: true });
};
var __copyProps = (to, from, except, desc) => {
  if (from && typeof from === "object" || typeof from === "function") {
    for (let key of __getOwnPropNames(from))
      if (!__hasOwnProp.call(to, key) && key !== except)
        __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
  }
  return to;
};
var __toESM = (mod, isNodeMode, target) => (target = mod != null ? __create(__getProtoOf(mod)) : {}, __copyProps(
  // If the importer is in node compatibility mode or this is not an ESM
  // file that has been converted to a CommonJS file using a Babel-
  // compatible transform (i.e. "__esModule" has not been set), then set
  // "default" to the CommonJS "module.exports" for node compatibility.
  isNodeMode || !mod || !mod.__esModule ? __defProp(target, "default", { value: mod, enumerable: true }) : target,
  mod
));
var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

// src/extension.ts
var extension_exports = {};
__export(extension_exports, {
  activate: () => activate,
  deactivate: () => deactivate
});
module.exports = __toCommonJS(extension_exports);
var vscode6 = __toESM(require("vscode"));

// src/sidecarClient.ts
var http = __toESM(require("node:http"));

// src/config.ts
var vscode = __toESM(require("vscode"));
function getConfig() {
  const cfg = vscode.workspace.getConfiguration("claude-sandbox");
  return {
    sidecarUrl: cfg.get("sidecarUrl", "http://localhost:8000"),
    auditLogPath: cfg.get(
      "auditLogPath",
      ".audit-logs/security-guard.jsonl"
    ),
    notificationsEnabled: cfg.get("notifications.enabled", true),
    notificationsMinInterval: cfg.get(
      "notifications.minInterval",
      5e3
    ),
    showBlockCount: cfg.get("statusBar.showBlockCount", true),
    autoStart: cfg.get("autoStart", false)
  };
}
function getAuditLogUri() {
  const folders = vscode.workspace.workspaceFolders;
  if (!folders || folders.length === 0) {
    return void 0;
  }
  const cfg = getConfig();
  return vscode.Uri.joinPath(folders[0].uri, cfg.auditLogPath);
}

// src/sidecarClient.ts
var SidecarClient = class {
  _url;
  constructor() {
    this._url = getConfig().sidecarUrl;
  }
  refreshConfig() {
    this._url = getConfig().sidecarUrl;
  }
  checkHealth() {
    return new Promise((resolve) => {
      const endpoint = `${this._url}/health`;
      let parsedUrl;
      try {
        parsedUrl = new URL(endpoint);
      } catch {
        resolve({ healthy: false, message: `Invalid sidecar URL: ${endpoint}` });
        return;
      }
      const options = {
        hostname: parsedUrl.hostname,
        port: parsedUrl.port || 80,
        path: parsedUrl.pathname,
        method: "GET",
        timeout: 5e3
      };
      const req = http.request(options, (res) => {
        let data = "";
        res.on("data", (chunk) => {
          data += chunk.toString();
        });
        res.on("end", () => {
          if (res.statusCode && res.statusCode >= 200 && res.statusCode < 300) {
            resolve({ healthy: true, message: data || "OK" });
          } else {
            resolve({
              healthy: false,
              message: `HTTP ${res.statusCode}: ${data}`
            });
          }
        });
      });
      req.on("timeout", () => {
        req.destroy();
        resolve({ healthy: false, message: "Connection timed out (5s)" });
      });
      req.on("error", (err) => {
        resolve({ healthy: false, message: err.message });
      });
      req.end();
    });
  }
};

// src/auditLogWatcher.ts
var vscode2 = __toESM(require("vscode"));
var fs = __toESM(require("node:fs"));
var AuditLogWatcher = class {
  _onNewEntry = new vscode2.EventEmitter();
  onNewEntry = this._onNewEntry.event;
  _entries = [];
  _watcher;
  _lastByteOffset = 0;
  _logPath;
  start() {
    const uri = getAuditLogUri();
    if (!uri) {
      return;
    }
    this._logPath = uri.fsPath;
    this._readExisting();
    const pattern = new vscode2.RelativePattern(
      vscode2.workspace.workspaceFolders[0],
      ".audit-logs/security-guard.jsonl"
    );
    this._watcher = vscode2.workspace.createFileSystemWatcher(pattern);
    this._watcher.onDidChange(() => this._readNewEntries());
    this._watcher.onDidCreate(() => {
      this._lastByteOffset = 0;
      this._readNewEntries();
    });
  }
  _readExisting() {
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
      this._lastByteOffset = 0;
    }
  }
  _readNewEntries() {
    if (!this._logPath) {
      return;
    }
    try {
      const stat = fs.statSync(this._logPath);
      if (stat.size <= this._lastByteOffset) {
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
    }
  }
  parseLine(line) {
    try {
      const obj = JSON.parse(line);
      if (typeof obj.timestamp === "string" && typeof obj.action === "string") {
        return {
          timestamp: obj.timestamp ?? "",
          mode: obj.mode ?? "",
          file: obj.file ?? "",
          tool: obj.tool ?? "",
          action: obj.action ?? "",
          reason: obj.reason ?? "",
          engine: obj.engine ?? ""
        };
      }
      return null;
    } catch {
      return null;
    }
  }
  getEntries() {
    return this._entries;
  }
  getBlockCount() {
    return this._entries.filter((e) => e.action === "BLOCKED").length;
  }
  getBlockCountToday() {
    const todayPrefix = (/* @__PURE__ */ new Date()).toISOString().slice(0, 10);
    return this._entries.filter(
      (e) => e.action === "BLOCKED" && e.timestamp.startsWith(todayPrefix)
    ).length;
  }
  getLastBlock() {
    for (let i = this._entries.length - 1; i >= 0; i--) {
      if (this._entries[i].action === "BLOCKED") {
        return this._entries[i];
      }
    }
    return void 0;
  }
  dispose() {
    this._watcher?.dispose();
    this._onNewEntry.dispose();
  }
};

// src/statusBar.ts
var vscode3 = __toESM(require("vscode"));
var StatusBarManager = class {
  _item;
  _client;
  _logWatcher;
  _state = "off";
  _pollTimer;
  _logSub;
  constructor(client, logWatcher) {
    this._client = client;
    this._logWatcher = logWatcher;
    this._item = vscode3.window.createStatusBarItem(
      vscode3.StatusBarAlignment.Left,
      100
    );
    this._item.show();
    this.setState("off");
    this._logSub = logWatcher.onNewEntry(() => {
      if (this._state === "active") {
        this._updateActiveText();
      }
    });
  }
  get state() {
    return this._state;
  }
  setState(state) {
    this._state = state;
    switch (state) {
      case "off":
        this._item.text = "$(shield) Sandbox: Off";
        this._item.color = new vscode3.ThemeColor(
          "statusBar.foreground"
        );
        this._item.backgroundColor = void 0;
        this._item.command = "claude-sandbox.start";
        this._item.tooltip = "Claude Code Secure Sandbox -- Click to start";
        break;
      case "starting":
        this._item.text = "$(loading~spin) Sandbox: Starting...";
        this._item.color = void 0;
        this._item.backgroundColor = new vscode3.ThemeColor(
          "statusBarItem.warningBackground"
        );
        this._item.command = void 0;
        this._item.tooltip = "Claude Code Secure Sandbox -- Starting containers...";
        break;
      case "active":
        this._updateActiveText();
        this._item.color = new vscode3.ThemeColor(
          "testing.iconPassed"
        );
        this._item.backgroundColor = void 0;
        this._item.command = "claude-sandbox.showLog";
        break;
      case "sidecarDown":
        this._item.text = "$(shield) Sandbox: Sidecar Down";
        this._item.color = void 0;
        this._item.backgroundColor = new vscode3.ThemeColor(
          "statusBarItem.errorBackground"
        );
        this._item.command = "claude-sandbox.doctor";
        this._item.tooltip = "Claude Code Secure Sandbox -- Sidecar unreachable. Click to run doctor.";
        break;
    }
  }
  _updateActiveText() {
    const cfg = getConfig();
    const blockCount = this._logWatcher.getBlockCount();
    const blocksToday = this._logWatcher.getBlockCountToday();
    const lastBlock = this._logWatcher.getLastBlock();
    if (cfg.showBlockCount) {
      this._item.text = `$(shield) Sandbox: Active (${blockCount} blocks)`;
    } else {
      this._item.text = "$(shield) Sandbox: Active";
    }
    let tooltip = `Claude Code Secure Sandbox
Sidecar: healthy
Blocks today: ${blocksToday}`;
    if (lastBlock) {
      tooltip += `
Last: ${lastBlock.mode} -- ${lastBlock.reason}`;
    }
    this._item.tooltip = tooltip;
  }
  startPolling(intervalMs = 1e4) {
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
  stopPolling() {
    if (this._pollTimer !== void 0) {
      clearInterval(this._pollTimer);
      this._pollTimer = void 0;
    }
  }
  dispose() {
    this.stopPolling();
    this._logSub?.dispose();
    this._item.dispose();
  }
};

// src/notifications.ts
var vscode4 = __toESM(require("vscode"));
var NotificationHandler = class {
  _lastNotificationTime = 0;
  _sub;
  constructor(logWatcher) {
    this._sub = logWatcher.onNewEntry((entry) => this._onEntry(entry));
  }
  _onEntry(entry) {
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
    vscode4.window.showWarningMessage(msg, "View Log").then((choice) => {
      if (choice === "View Log") {
        vscode4.commands.executeCommand("claude-sandbox.showLog");
      }
    });
  }
  dispose() {
    this._sub.dispose();
  }
};

// src/commands.ts
var vscode5 = __toESM(require("vscode"));
function formatEntry(entry) {
  const ts = entry.timestamp;
  let timeStr = ts;
  const match = ts.match(/T(\d{2}:\d{2}:\d{2})/);
  if (match) {
    timeStr = match[1];
  }
  const lines = [
    `[${timeStr}] ${entry.action} [${entry.mode}] ${entry.file}`,
    `           Reason: ${entry.reason}`,
    `           Engine: ${entry.engine}`
  ];
  return lines.join("\n");
}
function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
function registerCommands(context, statusBar, logWatcher, sidecarClient) {
  let outputChannel;
  let logStreamSub;
  context.subscriptions.push(
    vscode5.commands.registerCommand("claude-sandbox.showLog", () => {
      if (!outputChannel) {
        outputChannel = vscode5.window.createOutputChannel("Security Guard");
        context.subscriptions.push(outputChannel);
      }
      outputChannel.clear();
      const blocked = logWatcher.getEntries().filter((e) => e.action === "BLOCKED");
      for (const entry of blocked) {
        outputChannel.appendLine(formatEntry(entry));
        outputChannel.appendLine("");
      }
      if (blocked.length === 0) {
        outputChannel.appendLine("[INFO] No blocked entries recorded.");
      }
      logStreamSub?.dispose();
      logStreamSub = logWatcher.onNewEntry((entry) => {
        if (entry.action === "BLOCKED") {
          outputChannel.appendLine(formatEntry(entry));
          outputChannel.appendLine("");
        }
      });
      context.subscriptions.push(logStreamSub);
      outputChannel.show(true);
    })
  );
  context.subscriptions.push(
    vscode5.commands.registerCommand("claude-sandbox.start", async () => {
      statusBar.setState("starting");
      const terminal = vscode5.window.createTerminal({
        name: "Claude Sandbox",
        hideFromUser: true
      });
      terminal.sendText("docker rm -f guardrails-sidecar 2>/dev/null; docker run -d --name guardrails-sidecar -p 8000:8000 --read-only --tmpfs /tmp:size=100M --restart unless-stopped guardrails-sidecar");
      let healthy = false;
      for (let i = 0; i < 30; i++) {
        await delay(1e3);
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
    })
  );
  context.subscriptions.push(
    vscode5.commands.registerCommand("claude-sandbox.stop", () => {
      const terminal = vscode5.window.createTerminal({
        name: "Claude Sandbox",
        hideFromUser: true
      });
      terminal.sendText("docker sandbox stop claude-sandbox 2>/dev/null; docker rm -f guardrails-sidecar 2>/dev/null");
      statusBar.stopPolling();
      statusBar.setState("off");
      setTimeout(() => terminal.dispose(), 5e3);
    })
  );
  context.subscriptions.push(
    vscode5.commands.registerCommand("claude-sandbox.restartSidecar", () => {
      const terminal = vscode5.window.createTerminal({
        name: "Claude Sandbox",
        hideFromUser: true
      });
      terminal.sendText("docker restart guardrails-sidecar");
      setTimeout(() => terminal.dispose(), 1e4);
    })
  );
  context.subscriptions.push(
    vscode5.commands.registerCommand("claude-sandbox.openShell", () => {
      const terminal = vscode5.window.createTerminal({
        name: "Sandbox Shell"
      });
      terminal.sendText("docker sandbox exec claude-sandbox bash");
      terminal.show();
    })
  );
  context.subscriptions.push(
    vscode5.commands.registerCommand("claude-sandbox.doctor", () => {
      const terminal = vscode5.window.createTerminal({
        name: "Sandbox Doctor"
      });
      terminal.sendText("npx @tenexai/claude-sandbox doctor");
      terminal.show();
    })
  );
}

// src/extension.ts
function activate(context) {
  const sidecarClient = new SidecarClient();
  const logWatcher = new AuditLogWatcher();
  const statusBar = new StatusBarManager(sidecarClient, logWatcher);
  const notificationHandler = new NotificationHandler(logWatcher);
  context.subscriptions.push(logWatcher);
  context.subscriptions.push(statusBar);
  context.subscriptions.push(notificationHandler);
  registerCommands(context, statusBar, logWatcher, sidecarClient);
  context.subscriptions.push(
    vscode6.workspace.onDidChangeConfiguration((e) => {
      if (e.affectsConfiguration("claude-sandbox.sidecarUrl")) {
        sidecarClient.refreshConfig();
      }
    })
  );
  logWatcher.start();
  sidecarClient.checkHealth().then((result) => {
    if (result.healthy) {
      statusBar.setState("active");
      statusBar.startPolling();
    } else {
      statusBar.setState("off");
      const cfg = getConfig();
      if (cfg.autoStart) {
        vscode6.commands.executeCommand("claude-sandbox.start");
      }
    }
  });
}
function deactivate() {
}
// Annotate the CommonJS export names for ESM import in node:
0 && (module.exports = {
  activate,
  deactivate
});
//# sourceMappingURL=extension.js.map

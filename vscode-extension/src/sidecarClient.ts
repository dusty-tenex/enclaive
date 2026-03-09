import * as http from "node:http";
import { getConfig } from "./config";

export class SidecarClient {
  private _url: string;

  constructor() {
    this._url = getConfig().sidecarUrl;
  }

  refreshConfig(): void {
    this._url = getConfig().sidecarUrl;
  }

  checkHealth(): Promise<{ healthy: boolean; message: string }> {
    return new Promise((resolve) => {
      const endpoint = `${this._url}/health`;
      let parsedUrl: URL;
      try {
        parsedUrl = new URL(endpoint);
      } catch {
        resolve({ healthy: false, message: `Invalid sidecar URL: ${endpoint}` });
        return;
      }

      const options: http.RequestOptions = {
        hostname: parsedUrl.hostname,
        port: parsedUrl.port || 80,
        path: parsedUrl.pathname,
        method: "GET",
        timeout: 5000,
      };

      const req = http.request(options, (res) => {
        let data = "";
        res.on("data", (chunk: Buffer) => {
          data += chunk.toString();
        });
        res.on("end", () => {
          if (res.statusCode && res.statusCode >= 200 && res.statusCode < 300) {
            resolve({ healthy: true, message: data || "OK" });
          } else {
            resolve({
              healthy: false,
              message: `HTTP ${res.statusCode}: ${data}`,
            });
          }
        });
      });

      req.on("timeout", () => {
        req.destroy();
        resolve({ healthy: false, message: "Connection timed out (5s)" });
      });

      req.on("error", (err: Error) => {
        resolve({ healthy: false, message: err.message });
      });

      req.end();
    });
  }
}

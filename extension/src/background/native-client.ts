import type {
  HostRequest,
  HostResponse,
  TabInfo,
  ConnectionStatus,
  ContextBundle,
  TabDecision,
} from "../shared/types.js";
import { setConnectionStatus } from "./storage.js";

const HOST_NAME = "com.tabx.host";
const PING_INTERVAL_MS = 30_000;
const RECONNECT_DELAY_MS = 5_000;
const MAX_RECONNECT_ATTEMPTS = 5;

type DecisionCallback = (
  decisions: Array<{ tabId: number; decision: TabDecision; score: number }>
) => void;

type BundleCallback = (bundle: ContextBundle) => void;

export class NativeMessagingClient {
  private port: chrome.runtime.Port | null = null;
  private pingTimer: ReturnType<typeof setInterval> | null = null;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private reconnectAttempts = 0;
  private onDecision: DecisionCallback;
  private onBundle: BundleCallback;
  private pendingBundleResolves: Array<(b: ContextBundle) => void> = [];

  constructor(onDecision: DecisionCallback, onBundle: BundleCallback) {
    this.onDecision = onDecision;
    this.onBundle = onBundle;
  }

  connect(): void {
    this.reconnectAttempts = 0;
    this.tryConnect();
  }

  private tryConnect(): void {
    try {
      this.port = chrome.runtime.connectNative(HOST_NAME);
      this.port.onMessage.addListener((msg: unknown) => {
        this.handleMessage(msg as HostResponse);
      });
      this.port.onDisconnect.addListener(() => {
        const err = chrome.runtime.lastError;
        console.warn("[TabX] Native host disconnected:", err?.message ?? "unknown");
        this.port = null;
        void setConnectionStatus("disconnected");
        this.scheduleReconnect();
      });

      void setConnectionStatus("connected");
      this.reconnectAttempts = 0;
      this.startPing();
    } catch (err) {
      console.error("[TabX] Failed to connect to native host:", err);
      void setConnectionStatus("error");
      this.scheduleReconnect();
    }
  }

  private scheduleReconnect(): void {
    if (this.pingTimer !== null) {
      clearInterval(this.pingTimer);
      this.pingTimer = null;
    }
    if (this.reconnectAttempts >= MAX_RECONNECT_ATTEMPTS) {
      console.warn("[TabX] Max reconnect attempts reached, giving up.");
      return;
    }
    this.reconnectAttempts++;
    const delay = RECONNECT_DELAY_MS * this.reconnectAttempts;
    this.reconnectTimer = setTimeout(() => {
      console.log(`[TabX] Reconnecting to native host (attempt ${this.reconnectAttempts})...`);
      this.tryConnect();
    }, delay);
  }

  private startPing(): void {
    if (this.pingTimer !== null) clearInterval(this.pingTimer);
    this.pingTimer = setInterval(() => {
      this.send({ type: "ping", timestamp: Date.now() });
    }, PING_INTERVAL_MS);
  }

  send(request: HostRequest): boolean {
    if (!this.port) return false;
    try {
      this.port.postMessage(request);
      return true;
    } catch (err) {
      console.error("[TabX] Error sending to native host:", err);
      return false;
    }
  }

  sendTabData(tabs: TabInfo[]): void {
    this.send({ type: "tab_data", tabs, timestamp: Date.now() });
  }

  requestContextBundle(): Promise<ContextBundle> {
    return new Promise((resolve) => {
      this.pendingBundleResolves.push(resolve);
      const sent = this.send({ type: "get_context_bundle", timestamp: Date.now() });
      if (!sent) {
        this.pendingBundleResolves.pop();
        resolve({
          pagesRead: [],
          highlights: [],
          survivingTabs: [],
          generatedAt: Date.now(),
        });
      }
    });
  }

  getStatus(): ConnectionStatus {
    return this.port !== null ? "connected" : "disconnected";
  }

  disconnect(): void {
    if (this.pingTimer !== null) {
      clearInterval(this.pingTimer);
      this.pingTimer = null;
    }
    if (this.reconnectTimer !== null) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    if (this.port) {
      this.port.disconnect();
      this.port = null;
    }
  }

  private handleMessage(msg: HostResponse): void {
    switch (msg.type) {
      case "decision":
        this.onDecision(msg.decisions);
        break;
      case "context_bundle": {
        const bundle = msg.bundle;
        const resolves = this.pendingBundleResolves.splice(0);
        for (const resolve of resolves) resolve(bundle);
        this.onBundle(bundle);
        break;
      }
      case "pong":
        // heartbeat acknowledged — connection is alive
        break;
      case "error":
        console.error("[TabX] Native host error:", msg.message);
        break;
      default:
        console.warn("[TabX] Unknown message from host:", msg);
    }
  }
}

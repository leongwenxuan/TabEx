import type {
  HostRequest,
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
  decisions: Array<{ tabId: number; decision: TabDecision; score: number; summary?: string; insights?: string[] }>
) => void;

type BundleCallback = (bundle: ContextBundle) => void;

type HostTabPayload = {
  tabId: number;
  url: string;
  title: string;
  timeSpentSeconds: number;
  scrollDepth: number;
  selectedText: string | null;
  contentDigest: string | null;
  lastVisitedAt: string;
  isActive: boolean;
};

type DecisionPayload = { tabId: number; decision: TabDecision; score: number; summary?: string; insights?: string[] };

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
        this.handleMessage(msg);
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
    const payload: HostTabPayload[] = tabs.map((tab) => ({
      tabId: tab.tabId,
      url: tab.url,
      title: tab.title,
      timeSpentSeconds: tab.timeSpentMs / 1000,
      scrollDepth: tab.scrollDepth,
      selectedText: tab.selections.at(-1) ?? null,
      contentDigest: tab.contentDigest || null,
      lastVisitedAt: new Date(tab.lastActivatedAt).toISOString(),
      // The extension does not currently store active status per tab in TabInfo.
      isActive: false,
    }));
    this.send({ type: "tab_update", tabs: payload } as unknown as HostRequest);
  }

  requestContextBundle(): Promise<ContextBundle> {
    return new Promise((resolve) => {
      this.pendingBundleResolves.push(resolve);
      const sent = this.send({ type: "request_bundle" } as unknown as HostRequest);
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

  private handleMessage(msg: unknown): void {
    if (!isRecord(msg) || typeof msg.type !== "string") {
      console.warn("[TabX] Malformed message from native host:", msg);
      return;
    }

    switch (msg.type) {
      // Legacy response shape
      case "decision":
        if (Array.isArray(msg.decisions)) {
          this.onDecision(parseDecisions(msg.decisions));
        }
        break;

      // Current host response shape
      case "decisions":
        if (Array.isArray(msg.results)) {
          this.onDecision(parseDecisions(msg.results));
        }
        break;

      // Legacy response shape
      case "context_bundle":
        this.resolveBundle(msg.bundle);
        break;

      // Current host response shape
      case "bundle":
        this.resolveBundle(msg.bundle);
        break;

      case "pong":
        // heartbeat acknowledged — connection is alive
        break;

      case "error": {
        const message =
          typeof msg.message === "string"
            ? msg.message
            : typeof msg.error === "string"
              ? msg.error
              : "unknown";
        console.error("[TabX] Native host error:", message);
        break;
      }

      default:
        console.warn("[TabX] Unknown message from host:", msg);
    }
  }

  private resolveBundle(rawBundle: unknown): void {
    const bundle = normalizeBundle(rawBundle);
    const resolves = this.pendingBundleResolves.splice(0);
    for (const resolve of resolves) resolve(bundle);
    this.onBundle(bundle);
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function parseDecisions(input: unknown[]): DecisionPayload[] {
  const parsed: DecisionPayload[] = [];
  for (const item of input) {
    if (!isRecord(item)) continue;
    const tabId = typeof item.tabId === "number" ? item.tabId : null;
    const score = typeof item.score === "number" ? item.score : null;
    const decision = item.decision;
    if (
      tabId !== null &&
      score !== null &&
      (decision === "close" || decision === "keep" || decision === "flag")
    ) {
      const summary = typeof item.summary === "string" ? item.summary : undefined;
      const insights = Array.isArray(item.insights)
        ? item.insights.filter((s): s is string => typeof s === "string")
        : undefined;
      parsed.push({ tabId, score, decision, summary, insights });
    }
  }
  return parsed;
}

function normalizeBundle(raw: unknown): ContextBundle {
  const empty: ContextBundle = {
    pagesRead: [],
    highlights: [],
    survivingTabs: [],
    generatedAt: Date.now(),
  };

  if (!isRecord(raw)) return empty;

  // Already in extension-native shape
  if (
    Array.isArray(raw.pagesRead) &&
    Array.isArray(raw.highlights) &&
    Array.isArray(raw.survivingTabs) &&
    typeof raw.generatedAt === "number"
  ) {
    return raw as unknown as ContextBundle;
  }

  // Host shape from Swift: pagesRead + survivingTabs + generatedAt (ISO8601 string)
  const pagesRead = Array.isArray(raw.pagesRead) ? raw.pagesRead : [];
  const survivingTabs = Array.isArray(raw.survivingTabs) ? raw.survivingTabs : [];

  const normalizedPages = pagesRead
    .filter(isRecord)
    .map((page) => ({
      url: typeof page.url === "string" ? page.url : "",
      title: typeof page.title === "string" ? page.title : "",
      digest: typeof page.contentDigest === "string" ? page.contentDigest : "",
    }))
    .filter((page) => page.url.length > 0);

  const normalizedHighlights = pagesRead
    .filter(isRecord)
    .flatMap((page) => {
      const url = typeof page.url === "string" ? page.url : "";
      const highlights = Array.isArray(page.highlights) ? page.highlights : [];
      return highlights
        .filter((h): h is string => typeof h === "string")
        .map((text) => ({ url, text }));
    });

  const normalizedSurviving = survivingTabs
    .filter(isRecord)
    .map((tab) => ({
      tabId: typeof tab.tabId === "number" ? tab.tabId : -1,
      url: typeof tab.url === "string" ? tab.url : "",
      title: typeof tab.title === "string" ? tab.title : "",
      score: typeof tab.score === "number" ? tab.score : 0,
    }))
    .filter((tab) => tab.tabId >= 0 && tab.url.length > 0);

  const generatedAt =
    typeof raw.generatedAt === "string"
      ? Date.parse(raw.generatedAt)
      : typeof raw.generatedAt === "number"
        ? raw.generatedAt
        : Date.now();

  return {
    pagesRead: normalizedPages,
    highlights: normalizedHighlights,
    survivingTabs: normalizedSurviving,
    generatedAt: Number.isFinite(generatedAt) ? generatedAt : Date.now(),
  };
}

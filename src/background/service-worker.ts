/**
 * TabX background service worker (Manifest V3).
 * Orchestrates tab tracking, native messaging, and popup communication.
 */

import { NativeClient } from "./native-client.js";
import { TabTracker } from "./tab-tracker.js";
import type {
  ContentMessage,
  DecisionPayload,
  ExtensionState,
  FromHostMessage,
  PopupMessage,
  UserSettings,
} from "../types/index.js";
import { DEFAULT_SETTINGS } from "../types/index.js";

// ─── State ────────────────────────────────────────────────────────────────────

let settings: UserSettings = { ...DEFAULT_SETTINGS };
let tracker: TabTracker = new TabTracker(settings);
let connected = false;

// ─── Native client ────────────────────────────────────────────────────────────

const nativeClient = new NativeClient(
  (msg: FromHostMessage) => {
    if (msg.type === "connection_ack") {
      console.log("[TabX] Native host connected:", msg.version);
      connected = true;
    } else if (msg.type === "decision") {
      handleDecision(msg);
    }
  },
  (err?: string) => {
    console.warn("[TabX] Native host disconnected:", err ?? "unknown");
    connected = false;
  }
);

// ─── Decision handler ─────────────────────────────────────────────────────────

async function handleDecision(payload: DecisionPayload): Promise<void> {
  const { tabId, decision, score } = payload;
  tracker.applyDecision(tabId, decision, score);

  if (decision === "close" && settings.autoClose) {
    const tab = tracker.getTabSnapshot(tabId);
    if (tab && !tracker.isProtected(tab.url)) {
      try {
        await chrome.tabs.remove(tabId);
      } catch {
        // Tab may already be closed
      }
    }
  }
}

// ─── Settings ─────────────────────────────────────────────────────────────────

async function loadSettings(): Promise<void> {
  const result = await chrome.storage.local.get("settings");
  if (result["settings"]) {
    settings = { ...DEFAULT_SETTINGS, ...(result["settings"] as UserSettings) };
  }
  tracker.updateSettings(settings);
}

async function saveSettings(newSettings: UserSettings): Promise<void> {
  settings = newSettings;
  tracker.updateSettings(settings);
  await chrome.storage.local.set({ settings });
}

// ─── Tab event listeners ──────────────────────────────────────────────────────

chrome.tabs.onCreated.addListener((tab) => {
  tracker.onTabCreated(tab);
  if (tab.id !== undefined) {
    const snapshot = tracker.getTabSnapshot(tab.id);
    if (snapshot) {
      nativeClient.send({ type: "tab_update", tab: snapshot });
    }
  }
});

chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  tracker.onTabUpdated(tabId, changeInfo, tab);
  if (changeInfo.status === "complete") {
    const snapshot = tracker.getTabSnapshot(tabId);
    if (snapshot) {
      nativeClient.send({ type: "tab_update", tab: snapshot });
    }
  }
});

chrome.tabs.onActivated.addListener(({ tabId }) => {
  tracker.onTabActivated(tabId);
});

chrome.tabs.onRemoved.addListener((tabId) => {
  const closed = tracker.onTabRemoved(tabId);
  if (closed) {
    nativeClient.send({
      type: "tab_close",
      tabId: closed.tabId,
      url: closed.url,
      title: closed.title,
    });
  }
});

// ─── Content script messages ──────────────────────────────────────────────────

chrome.runtime.onMessage.addListener(
  (
    message: ContentMessage | PopupMessage,
    sender: chrome.runtime.MessageSender,
    sendResponse: (response: ExtensionState | boolean) => void
  ) => {
    const msg = message as ContentMessage | PopupMessage;

    if (msg.type === "content_scroll") {
      const tabId = sender.tab?.id ?? msg.tabId;
      if (tabId !== undefined) {
        tracker.updateScrollDepth(tabId, msg.scrollDepth);
      }
      return;
    }

    if (msg.type === "content_selection") {
      const tabId = sender.tab?.id ?? msg.tabId;
      if (tabId !== undefined) {
        tracker.addTextSelection(tabId, msg.text);
        // Send updated snapshot to host
        const snapshot = tracker.getTabSnapshot(tabId);
        if (snapshot) {
          nativeClient.send({ type: "tab_update", tab: snapshot });
        }
      }
      return;
    }

    if (msg.type === "content_digest") {
      const tabId = sender.tab?.id ?? msg.tabId;
      if (tabId !== undefined) {
        tracker.updateContentDigest(tabId, msg.digest);
        // Send full update once digest is ready
        const snapshot = tracker.getTabSnapshot(tabId);
        if (snapshot) {
          nativeClient.send({ type: "tab_update", tab: snapshot });
        }
      }
      return;
    }

    if (msg.type === "popup_get_state") {
      const state: ExtensionState = {
        connected,
        tabs: tracker.getAllTabs(),
        recentlyClosed: tracker.getRecentlyClosed(),
        settings,
      };
      sendResponse(state);
      return true; // async response
    }

    if (msg.type === "popup_undo_close") {
      const closed = tracker.popClosedTab(msg.index);
      if (closed) {
        chrome.tabs.create({ url: closed.url, active: false }).catch(() => {});
        sendResponse(true);
      } else {
        sendResponse(false);
      }
      return true;
    }

    if (msg.type === "popup_apply_decision") {
      const { tabId, decision } = msg;
      tracker.applyDecision(tabId, decision, 0);
      if (decision === "close") {
        const tab = tracker.getTabSnapshot(tabId);
        if (tab && !tracker.isProtected(tab.url)) {
          chrome.tabs.remove(tabId).catch(() => {});
        }
      }
      sendResponse(true);
      return true;
    }

    return false;
  }
);

// ─── Settings messages from options page ──────────────────────────────────────

chrome.runtime.onMessage.addListener(
  (
    message: { type: string; settings?: UserSettings },
    _sender: chrome.runtime.MessageSender,
    sendResponse: (response: unknown) => void
  ) => {
    if (message.type === "options_save_settings" && message.settings) {
      saveSettings(message.settings).then(() => sendResponse({ ok: true }));
      return true;
    }
    if (message.type === "options_get_settings") {
      sendResponse({ settings });
      return true;
    }
    return false;
  }
);

// ─── Initialization ───────────────────────────────────────────────────────────

async function init(): Promise<void> {
  await loadSettings();

  // Seed tracker with any already-open tabs
  const openTabs = await chrome.tabs.query({});
  for (const tab of openTabs) {
    tracker.onTabCreated(tab);
  }

  // Get active tab
  const [activeTab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (activeTab?.id !== undefined) {
    tracker.onTabActivated(activeTab.id);
  }

  nativeClient.connect();
}

init().catch((err) => console.error("[TabX] Init error:", err));

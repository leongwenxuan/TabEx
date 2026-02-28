/**
 * TabX Background Service Worker (Manifest V3)
 *
 * Orchestrates:
 * - Tab lifecycle tracking (open/close/activate/update)
 * - Native messaging with the Swift host
 * - Decision management (close/keep/flag from host)
 * - Undo/resurrect for recently closed tabs
 * - Popup command handling
 */

import { TabTracker } from "./tab-tracker.js";
import { NativeMessagingClient } from "./native-client.js";
import { DecisionManager } from "./decision-manager.js";
import { UndoManager } from "./undo-manager.js";
import {
  getStorage,
  getConfig,
  updateConfig,
  addDontCloseRule,
  removeDontCloseRule,
  setConnectionStatus,
  setPendingRestore,
} from "./storage.js";
import type {
  ContentReadingMessage,
  PopupCommand,
  PopupStateMessage,
  TabDecision,
} from "../shared/types.js";

// ─── Core instances ───────────────────────────────────────────────────────────

const nativeClient = new NativeMessagingClient(
  handleDecisions,
  (_bundle) => {
    // Bundle received — no action needed here; resolved via requestContextBundle()
  }
);

nativeClient.setSessionSwitchHandler(async (info) => {
  if (!info.hasSavedSession) return;

  const config = await getConfig();
  if (config.autoRestore && info.incomingKey) {
    // Auto-restore: send restore command immediately, no banner needed
    nativeClient.sendRestoreSession(info.incomingKey);
    await setPendingRestore(null);
  } else {
    // Manual restore: show the banner in the popup
    await setPendingRestore(info);
  }
  await broadcastPopupState();
});

const decisionManager = new DecisionManager(async (tabId: number) => {
  try {
    await chrome.tabs.remove(tabId);
  } catch {
    // tab may already be gone
  }
});

const undoManager = new UndoManager();

const tabTracker = new TabTracker(async (tabs) => {
  nativeClient.sendTabData(tabs);
});

// ─── Decision handler (called from native client) ─────────────────────────────

async function handleDecisions(
  decisions: Array<{ tabId: number; decision: TabDecision; score: number; summary?: string; insights?: string[] }>,
  context?: { branchSwitch: boolean }
): Promise<void> {
  const forceClose = context?.branchSwitch ?? false;
  await decisionManager.processDecisions(decisions, { forceClose });
  await broadcastPopupState();
}

// ─── Tab event listeners ──────────────────────────────────────────────────────

chrome.tabs.onCreated.addListener((tab) => {
  void tabTracker.onTabCreated(tab);
});

chrome.tabs.onActivated.addListener((activeInfo) => {
  void tabTracker.onTabActivated(activeInfo);
});

chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (changeInfo.status === "complete" || changeInfo.url) {
    void tabTracker.onTabUpdated(tabId, changeInfo, tab);
  }
});

chrome.tabs.onRemoved.addListener((tabId, removeInfo) => {
  void tabTracker.onTabRemoved(tabId, removeInfo);
  void broadcastPopupState();
});

// ─── Content script messages ──────────────────────────────────────────────────

chrome.runtime.onMessage.addListener((msg: unknown, sender, sendResponse) => {
  const message = msg as ContentReadingMessage | PopupCommand;

  if ("type" in message && message.type === "reading_data") {
    const reading = message as ContentReadingMessage;
    const tabId = sender.tab?.id;
    if (tabId !== undefined) {
      void tabTracker
        .onReadingData(
          tabId,
          reading.data.scrollDepth,
          reading.data.selections,
          reading.data.contentDigest
        )
        .then(() => broadcastPopupState());
    }
    return false;
  }

  // Popup commands — handle async and send response
  void handlePopupCommand(message as PopupCommand, sendResponse);
  return true; // keep message channel open for async response
});

// ─── Popup command handler ────────────────────────────────────────────────────

async function handlePopupCommand(
  cmd: PopupCommand,
  sendResponse: (response: unknown) => void
): Promise<void> {
  switch (cmd.type) {
    case "get_state": {
      const state = await buildPopupState();
      sendResponse(state);
      break;
    }

    case "undo_close": {
      const result = await undoManager.resurrect(cmd.tabId);
      sendResponse(result);
      await broadcastPopupState();
      break;
    }

    case "update_config": {
      await updateConfig(cmd.config);
      sendResponse({ ok: true });
      await broadcastPopupState();
      break;
    }

    case "add_dont_close_rule": {
      const rule = await addDontCloseRule(cmd.rule);
      sendResponse({ ok: true, rule });
      await broadcastPopupState();
      break;
    }

    case "remove_dont_close_rule": {
      await removeDontCloseRule(cmd.ruleId);
      sendResponse({ ok: true });
      await broadcastPopupState();
      break;
    }

    case "dismiss_decision": {
      await decisionManager.dismissDecision(cmd.tabId);
      sendResponse({ ok: true });
      await broadcastPopupState();
      break;
    }

    case "get_context_bundle": {
      const bundle = await nativeClient.requestContextBundle();
      sendResponse({ ok: true, bundle });
      break;
    }

    case "restore_session": {
      nativeClient.sendRestoreSession(cmd.sessionKey);
      await setPendingRestore(null);
      sendResponse({ ok: true });
      await broadcastPopupState();
      break;
    }

    case "dismiss_restore": {
      await setPendingRestore(null);
      sendResponse({ ok: true });
      await broadcastPopupState();
      break;
    }

    default:
      sendResponse({ ok: false, error: "unknown_command" });
  }
}

// ─── Popup state broadcasting ─────────────────────────────────────────────────

async function buildPopupState(): Promise<PopupStateMessage> {
  const storage = await getStorage();
  const tabs = Object.values(storage.tabs);
  return {
    type: "popup_state",
    tabs,
    closedTabs: storage.closedTabs,
    connectionStatus: storage.connectionStatus,
    config: storage.config,
    pendingRestore: storage.pendingRestore,
  };
}

async function broadcastPopupState(): Promise<void> {
  const state = await buildPopupState();
  try {
    await chrome.runtime.sendMessage(state);
  } catch {
    // Popup may not be open — ignore "Could not establish connection" errors
  }
}

// ─── Alarm for periodic tab time accrual ─────────────────────────────────────

chrome.alarms.create("accrue_time", { periodInMinutes: 1 });
chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === "accrue_time") {
    void tabTracker.accrueActiveTime();
  }
});

// ─── Service worker lifecycle ─────────────────────────────────────────────────

chrome.runtime.onInstalled.addListener(async () => {
  console.log("[TabX] Extension installed/updated.");
  await setConnectionStatus("disconnected");
  nativeClient.connect();
});

// Reconnect on service worker startup (after browser restart, etc.)
nativeClient.connect();

// Prune stale tabs from storage, then seed currently open tabs
void (async () => {
  await tabTracker.pruneStale();
  const tabs = await chrome.tabs.query({});
  for (const tab of tabs) {
    if (tab.id && tab.url) {
      await tabTracker.onTabCreated(tab);
    }
  }
})();

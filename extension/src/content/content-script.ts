/**
 * TabX Content Script
 *
 * Captures per-page reading signals using dedicated tracker modules:
 * - Scroll depth (0–1 fraction of page scrolled)
 * - Text selections made by the user
 * - Page content digest (first 500 chars of visible body text)
 *
 * Sends ReadingData to the background service worker on a 10-second interval
 * and on visibility change (page hidden).
 */

import type { ContentReadingMessage, ReadingData } from "../shared/types.js";
import { ScrollTracker } from "./scroll-tracker.js";
import { SelectionTracker } from "./selection-tracker.js";
import { getContentDigest } from "./content-digest.js";

// ─── Constants ────────────────────────────────────────────────────────────────

const SEND_INTERVAL_MS = 10_000;

// ─── State ────────────────────────────────────────────────────────────────────

let pendingSend = false;

const scrollTracker = new ScrollTracker(() => {
  scheduleSend();
});

const selectionTracker = new SelectionTracker(() => {
  scheduleSend();
});

// ─── Send to background ───────────────────────────────────────────────────────

function sendReadingData(): void {
  const data: ReadingData = {
    tabId: -1, // background will use sender.tab.id
    url: location.href,
    title: document.title,
    scrollDepth: scrollTracker.maxDepth,
    selections: selectionTracker.selections,
    contentDigest: getContentDigest(),
    timestamp: Date.now(),
  };

  const msg: ContentReadingMessage = { type: "reading_data", data };
  try {
    chrome.runtime.sendMessage(msg);
  } catch {
    // Extension context invalidated — stop sending
    clearInterval(sendTimer);
    scrollTracker.destroy();
    selectionTracker.destroy();
  }
  pendingSend = false;
}

function scheduleSend(): void {
  pendingSend = true;
}

// ─── Periodic send ────────────────────────────────────────────────────────────

const sendTimer = setInterval(() => {
  if (pendingSend) {
    sendReadingData();
  }
}, SEND_INTERVAL_MS);

// ─── Initial send ─────────────────────────────────────────────────────────────

if (document.readyState === "complete" || document.readyState === "interactive") {
  setTimeout(sendReadingData, 2000);
} else {
  window.addEventListener("DOMContentLoaded", () => {
    setTimeout(sendReadingData, 2000);
  });
}

// ─── Visibility change ────────────────────────────────────────────────────────

window.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "hidden") {
    sendReadingData();
  }
});

/**
 * TabX Content Script
 *
 * Captures per-page reading signals:
 * - Scroll depth (0–1 fraction of page scrolled)
 * - Text selections made by the user
 * - Page content digest (first 500 chars of body text, sensitive fields excluded)
 *
 * Sends ReadingData to the background service worker.
 */

import type { ContentReadingMessage, ReadingData } from "../shared/types.js";

// ─── Constants ────────────────────────────────────────────────────────────────

const SEND_INTERVAL_MS = 10_000;          // send updates every 10 s
const MAX_DIGEST_CHARS = 500;
const MAX_SELECTIONS = 20;
const MAX_SELECTION_LENGTH = 300;

// Sensitive field selectors — avoid capturing these
const SENSITIVE_SELECTORS = [
  'input[type="password"]',
  'input[type="email"]',
  'input[name*="card"]',
  'input[name*="cvv"]',
  'input[name*="ssn"]',
  '[data-sensitive]',
  'form[autocomplete="off"] input',
];

// ─── State ────────────────────────────────────────────────────────────────────

let maxScrollDepth = 0;
const selections: string[] = [];
let pendingSend = false;

// ─── Scroll tracking ──────────────────────────────────────────────────────────

function getScrollDepth(): number {
  const scrollTop = window.scrollY;
  const docHeight = document.documentElement.scrollHeight - window.innerHeight;
  if (docHeight <= 0) return 1;
  return Math.min(1, scrollTop / docHeight);
}

function onScroll(): void {
  const depth = getScrollDepth();
  if (depth > maxScrollDepth) {
    maxScrollDepth = depth;
  }
  scheduleSend();
}

window.addEventListener("scroll", onScroll, { passive: true });

// ─── Text selection tracking ──────────────────────────────────────────────────

function onSelectionChange(): void {
  const sel = window.getSelection();
  if (!sel || sel.rangeCount === 0) return;
  const text = sel.toString().trim();
  if (text.length < 10 || text.length > MAX_SELECTION_LENGTH) return;
  if (!isInsideSensitiveField(sel.anchorNode)) {
    if (!selections.includes(text)) {
      selections.push(text);
      if (selections.length > MAX_SELECTIONS) selections.shift();
      scheduleSend();
    }
  }
}

function isInsideSensitiveField(node: Node | null): boolean {
  if (!node) return false;
  let el: Element | null =
    node.nodeType === Node.ELEMENT_NODE
      ? (node as Element)
      : node.parentElement;
  while (el) {
    for (const selector of SENSITIVE_SELECTORS) {
      try {
        if (el.matches(selector)) return true;
      } catch {
        // ignore invalid selectors
      }
    }
    el = el.parentElement;
  }
  return false;
}

document.addEventListener("selectionchange", onSelectionChange);

// ─── Page content digest ──────────────────────────────────────────────────────

function getContentDigest(): string {
  // Grab innerText from body, excluding scripts, styles, nav, footer
  const clone = document.body.cloneNode(true) as HTMLElement;

  // Remove non-content elements
  for (const selector of [
    "script",
    "style",
    "nav",
    "footer",
    "header",
    "aside",
    ...SENSITIVE_SELECTORS,
  ]) {
    clone.querySelectorAll(selector).forEach((el) => el.remove());
  }

  const text = clone.innerText ?? clone.textContent ?? "";
  return text.replace(/\s+/g, " ").trim().slice(0, MAX_DIGEST_CHARS);
}

// ─── Send to background ───────────────────────────────────────────────────────

function sendReadingData(): void {
  const data: ReadingData = {
    tabId: -1, // background will use sender.tab.id
    url: location.href,
    title: document.title,
    scrollDepth: maxScrollDepth,
    selections: [...selections],
    contentDigest: getContentDigest(),
    timestamp: Date.now(),
  };

  const msg: ContentReadingMessage = { type: "reading_data", data };
  try {
    chrome.runtime.sendMessage(msg);
  } catch {
    // Extension context invalidated (e.g. reloaded) — stop sending
    clearInterval(sendTimer);
  }
  pendingSend = false;
}

function scheduleSend(): void {
  if (!pendingSend) {
    pendingSend = true;
  }
}

// Send on interval
const sendTimer = setInterval(() => {
  if (pendingSend) {
    sendReadingData();
  }
}, SEND_INTERVAL_MS);

// Also send immediately on page load once DOM is ready
if (document.readyState === "complete" || document.readyState === "interactive") {
  setTimeout(sendReadingData, 2000);
} else {
  window.addEventListener("DOMContentLoaded", () => {
    setTimeout(sendReadingData, 2000);
  });
}

// Send on page unload to capture final state
window.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "hidden") {
    sendReadingData();
  }
});

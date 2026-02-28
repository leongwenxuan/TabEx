/**
 * TabX content script.
 * Runs in every page context to capture:
 * - Scroll depth
 * - Text selections
 * - Page content digest (title + headings + meta description)
 *
 * Communicates with the background service worker via chrome.runtime.sendMessage.
 */

import type {
  ContentDigestMessage,
  ContentScrollMessage,
  ContentSelectionMessage,
} from "../types/index.js";

// ─── Scroll depth tracking ────────────────────────────────────────────────────

let maxScrollDepth = 0;
let scrollDebounceTimer: ReturnType<typeof setTimeout> | null = null;

function computeScrollDepth(): number {
  const scrollTop = window.scrollY;
  const docHeight =
    document.documentElement.scrollHeight - window.innerHeight;
  if (docHeight <= 0) return 1;
  return Math.min(1, scrollTop / docHeight);
}

function onScroll(): void {
  if (scrollDebounceTimer !== null) {
    clearTimeout(scrollDebounceTimer);
  }
  scrollDebounceTimer = setTimeout(() => {
    const depth = computeScrollDepth();
    if (depth > maxScrollDepth) {
      maxScrollDepth = depth;
      const msg: ContentScrollMessage = {
        type: "content_scroll",
        scrollDepth: maxScrollDepth,
        url: location.href,
      };
      chrome.runtime.sendMessage(msg).catch(() => {});
    }
  }, 300);
}

window.addEventListener("scroll", onScroll, { passive: true });

// ─── Text selection tracking ──────────────────────────────────────────────────

let selectionDebounceTimer: ReturnType<typeof setTimeout> | null = null;

function onSelectionChange(): void {
  if (selectionDebounceTimer !== null) {
    clearTimeout(selectionDebounceTimer);
  }
  selectionDebounceTimer = setTimeout(() => {
    const text = window.getSelection()?.toString().trim() ?? "";
    if (text.length > 10) {
      const msg: ContentSelectionMessage = {
        type: "content_selection",
        text,
        url: location.href,
      };
      chrome.runtime.sendMessage(msg).catch(() => {});
    }
  }, 400);
}

document.addEventListener("selectionchange", onSelectionChange);

// ─── Page content digest ──────────────────────────────────────────────────────

function buildDigest(): string {
  const parts: string[] = [];

  // Title
  const title = document.title.trim();
  if (title) parts.push(`TITLE: ${title}`);

  // Meta description
  const metaDesc = document.querySelector<HTMLMetaElement>(
    'meta[name="description"]'
  );
  if (metaDesc?.content) {
    parts.push(`DESC: ${metaDesc.content.slice(0, 200)}`);
  }

  // Open Graph title (often cleaner than <title>)
  const ogTitle = document.querySelector<HTMLMetaElement>(
    'meta[property="og:title"]'
  );
  if (ogTitle?.content && ogTitle.content !== title) {
    parts.push(`OG: ${ogTitle.content.slice(0, 200)}`);
  }

  // H1 headings
  const h1s = Array.from(document.querySelectorAll("h1"))
    .map((el) => el.textContent?.trim() ?? "")
    .filter(Boolean)
    .slice(0, 3);
  if (h1s.length) {
    parts.push(`H1: ${h1s.join(" | ")}`);
  }

  // H2 headings (first 5)
  const h2s = Array.from(document.querySelectorAll("h2"))
    .map((el) => el.textContent?.trim() ?? "")
    .filter(Boolean)
    .slice(0, 5);
  if (h2s.length) {
    parts.push(`H2: ${h2s.join(" | ")}`);
  }

  // First meaningful paragraph
  const firstPara = Array.from(document.querySelectorAll("p"))
    .map((el) => el.textContent?.trim() ?? "")
    .find((t) => t.length > 50);
  if (firstPara) {
    parts.push(`PARA: ${firstPara.slice(0, 300)}`);
  }

  return parts.join("\n").slice(0, 1000);
}

function sendDigest(): void {
  const digest = buildDigest();
  if (!digest) return;
  const msg: ContentDigestMessage = {
    type: "content_digest",
    digest,
    url: location.href,
  };
  chrome.runtime.sendMessage(msg).catch(() => {});
}

// Send digest when page is fully loaded
if (document.readyState === "complete") {
  sendDigest();
} else {
  window.addEventListener("load", sendDigest, { once: true });
}

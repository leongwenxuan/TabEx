/**
 * TabList component — renders open tabs and recently-closed tabs in the popup.
 *
 * Open tabs show title, URL, score badge, decision badge, and a dismiss action
 * for tabs flagged for closure.
 *
 * Closed tabs show title/URL with an Undo button that reopens the tab.
 */

import type { ClosedTabRecord, PopupCommand, TabInfo } from "../../shared/types.js";

function sendCommand(cmd: PopupCommand): void {
  chrome.runtime.sendMessage(cmd).catch(() => {
    // popup may have been unloaded
  });
}

// ─── Open tabs ────────────────────────────────────────────────────────────────

/**
 * Renders the list of open tracked tabs into `container`.
 * Replaces all previous children.
 */
export function renderTabList(container: HTMLElement, tabs: TabInfo[]): void {
  container.innerHTML = "";

  if (tabs.length === 0) {
    const empty = document.createElement("div");
    empty.className = "empty-state";
    empty.textContent = "No tabs tracked yet.";
    container.appendChild(empty);
    return;
  }

  for (const tab of tabs) {
    container.appendChild(createTabItem(tab));
  }
}

function createTabItem(tab: TabInfo): HTMLElement {
  const item = document.createElement("div");
  item.className = "tab-item";
  item.dataset["tabId"] = String(tab.tabId);

  // Favicon
  const favicon = document.createElement("img");
  favicon.className = "tab-favicon";
  try {
    favicon.src = `https://www.google.com/s2/favicons?domain=${new URL(tab.url).hostname}&sz=16`;
  } catch {
    favicon.style.display = "none";
  }
  favicon.addEventListener("error", () => {
    favicon.style.display = "none";
  });

  // Info block
  const info = document.createElement("div");
  info.className = "tab-info";

  const titleEl = document.createElement("div");
  titleEl.className = "tab-title";
  titleEl.textContent = tab.title || tab.url;

  const urlEl = document.createElement("div");
  urlEl.className = "tab-url";
  urlEl.textContent = tab.url;

  info.appendChild(titleEl);
  info.appendChild(urlEl);

  // Agent summary (2-line clamp)
  if (tab.summary) {
    const summaryEl = document.createElement("div");
    summaryEl.className = "tab-summary";
    summaryEl.textContent = tab.summary;
    info.appendChild(summaryEl);
  }

  // Agent insights (top 3 as small tags)
  if (tab.insights && tab.insights.length > 0) {
    const insightsEl = document.createElement("div");
    insightsEl.className = "tab-insights";
    for (const insight of tab.insights.slice(0, 3)) {
      const tag = document.createElement("span");
      tag.className = "insight-tag";
      tag.textContent = insight;
      insightsEl.appendChild(tag);
    }
    info.appendChild(insightsEl);
  }

  // Meta (score + decision badges)
  const meta = document.createElement("div");
  meta.className = "tab-meta";

  if (tab.score !== undefined) {
    const scoreBadge = document.createElement("span");
    scoreBadge.className = "score-badge";
    scoreBadge.textContent = String(Math.round(tab.score * 100));
    meta.appendChild(scoreBadge);
  }

  if (tab.decision) {
    const decBadge = document.createElement("span");
    decBadge.className = `decision-badge decision-${tab.decision}`;
    decBadge.textContent = tab.decision;
    meta.appendChild(decBadge);
  }

  // Actions
  const actions = document.createElement("div");
  actions.className = "tab-actions";

  if (tab.decision === "close" || tab.decision === "flag") {
    const keepBtn = document.createElement("button");
    keepBtn.className = "action-btn btn-keep";
    keepBtn.textContent = "Keep";
    keepBtn.addEventListener("click", () => {
      sendCommand({ type: "dismiss_decision", tabId: tab.tabId });
    });
    actions.appendChild(keepBtn);
  }

  item.appendChild(favicon);
  item.appendChild(info);
  item.appendChild(meta);
  item.appendChild(actions);

  return item;
}

// ─── Recently closed tabs ─────────────────────────────────────────────────────

/**
 * Renders the list of recently closed tabs into `container`.
 * Each entry has an Undo button to reopen the tab.
 */
export function renderClosedList(
  container: HTMLElement,
  closed: ClosedTabRecord[]
): void {
  container.innerHTML = "";

  if (closed.length === 0) {
    const empty = document.createElement("div");
    empty.className = "empty-state";
    empty.textContent = "No recently closed tabs.";
    container.appendChild(empty);
    return;
  }

  for (const record of closed) {
    container.appendChild(createClosedItem(record));
  }
}

function createClosedItem(record: ClosedTabRecord): HTMLElement {
  const item = document.createElement("div");
  item.className = "closed-item";

  const info = document.createElement("div");
  info.className = "tab-info";

  const titleEl = document.createElement("div");
  titleEl.className = "tab-title";
  titleEl.textContent = record.title || record.url;

  const urlEl = document.createElement("div");
  urlEl.className = "tab-url";
  urlEl.textContent = record.url;

  info.appendChild(titleEl);
  info.appendChild(urlEl);

  const undoBtn = document.createElement("button");
  undoBtn.className = "undo-btn";
  undoBtn.textContent = "Undo";
  undoBtn.addEventListener("click", () => {
    sendCommand({ type: "undo_close", tabId: record.tabId });
  });

  item.appendChild(info);
  item.appendChild(undoBtn);

  return item;
}

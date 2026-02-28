/**
 * Tab tracker: maintains in-memory state of open tabs and recently closed tabs.
 * Tracks time spent per tab, scroll depth, text selections, and content digests.
 */

import type {
  ClosedTabRecord,
  DontCloseRule,
  TabDecision,
  TabRecord,
  UserSettings,
} from "../types/index.js";

const MAX_SELECTIONS_PER_TAB = 20;
const MAX_DIGEST_LENGTH = 1000;

export class TabTracker {
  private tabs = new Map<number, TabRecord>();
  private recentlyClosed: ClosedTabRecord[] = [];
  private activeTabId: number | null = null;
  private activeTabStartMs: number | null = null;

  constructor(private settings: UserSettings) {}

  updateSettings(settings: UserSettings): void {
    this.settings = settings;
    this.pruneClosedHistory();
  }

  // Called when a tab is opened
  onTabCreated(tab: chrome.tabs.Tab): void {
    if (!tab.id || !tab.url) return;
    const now = Date.now();
    this.tabs.set(tab.id, {
      tabId: tab.id,
      url: tab.url,
      title: tab.title ?? "",
      openedAt: now,
      lastActivatedAt: now,
      totalActiveMs: 0,
      scrollDepth: 0,
      textSelected: [],
      contentDigest: "",
    });
  }

  // Called when tab URL or title updates
  onTabUpdated(
    tabId: number,
    changeInfo: chrome.tabs.TabChangeInfo,
    tab: chrome.tabs.Tab
  ): void {
    const record = this.tabs.get(tabId);
    if (!record) {
      // Tab may have been created before we started tracking
      if (tab.url) {
        this.onTabCreated(tab);
      }
      return;
    }
    if (changeInfo.url) {
      // URL changed – reset content tracking
      record.url = changeInfo.url;
      record.scrollDepth = 0;
      record.textSelected = [];
      record.contentDigest = "";
    }
    if (tab.title) {
      record.title = tab.title;
    }
  }

  // Called when a tab is activated (focused)
  onTabActivated(tabId: number): void {
    const now = Date.now();
    // Accumulate time for previously active tab
    if (this.activeTabId !== null && this.activeTabStartMs !== null) {
      const prev = this.tabs.get(this.activeTabId);
      if (prev) {
        prev.totalActiveMs += now - this.activeTabStartMs;
      }
    }
    this.activeTabId = tabId;
    this.activeTabStartMs = now;
    const tab = this.tabs.get(tabId);
    if (tab) {
      tab.lastActivatedAt = now;
    }
  }

  // Called when a tab is closed
  onTabRemoved(tabId: number): ClosedTabRecord | null {
    const now = Date.now();
    const record = this.tabs.get(tabId);
    if (!record) return null;

    // Finalize active time
    if (this.activeTabId === tabId && this.activeTabStartMs !== null) {
      record.totalActiveMs += now - this.activeTabStartMs;
      this.activeTabId = null;
      this.activeTabStartMs = null;
    }

    const closed: ClosedTabRecord = {
      ...record,
      closedAt: now,
      decision: record.decision ?? "close",
    };

    this.tabs.delete(tabId);
    this.recentlyClosed.unshift(closed);
    this.pruneClosedHistory();
    return closed;
  }

  // Content script updates
  updateScrollDepth(tabId: number, depth: number): void {
    const tab = this.tabs.get(tabId);
    if (tab) {
      tab.scrollDepth = Math.max(tab.scrollDepth, Math.min(1, depth));
    }
  }

  addTextSelection(tabId: number, text: string): void {
    const tab = this.tabs.get(tabId);
    if (!tab) return;
    const trimmed = text.trim().slice(0, 500);
    if (!trimmed || tab.textSelected.includes(trimmed)) return;
    tab.textSelected.push(trimmed);
    if (tab.textSelected.length > MAX_SELECTIONS_PER_TAB) {
      tab.textSelected.shift();
    }
  }

  updateContentDigest(tabId: number, digest: string): void {
    const tab = this.tabs.get(tabId);
    if (tab) {
      tab.contentDigest = digest.slice(0, MAX_DIGEST_LENGTH);
    }
  }

  // Apply a decision from the host
  applyDecision(tabId: number, decision: TabDecision, score: number): void {
    const tab = this.tabs.get(tabId);
    if (tab) {
      tab.decision = decision;
      tab.score = score;
    }
  }

  // Get a snapshot of a tab for sending to host
  getTabSnapshot(tabId: number): TabRecord | undefined {
    return this.tabs.get(tabId);
  }

  getAllTabs(): TabRecord[] {
    return Array.from(this.tabs.values());
  }

  getRecentlyClosed(): ClosedTabRecord[] {
    return [...this.recentlyClosed];
  }

  // Check if a tab URL matches a don't-close rule
  isProtected(url: string): boolean {
    for (const rule of this.settings.dontCloseRules) {
      if (matchesRule(url, rule)) return true;
    }
    return false;
  }

  // Remove a closed tab from history and return it (for undo/resurrect)
  popClosedTab(index: number): ClosedTabRecord | undefined {
    if (index < 0 || index >= this.recentlyClosed.length) return undefined;
    const [removed] = this.recentlyClosed.splice(index, 1);
    return removed;
  }

  private pruneClosedHistory(): void {
    const cutoff = Date.now() - this.settings.undoWindowMs;
    this.recentlyClosed = this.recentlyClosed.filter(
      (t) => t.closedAt > cutoff
    );
  }
}

function matchesRule(url: string, rule: DontCloseRule): boolean {
  try {
    const parsed = new URL(url);
    if (rule.type === "domain") {
      return (
        parsed.hostname === rule.value ||
        parsed.hostname.endsWith(`.${rule.value}`)
      );
    }
    if (rule.type === "url_pattern") {
      // Simple glob: * matches anything
      const escaped = rule.value.replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*");
      return new RegExp(`^${escaped}$`).test(url);
    }
  } catch {
    // Unparseable URL
  }
  return false;
}

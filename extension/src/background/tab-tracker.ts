import type { TabInfo, ClosedTabRecord, TabDecision } from "../shared/types.js";
import {
  getTabs,
  setTab,
  deleteTab,
  getTab,
  pushClosedTab,
  getConfig,
  matchesDontCloseRule,
} from "./storage.js";

const SCORE_FLUSH_DELAY_MS = 2_000; // debounce before sending to host

type FlushCallback = (tabs: TabInfo[]) => void;

export class TabTracker {
  private activeTabId: number | null = null;
  private activationTime: number | null = null;
  private flushTimer: ReturnType<typeof setTimeout> | null = null;
  private onFlush: FlushCallback;

  constructor(onFlush: FlushCallback) {
    this.onFlush = onFlush;
  }

  async onTabCreated(tab: chrome.tabs.Tab): Promise<void> {
    if (!tab.id || !tab.url) return;
    const info: TabInfo = {
      tabId: tab.id,
      url: tab.url ?? "",
      title: tab.title ?? "",
      openedAt: Date.now(),
      lastActivatedAt: Date.now(),
      timeSpentMs: 0,
      scrollDepth: 0,
      selections: [],
      contentDigest: "",
    };
    await setTab(info);
    this.scheduleFlush();
  }

  async onTabActivated(activeInfo: chrome.tabs.TabActiveInfo): Promise<void> {
    const now = Date.now();

    // Accrue time on previously active tab
    if (this.activeTabId !== null && this.activationTime !== null) {
      const prev = await getTab(this.activeTabId);
      if (prev) {
        prev.timeSpentMs += now - this.activationTime;
        await setTab(prev);
      }
    }

    this.activeTabId = activeInfo.tabId;
    this.activationTime = now;

    const tab = await getTab(activeInfo.tabId);
    if (tab) {
      tab.lastActivatedAt = now;
      await setTab(tab);
    }

    this.scheduleFlush();
  }

  async onTabUpdated(
    tabId: number,
    _changeInfo: chrome.tabs.TabChangeInfo,
    tab: chrome.tabs.Tab
  ): Promise<void> {
    if (!tab.url) return;
    const existing = await getTab(tabId);
    if (existing) {
      existing.url = tab.url;
      existing.title = tab.title ?? existing.title;
      await setTab(existing);
    } else {
      // Tab existed before extension was active
      await setTab({
        tabId,
        url: tab.url,
        title: tab.title ?? "",
        openedAt: Date.now(),
        lastActivatedAt: Date.now(),
        timeSpentMs: 0,
        scrollDepth: 0,
        selections: [],
        contentDigest: "",
      });
    }
    this.scheduleFlush();
  }

  async onTabRemoved(
    tabId: number,
    _removeInfo: chrome.tabs.TabRemoveInfo
  ): Promise<void> {
    if (this.activeTabId === tabId && this.activationTime !== null) {
      const prev = await getTab(tabId);
      if (prev) {
        prev.timeSpentMs += Date.now() - this.activationTime;
        await setTab(prev);
      }
      this.activeTabId = null;
      this.activationTime = null;
    }

    const tab = await getTab(tabId);
    if (tab) {
      const record: ClosedTabRecord = {
        tabId: tab.tabId,
        url: tab.url,
        title: tab.title,
        closedAt: Date.now(),
        closedBy: "user",
        decision: tab.decision ?? "keep",
        score: tab.score ?? 0,
      };
      await pushClosedTab(record);
      await deleteTab(tabId);
    }
  }

  async onReadingData(
    tabId: number,
    scrollDepth: number,
    selections: string[],
    contentDigest: string
  ): Promise<void> {
    const tab = await getTab(tabId);
    if (!tab) return;
    tab.scrollDepth = Math.max(tab.scrollDepth, scrollDepth);
    tab.contentDigest = contentDigest;
    // Merge new selections, deduplicate, cap at 20
    const all = Array.from(new Set([...tab.selections, ...selections]));
    tab.selections = all.slice(0, 20);
    await setTab(tab);
    this.scheduleFlush();
  }

  async applyDecisions(
    decisions: Array<{ tabId: number; decision: TabDecision; score: number }>
  ): Promise<void> {
    const config = await getConfig();

    for (const { tabId, decision, score } of decisions) {
      const tab = await getTab(tabId);
      if (!tab) continue;

      tab.decision = decision;
      tab.score = score;
      await setTab(tab);

      if (
        decision === "close" &&
        config.autoClose &&
        !matchesDontCloseRule(tab.url, config.dontCloseRules)
      ) {
        // Push to closed-tabs undo list before removing
        const record: ClosedTabRecord = {
          tabId: tab.tabId,
          url: tab.url,
          title: tab.title,
          closedAt: Date.now(),
          closedBy: "tabx",
          decision,
          score,
        };
        await pushClosedTab(record);
        await deleteTab(tabId);
        try {
          await chrome.tabs.remove(tabId);
        } catch {
          // tab may already be gone
        }
      }
    }
  }

  async getAllTabs(): Promise<TabInfo[]> {
    const tabs = await getTabs();
    return Object.values(tabs);
  }

  private scheduleFlush(): void {
    if (this.flushTimer !== null) clearTimeout(this.flushTimer);
    this.flushTimer = setTimeout(async () => {
      const tabs = await this.getAllTabs();
      if (tabs.length > 0) this.onFlush(tabs);
    }, SCORE_FLUSH_DELAY_MS);
  }

  /** Snapshot current active tab's time on demand */
  async accrueActiveTime(): Promise<void> {
    if (this.activeTabId === null || this.activationTime === null) return;
    const now = Date.now();
    const tab = await getTab(this.activeTabId);
    if (tab) {
      tab.timeSpentMs += now - this.activationTime;
      await setTab(tab);
      this.activationTime = now;
    }
  }
}

import type { TabDecision, TabInfo } from "../shared/types.js";
import { getConfig, getTab, setTab, matchesDontCloseRule, pushClosedTab, getTabs } from "./storage.js";
import type { ClosedTabRecord } from "../shared/types.js";

export interface TabDecisionResult {
  tabId: number;
  decision: TabDecision;
  score: number;
  applied: boolean;
  reason?: string;
}

export class DecisionManager {
  private onAutoClose: (tabId: number) => Promise<void>;

  constructor(onAutoClose: (tabId: number) => Promise<void>) {
    this.onAutoClose = onAutoClose;
  }

  /**
   * Process decisions from the native host and apply them to tracked tabs.
   * Respects safelist rules and autoClose config.
   */
  async processDecisions(
    decisions: Array<{ tabId: number; decision: TabDecision; score: number; summary?: string; insights?: string[] }>
  ): Promise<TabDecisionResult[]> {
    const config = await getConfig();
    const results: TabDecisionResult[] = [];

    for (const { tabId, decision, score, summary, insights } of decisions) {
      const tab = await getTab(tabId);
      if (!tab) {
        results.push({ tabId, decision, score, applied: false, reason: "tab_not_found" });
        continue;
      }

      // Update decision + score + agent fields on tab record
      tab.decision = decision;
      tab.score = score;
      if (summary !== undefined) tab.summary = summary;
      if (insights !== undefined) tab.insights = insights;
      await setTab(tab);

      // Check safelist
      if (matchesDontCloseRule(tab.url, config.dontCloseRules)) {
        results.push({ tabId, decision, score, applied: false, reason: "safelisted" });
        continue;
      }

      // Apply auto-close if enabled and decision is close
      if (decision === "close" && config.autoClose) {
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
        await this.onAutoClose(tabId);
        results.push({ tabId, decision, score, applied: true });
      } else {
        // Decision stored but not auto-applied — popup will show it
        results.push({ tabId, decision, score, applied: false, reason: "auto_close_disabled" });
      }
    }

    return results;
  }

  /** Check if a tab URL is currently safelisted */
  async isSafelisted(url: string): Promise<boolean> {
    const config = await getConfig();
    return matchesDontCloseRule(url, config.dontCloseRules);
  }

  /** Get all tabs with pending decisions (close/flag) that haven't been auto-applied */
  async getPendingDecisions(): Promise<TabInfo[]> {
    const tabs = await getTabs();
    return Object.values(tabs).filter(
      (t) => t.decision === "close" || t.decision === "flag"
    );
  }

  /** Clear the decision from a tab (e.g. user dismisses it in popup) */
  async dismissDecision(tabId: number): Promise<void> {
    const tab = await getTab(tabId);
    if (!tab) return;
    tab.decision = undefined;
    await setTab(tab);
  }
}

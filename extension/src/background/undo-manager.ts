import type { ClosedTabRecord } from "../shared/types.js";
import { getClosedTabs, removeClosedTab } from "./storage.js";

export interface ResurrectResult {
  success: boolean;
  tabId?: number;
  url: string;
  reason?: string;
}

export class UndoManager {
  /**
   * Resurrect a recently-closed tab by its original tabId.
   * Opens a new tab at the same URL and removes the record from the undo list.
   */
  async resurrect(closedTabId: number): Promise<ResurrectResult> {
    const record = await removeClosedTab(closedTabId);
    if (!record) {
      return { success: false, url: "", reason: "not_found" };
    }

    try {
      const tab = await chrome.tabs.create({ url: record.url, active: false });
      return { success: true, tabId: tab.id, url: record.url };
    } catch (err) {
      return {
        success: false,
        url: record.url,
        reason: err instanceof Error ? err.message : "unknown",
      };
    }
  }

  /** Get the list of recently-closed tabs available for undo/resurrect */
  async getClosedTabs(): Promise<ClosedTabRecord[]> {
    return getClosedTabs();
  }

  /** Check whether a tab can be resurrected */
  async canResurrect(closedTabId: number): Promise<boolean> {
    const closed = await getClosedTabs();
    return closed.some((r) => r.tabId === closedTabId);
  }
}

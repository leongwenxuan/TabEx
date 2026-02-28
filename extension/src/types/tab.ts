// Tab-related types for TabX Chrome Extension

export type TabDecision = "close" | "keep" | "flag";

export interface TabInfo {
  tabId: number;
  url: string;
  title: string;
  openedAt: number;        // timestamp ms
  lastActivatedAt: number; // timestamp ms
  timeSpentMs: number;     // accumulated active time
  scrollDepth: number;     // 0-1 fraction of page scrolled
  selections: string[];    // text selections made on page
  contentDigest: string;   // first 500 chars of page text
  decision?: TabDecision | undefined;
  score?: number | undefined; // 0-1 relevance score from host
}

export interface TabEvent {
  type: "tab_opened" | "tab_closed" | "tab_activated" | "tab_updated";
  tabId: number;
  url?: string | undefined;
  title?: string | undefined;
  timestamp: number;
}

export interface ReadingData {
  tabId: number;
  url: string;
  title: string;
  scrollDepth: number;
  selections: string[];
  contentDigest: string;
  timestamp: number;
}

export interface ClosedTabRecord {
  tabId: number;
  url: string;
  title: string;
  closedAt: number;
  closedBy: "tabx" | "user";
  decision: TabDecision;
  score: number;
}

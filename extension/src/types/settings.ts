// Settings and config types for TabX Chrome Extension

import type { TabInfo, ClosedTabRecord } from "./tab.js";
import type { SessionSwitchInfo } from "./session.js";

export type ConnectionStatus = "connected" | "disconnected" | "error";

export interface DontCloseRule {
  id: string;
  type: "domain" | "url_prefix" | "url_pattern";
  value: string;
  label?: string | undefined;
}

export interface UserConfig {
  tabLimit: number | null;          // max tabs before auto-close
  dontCloseRules: DontCloseRule[];  // safelist patterns
  autoClose: boolean;               // whether to auto-close flagged tabs
  autoRestore: boolean;              // whether to auto-restore branch sessions on switch
  scoringEnabled: boolean;
}

export interface ContextBundle {
  pagesRead: Array<{ url: string; title: string; digest: string }>;
  highlights: Array<{ url: string; text: string }>;
  survivingTabs: Array<{ tabId: number; url: string; title: string; score: number }>;
  generatedAt: number;
}

export interface StorageSchema {
  config: UserConfig;
  tabs: Record<string, TabInfo>;           // keyed by tabId string
  closedTabs: ClosedTabRecord[];           // recent closed tabs for undo
  connectionStatus: ConnectionStatus;
  lastBundleAt: number | null;
  pendingRestore: SessionSwitchInfo | null;
}

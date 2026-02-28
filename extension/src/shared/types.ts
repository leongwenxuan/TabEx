// Shared types for TabX Chrome Extension

export type TabDecision = "close" | "keep" | "flag";

export type ConnectionStatus = "connected" | "disconnected" | "error";

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
  decision?: TabDecision;
  score?: number;          // 0-1 relevance score from host
}

export interface TabEvent {
  type: "tab_opened" | "tab_closed" | "tab_activated" | "tab_updated";
  tabId: number;
  url?: string;
  title?: string;
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

// Native messaging protocol messages (extension → host)
export type HostRequestType =
  | "tab_data"
  | "get_context_bundle"
  | "ping";

export interface TabDataRequest {
  type: "tab_data";
  tabs: TabInfo[];
  timestamp: number;
}

export interface GetContextBundleRequest {
  type: "get_context_bundle";
  timestamp: number;
}

export interface PingRequest {
  type: "ping";
  timestamp: number;
}

export type HostRequest =
  | TabDataRequest
  | GetContextBundleRequest
  | PingRequest;

// Native messaging protocol messages (host → extension)
export interface DecisionResponse {
  type: "decision";
  decisions: Array<{ tabId: number; decision: TabDecision; score: number }>;
  timestamp: number;
}

export interface ContextBundleResponse {
  type: "context_bundle";
  bundle: ContextBundle;
  timestamp: number;
}

export interface PongResponse {
  type: "pong";
  timestamp: number;
}

export interface ErrorResponse {
  type: "error";
  message: string;
  timestamp: number;
}

export type HostResponse =
  | DecisionResponse
  | ContextBundleResponse
  | PongResponse
  | ErrorResponse;

export interface ContextBundle {
  pagesRead: Array<{ url: string; title: string; digest: string }>;
  highlights: Array<{ url: string; text: string }>;
  survivingTabs: Array<{ tabId: number; url: string; title: string; score: number }>;
  generatedAt: number;
}

// Extension storage schema
export interface UserConfig {
  tabLimit: number | null;          // max tabs before auto-close
  dontCloseRules: DontCloseRule[];  // safelist patterns
  autoClose: boolean;               // whether to auto-close flagged tabs
  scoringEnabled: boolean;
}

export interface DontCloseRule {
  id: string;
  type: "domain" | "url_prefix" | "url_pattern";
  value: string;
  label?: string;
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

export interface StorageSchema {
  config: UserConfig;
  tabs: Record<string, TabInfo>;           // keyed by tabId string
  closedTabs: ClosedTabRecord[];           // recent closed tabs for undo
  connectionStatus: ConnectionStatus;
  lastBundleAt: number | null;
}

// Content script → background messages
export interface ContentReadingMessage {
  type: "reading_data";
  data: ReadingData;
}

// Background → popup messages
export interface PopupStateMessage {
  type: "popup_state";
  tabs: TabInfo[];
  closedTabs: ClosedTabRecord[];
  connectionStatus: ConnectionStatus;
  config: UserConfig;
}

// Popup → background commands
export type PopupCommand =
  | { type: "undo_close"; tabId: number }
  | { type: "update_config"; config: Partial<UserConfig> }
  | { type: "add_dont_close_rule"; rule: Omit<DontCloseRule, "id"> }
  | { type: "remove_dont_close_rule"; ruleId: string }
  | { type: "get_state" }
  | { type: "get_context_bundle" }
  | { type: "dismiss_decision"; tabId: number };

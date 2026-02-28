// Shared TypeScript types for TabX Chrome Extension

export type TabDecision = "keep" | "close" | "flag";

export interface TabRecord {
  tabId: number;
  url: string;
  title: string;
  openedAt: number;
  lastActivatedAt: number;
  totalActiveMs: number;
  scrollDepth: number; // 0–1
  textSelected: string[];
  contentDigest: string;
  decision?: TabDecision;
  score?: number;
}

export interface ClosedTabRecord extends TabRecord {
  closedAt: number;
  decision: TabDecision;
}

export interface TabUpdatePayload {
  type: "tab_update";
  tab: TabRecord;
}

export interface TabClosePayload {
  type: "tab_close";
  tabId: number;
  url: string;
  title: string;
}

export interface BatchUpdatePayload {
  type: "batch_update";
  tabs: TabRecord[];
}

export type ToHostMessage = TabUpdatePayload | TabClosePayload | BatchUpdatePayload;

export interface DecisionPayload {
  type: "decision";
  tabId: number;
  decision: TabDecision;
  score: number;
}

export interface ConnectionAckPayload {
  type: "connection_ack";
  version: string;
}

export type FromHostMessage = DecisionPayload | ConnectionAckPayload;

// Content script → background messages
export interface ContentScrollMessage {
  type: "content_scroll";
  tabId?: number;
  scrollDepth: number;
  url: string;
}

export interface ContentSelectionMessage {
  type: "content_selection";
  tabId?: number;
  text: string;
  url: string;
}

export interface ContentDigestMessage {
  type: "content_digest";
  tabId?: number;
  digest: string;
  url: string;
}

export type ContentMessage =
  | ContentScrollMessage
  | ContentSelectionMessage
  | ContentDigestMessage;

// Popup → background messages
export interface PopupGetStateMessage {
  type: "popup_get_state";
}

export interface PopupUndoCloseMessage {
  type: "popup_undo_close";
  index: number;
}

export interface PopupApplyDecisionMessage {
  type: "popup_apply_decision";
  tabId: number;
  decision: TabDecision;
}

export type PopupMessage =
  | PopupGetStateMessage
  | PopupUndoCloseMessage
  | PopupApplyDecisionMessage;

// State sent back to popup
export interface ExtensionState {
  connected: boolean;
  tabs: TabRecord[];
  recentlyClosed: ClosedTabRecord[];
  settings: UserSettings;
}

// User settings
export interface DontCloseRule {
  id: string;
  type: "domain" | "url_pattern";
  value: string;
}

export interface UserSettings {
  tabLimit: number | null; // null = no limit
  dontCloseRules: DontCloseRule[];
  autoClose: boolean; // whether to auto-close on host decision
  undoWindowMs: number; // how long to keep closed tab history
}

export const DEFAULT_SETTINGS: UserSettings = {
  tabLimit: null,
  dontCloseRules: [],
  autoClose: false,
  undoWindowMs: 30 * 60 * 1000, // 30 minutes
};

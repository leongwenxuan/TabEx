// Message types for TabX Chrome Extension native messaging and popup protocol

import type { TabDecision, TabInfo, ReadingData, ClosedTabRecord } from "./tab.js";
import type { ContextBundle, ConnectionStatus, UserConfig, DontCloseRule } from "./settings.js";
import type { SessionSwitchInfo } from "./session.js";

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
  pendingRestore: SessionSwitchInfo | null;
}

// Popup → background commands
export type PopupCommand =
  | { type: "undo_close"; tabId: number }
  | { type: "update_config"; config: Partial<UserConfig> }
  | { type: "add_dont_close_rule"; rule: Omit<DontCloseRule, "id"> }
  | { type: "remove_dont_close_rule"; ruleId: string }
  | { type: "get_state" }
  | { type: "get_context_bundle" }
  | { type: "dismiss_decision"; tabId: number }
  | { type: "restore_session"; sessionKey: string }
  | { type: "dismiss_restore" };

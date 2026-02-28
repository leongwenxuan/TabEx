// Barrel re-export for all TabX extension types

export type {
  TabDecision,
  TabInfo,
  TabEvent,
  ReadingData,
  ClosedTabRecord,
} from "./tab.js";

export type {
  ConnectionStatus,
  DontCloseRule,
  UserConfig,
  ContextBundle,
  StorageSchema,
} from "./settings.js";

export type {
  HostRequestType,
  TabDataRequest,
  GetContextBundleRequest,
  PingRequest,
  HostRequest,
  DecisionResponse,
  ContextBundleResponse,
  PongResponse,
  ErrorResponse,
  HostResponse,
  ContentReadingMessage,
  PopupStateMessage,
  PopupCommand,
} from "./messages.js";

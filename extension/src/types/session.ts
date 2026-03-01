// Session types for branch session restore flow

export interface TabToOpen {
  url: string;
  title: string;
}

export interface SessionSwitchInfo {
  fromBranch: string | null;
  toBranch: string | null;
  repoPath: string | null;
  hasSavedSession: boolean;
  incomingKey: string | null;
  tabsToOpen: TabToOpen[] | null;
}

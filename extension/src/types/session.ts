// Session types for branch session restore flow

export interface SessionSwitchInfo {
  fromBranch: string | null;
  toBranch: string | null;
  repoPath: string | null;
  hasSavedSession: boolean;
  incomingKey: string | null;
}

# Branch Sessions v1 Spec

## Problem

Branch switching destroys research context. You spend 30 minutes reading docs, Stack Overflow threads, and API references for `feat/oauth-flow`, then switch to `fix/login-crash` — and your browser still has the OAuth tabs cluttering it while you need entirely different pages. When you switch back, you've lost track of what mattered.

## Core Idea

Use `gitBranch + repoPath` as a namespace for browser context. On branch switch: snapshot the current session, compact it, and offer to restore the session associated with the new branch.

---

## 1. Data Schema

### 1.1 Workspace Key

```
workspaceKey = SHA256(canonicalize(repoPath) + ":" + branch)[:16]
```

- `repoPath` is the absolute path returned by `GitContext.detect().repoPath`
- `branch` is the ref name from `.git/HEAD`
- Truncated to 16 hex chars — collision-safe for practical use
- Worktree paths are canonicalized (resolved symlinks) before hashing

Example: `/Users/dev/myapp` + `feat/oauth` → `a3f8c1d902e7b4a1`

**Swift**

```swift
public struct WorkspaceKey: Codable, Hashable, Sendable {
    public let repoPath: String
    public let branch: String
    public let key: String  // hex hash

    public init(repoPath: String, branch: String) {
        self.repoPath = repoPath
        self.branch = branch
        let raw = repoPath + ":" + branch
        self.key = SHA256.hash(data: Data(raw.utf8))
            .prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
```

### 1.2 BranchSession

The central model. One per workspace key.

```swift
public struct BranchSession: Codable, Identifiable, Sendable {
    public let id: UUID
    public let workspaceKey: WorkspaceKey
    public var state: SessionState
    public let createdAt: Date
    public var lastActiveAt: Date
    public var pausedAt: Date?

    // --- Captured state ---
    /// Tabs that were open when this session was last active.
    public var tabs: [SessionTab]
    /// Accumulated page records from BundleManager during this session.
    public var pageRecords: [PageRecord]
    /// Search queries detected during this session.
    public var searchQueries: [SearchQuery]
    /// Tabs the user explicitly pinned to this session.
    public var pinnedTabUrls: Set<String>

    // --- Compacted output ---
    /// Generated on pause/compact. Null until first compaction.
    public var brief: BranchBrief?
}

public enum SessionState: String, Codable, Sendable {
    case active     // currently tracked
    case paused     // branch switched away, data preserved
    case archived   // compacted + old, not offered for restore
}
```

### 1.3 SessionTab

Snapshot of a tab at session pause time. Lighter than `TabData` — this is what we persist and restore from.

```swift
public struct SessionTab: Codable, Sendable {
    public let url: String
    public let title: String
    public let score: Double       // last known relevance score
    public let timeSpentSeconds: Double
    public let scrollDepth: Double
    public let contentDigest: String?
    public let pinnedToSession: Bool
    public let capturedAt: Date
}
```

### 1.4 SearchQuery

```swift
public struct SearchQuery: Codable, Sendable {
    public let query: String       // extracted search terms
    public let engine: String      // "google", "stackoverflow", "github", etc.
    public let url: String         // full search URL
    public let timestamp: Date
}
```

Search detection is URL-pattern based (no content inspection needed):
- `google.com/search?q=...`
- `stackoverflow.com/search?q=...`
- `github.com/search?q=...`
- `duckduckgo.com/?q=...`

### 1.5 BranchBrief

The compacted memory of a session. This is what agents and restore UI consume.

```swift
public struct BranchBrief: Codable, Sendable {
    public let generatedAt: Date
    public let summary: String          // 2-3 sentence description of what was researched
    public let keyFindings: [String]    // bullet points of decisions/discoveries
    public let topTabs: [SessionTab]    // ranked, deduped, max 10
    public let searchTerms: [String]    // deduplicated search queries
}
```

### 1.6 Storage Layout

```
~/.tabx/
├── sessions/
│   ├── index.json                     # SessionIndex (lightweight lookup)
│   ├── a3f8c1d902e7b4a1.json         # BranchSession (full)
│   ├── b7e2f09d4c1a8e33.json
│   └── ...
├── context-bundle.json                # unchanged — latest global bundle
├── latest-results.json                # unchanged
├── config.json                        # unchanged
├── arena-history.json                 # unchanged
└── state.json                         # unchanged
```

**SessionIndex** — loaded on startup, kept in memory. Avoids reading every session file.

```swift
public struct SessionIndex: Codable, Sendable {
    public var sessions: [SessionIndexEntry]
}

public struct SessionIndexEntry: Codable, Sendable {
    public let id: UUID
    public let workspaceKey: WorkspaceKey
    public let state: SessionState
    public let lastActiveAt: Date
    public let tabCount: Int
    public let briefSummary: String?   // first line of BranchBrief.summary
}
```

---

## 2. State Machine

```
                    ┌─────────────────────────────┐
                    │                             │
    branch switch   │   ┌────────┐  inactivity   │   manual
    to new branch   │   │        │  (7 days)      │   archive
         ┌──────────┴─► │ paused ├───────────────►│──► archived
         │              │        │                │
         │              └───┬────┘                │
         │                  │                     │
    ┌────┴───┐    branch    │                     │
    │        │◄── switch ───┘                     │
    │ active │    back                            │
    │        │                                    │
    └────────┘                                    │
         ▲          ┌──────────┐   manual         │
         │          │          │   restore         │
         └──────────┤ archived ├──────────────────┘
                    │          │
                    └──────────┘
```

### Transitions

| From | To | Trigger | Actions |
|---|---|---|---|
| (none) | `active` | First tab_update for an unknown workspace key | Create session, begin tracking |
| `active` | `paused` | Branch switch detected (different key) | Snapshot tabs, run compaction, write session file |
| `paused` | `active` | Branch switch back to this key | Load session, offer restore |
| `paused` | `archived` | 7 days without reactivation | No action needed — lazy on next index load |
| `archived` | `active` | Manual restore via popup/CLI | Load session, offer restore |
| `active` | `active` | Tab updates flowing in | Update in-memory state (normal operation) |

### Branch Switch Detection

Poll-based, piggybacks on the existing `tab_update` cycle:

1. `MessageRouter.handle(.tabUpdate)` already calls `GitContext.detect()` (via `BundleManager.updateResults`).
2. Add: compare `currentWorkspaceKey` against the last known key.
3. If different → trigger branch switch transition.

**Why poll, not fswatch:** The host process is launched by Chrome and may not have a persistent run loop in CLI mode. `GitContext.detect()` is cheap (reads `.git/HEAD`, two `git diff` calls). Polling on every `tab_update` (debounced to 2s) is frequent enough — branch switches don't need sub-second detection.

**Future option:** In `TabXApp` (menu bar), add a `DispatchSource.makeFileSystemObjectSource` on `.git/HEAD` for instant detection. Not required for MVP.

---

## 3. Compaction

### Triggers

1. **Branch switch** (primary) — compact the outgoing session before pausing
2. **Inactivity** — if no tab_update for 30 minutes while a session is active, compact in place
3. **Tab count threshold** — if `pageRecords.count > 50`, compact and prune

### Algorithm

```
compact(session) -> BranchBrief:
    1. Rank tabs by composite score:
       rank = (relevanceScore * 0.4) + (normalizedTimeSpent * 0.3) + (scrollDepth * 0.2) + (hasPinned * 0.1)

    2. Deduplicate by normalized URL:
       - Strip query params except meaningful ones (q=, id=, page=)
       - Strip fragments
       - Strip trailing slashes
       - Group by normalized URL, keep highest-ranked

    3. Take top 10 tabs → topTabs

    4. Deduplicate search queries:
       - Lowercase, trim
       - Remove near-duplicates (Levenshtein < 3 or subset match)

    5. Generate summary (if API key available):
       - Feed topTabs + searchTerms to gpt-4o-mini
       - Prompt: "Summarize in 2-3 sentences what the user was researching.
         List 3-5 key findings or decisions as bullet points."
       - Fallback (no API key): concatenate top 5 tab titles as summary

    6. Prune pageRecords:
       - Keep records for topTabs URLs
       - Keep records with timeSpent > 30s or scrollDepth > 0.3
       - Drop the rest

    7. Write BranchBrief to session, update index
```

### URL Normalization

```swift
func normalizeURL(_ url: String) -> String {
    guard var components = URLComponents(string: url) else { return url }
    // Keep only meaningful query params
    let keepParams: Set<String> = ["q", "id", "page", "tab", "issue", "pr"]
    components.queryItems = components.queryItems?.filter { keepParams.contains($0.name) }
    if components.queryItems?.isEmpty == true { components.queryItems = nil }
    components.fragment = nil
    // Strip trailing slash
    if components.path.hasSuffix("/") && components.path != "/" {
        components.path = String(components.path.dropLast())
    }
    return components.url?.absoluteString ?? url
}
```

---

## 4. Session Manager

New class that owns the session lifecycle. Sits between `MessageRouter` and `BundleManager`.

```swift
public final class SessionManager {
    private var currentKey: WorkspaceKey?
    private var currentSession: BranchSession?
    private var index: SessionIndex
    private let store: SessionStore  // file I/O layer

    /// Called when a branch switch is detected.
    /// Returns the new session (with restore candidates if any).
    public func onBranchSwitch(newKey: WorkspaceKey,
                               currentTabs: [TabData],
                               currentResults: [TabResult]) -> BranchSession

    /// Snapshots current session state from live tab data.
    public func snapshot(tabs: [TabData], results: [TabResult])

    /// Runs compaction on a session.
    public func compact(_ session: inout BranchSession)

    /// Returns sessions available for restore.
    public func restoreCandidates(for key: WorkspaceKey) -> BranchSession?

    /// Marks specific tabs from a session as "restore these."
    public func acceptRestore(tabUrls: [String])
}
```

### Integration into MessageRouter

```swift
// In MessageRouter.handle(.tabUpdate):
case .tabUpdate:
    let tabs = message.tabs ?? []
    let gitContext = GitContext.detect()
    let newKey = WorkspaceKey(repoPath: gitContext.repoPath ?? "", branch: gitContext.branch ?? "")

    // Detect branch switch
    if let currentKey = sessionManager.currentKey, currentKey != newKey {
        sessionManager.onBranchSwitch(
            newKey: newKey,
            currentTabs: tabs,
            currentResults: latestResults
        )
        // Notify extension about available restore
        // (new message type: session_switch)
    }

    // Normal flow continues
    bundleGen.ingest(tabs, trackIds: true)
    let results = scorer.score(tabs: tabs)
    // ... rest unchanged ...

    // Update session with latest state
    sessionManager.snapshot(tabs: tabs, results: results)
```

---

## 5. New Message Types

### Extension ← Host

```typescript
// New outgoing message type
type OutgoingMessageType = "decisions" | "bundle" | "pong" | "error" | "session_switch";

interface SessionSwitchMessage {
    type: "session_switch";
    previousBranch: string;
    currentBranch: string;
    restoreAvailable: boolean;
    restoreTabs?: Array<{
        url: string;
        title: string;
        score: number;
    }>;
    briefSummary?: string;
}
```

### Extension → Host

```typescript
// New incoming message types
type MessageType = "tab_update" | "request_bundle" | "ping" | "config_update"
                 | "restore_session" | "pin_tab" | "get_sessions";

interface RestoreSessionMessage {
    type: "restore_session";
    workspaceKey: string;
    tabUrls: string[];        // which tabs to restore (user may deselect some)
}

interface PinTabMessage {
    type: "pin_tab";
    url: string;
    pinned: boolean;          // toggle
}

interface GetSessionsMessage {
    type: "get_sessions";
}
```

---

## 6. Endpoint Contract (BundleServer)

Extend the existing `localhost:9876` HTTP server.

| Method | Path | Description |
|---|---|---|
| `GET` | `/bundle` | Current active bundle (unchanged) |
| `GET` | `/bundle.json` | Same as above (unchanged) |
| `GET` | `/bundle.md` | Markdown format (unchanged) |
| `GET` | `/sessions` | List all sessions (index) |
| `GET` | `/session/:key` | Full session by workspace key |
| `GET` | `/session/:key/brief` | Compacted brief only |
| `GET` | `/bundle?branch=NAME` | Bundle for a specific branch session |
| `GET` | `/health` | Health check (unchanged) |

### Response Examples

**`GET /sessions`**

```json
{
    "sessions": [
        {
            "id": "...",
            "workspaceKey": { "repoPath": "/Users/dev/myapp", "branch": "feat/oauth", "key": "a3f8c1d9" },
            "state": "active",
            "lastActiveAt": "2026-02-28T10:30:00Z",
            "tabCount": 12,
            "briefSummary": null
        },
        {
            "id": "...",
            "workspaceKey": { "repoPath": "/Users/dev/myapp", "branch": "fix/login-crash", "key": "b7e2f09d" },
            "state": "paused",
            "lastActiveAt": "2026-02-28T09:15:00Z",
            "tabCount": 5,
            "briefSummary": "Researching auth token refresh failures and session expiry edge cases."
        }
    ]
}
```

**`GET /session/a3f8c1d9/brief`**

```json
{
    "generatedAt": "2026-02-28T09:20:00Z",
    "summary": "Researching OAuth 2.0 PKCE flow for SPAs. Focused on token refresh, silent auth, and redirect URI handling.",
    "keyFindings": [
        "PKCE is required for public clients per RFC 7636",
        "Silent refresh via hidden iframe is deprecated in favor of refresh tokens",
        "Auth0 recommends rotating refresh tokens with absolute lifetime of 24h"
    ],
    "topTabs": [ ... ],
    "searchTerms": ["oauth pkce spa", "silent refresh deprecated", "auth0 refresh token rotation"]
}
```

---

## 7. Extension-Side Restore Flow

### 7.1 Popup UI

When a `session_switch` message arrives with `restoreAvailable: true`:

1. Show a banner at the top of the popup:
   ```
   ┌──────────────────────────────────────────┐
   │ 🔀 Switched to feat/oauth               │
   │ 5 tabs from your last session available  │
   │                                          │
   │ [Restore All]  [Pick Tabs]  [Dismiss]    │
   └──────────────────────────────────────────┘
   ```

2. **"Pick Tabs"** expands to a checklist of `restoreTabs` with title + URL. User selects which to reopen.

3. **"Restore All"** sends `restore_session` with all tab URLs.

4. On restore, extension calls `chrome.tabs.create({ url })` for each selected tab.

5. Banner dismisses after action or after 30 seconds of inactivity.

### 7.2 Storage

Add to `StorageSchema`:

```typescript
interface StorageSchema {
    // ... existing fields ...
    pendingRestore?: {
        branch: string;
        tabs: Array<{ url: string; title: string; score: number }>;
        briefSummary?: string;
        receivedAt: number;
    };
}
```

### 7.3 Badge

When a restore is pending, set the extension badge:

```typescript
chrome.action.setBadgeText({ text: "5" });    // tab count
chrome.action.setBadgeBackgroundColor({ color: "#6366f1" });
```

Clear on dismiss or restore.

---

## 8. Rollout Plan

### Phase 1: Session Persistence (MVP)

**Goal:** Branch sessions are created, saved, and loaded. No restore UI yet.

Files to create:
- `host/Sources/TabXHost/Sessions/WorkspaceKey.swift`
- `host/Sources/TabXHost/Sessions/BranchSession.swift` (models)
- `host/Sources/TabXHost/Sessions/SessionStore.swift` (file I/O)
- `host/Sources/TabXHost/Sessions/SessionManager.swift` (lifecycle)

Files to modify:
- `host/Sources/TabXHost/MessageRouter.swift` — add `SessionManager`, detect branch switches
- `host/Sources/TabXHost/Models/Messages.swift` — add `session_switch` outgoing type
- `host/Sources/TabXHost/Bundle/BundleStore.swift` — add `sessionsDirectory` path helper

Deliverable: On each `tab_update`, if the branch changed, the old session is written to `~/.tabx/sessions/<key>.json` and the new session is loaded or created. Visible via `tabx-host --sessions` CLI command.

### Phase 2: Compaction

**Goal:** Sessions are compacted on pause. Branch briefs are generated.

Files to create:
- `host/Sources/TabXHost/Sessions/Compactor.swift`
- `host/Sources/TabXHost/Sessions/URLNormalizer.swift`

Files to modify:
- `host/Sources/TabXHost/Sessions/SessionManager.swift` — call `Compactor` on branch switch
- `host/Sources/TabXHost/Agent/AgentRunner.swift` — expose a `summarize(tabs:searches:)` method for brief generation

Deliverable: `~/.tabx/sessions/<key>.json` includes a `brief` field after the first branch switch away. `tabx-host --session <key>` prints the brief.

### Phase 3: Restore Flow

**Goal:** Extension shows restore banner on branch switch.

Files to create:
- `extension/src/popup/components/restore-banner.ts`

Files to modify:
- `extension/src/background/native-client.ts` — handle `session_switch` message
- `extension/src/background/index.ts` — broadcast restore availability
- `extension/src/popup/popup.html` — add banner container
- `extension/src/types/tab.ts` — add restore-related types
- `extension/src/types/settings.ts` — add `pendingRestore` to `StorageSchema`
- `host/Sources/TabXHost/Models/Messages.swift` — add `restore_session` incoming type

Deliverable: User sees "Restore 5 tabs from feat/oauth?" banner when switching branches. Selecting restore opens the tabs.

### Phase 4: HTTP API + Agent Integration

**Goal:** Agents can query session history per branch.

Files to modify:
- `host/Sources/TabXApp/BundleServer.swift` — add `/sessions`, `/session/:key`, `/session/:key/brief` routes
- `host/Sources/TabXHost/CLI/CLIHandler.swift` — add `--sessions`, `--session <key>` commands
- `host/Sources/TabXHost/Models/Bundle.swift` — extend `ContextBundle` with `sessionBrief: BranchBrief?`

Deliverable: `curl localhost:9876/sessions` returns session index. `curl localhost:9876/session/a3f8c1d9/brief` returns the branch brief. `ContextBundle` includes the brief for the active session.

### Phase 5: Polish

- Search query detection in content script (URL pattern matching)
- Pin-to-session toggle in popup tab list
- Manual session archive/delete from popup
- Session mode toggle in settings (suggest restore / auto restore / off)
- Inactivity compaction timer

---

## 9. Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Branch != task (multiple tasks on one branch) | Phase 5: sub-session contexts (split one branch into labeled groups). For v1, one session per branch is good enough — covers 80% of workflows. |
| Same task across multiple branches | Brief includes search terms and key findings — user can manually consult another branch's brief. No automated cross-branch linking in v1. |
| Noisy snapshots from frequent switching | Debounce: don't create a session unless the branch has been active for > 10 seconds. Don't compact on sub-10s visits. |
| Disk bloat | Archive after 7 days. Delete archived sessions after 30 days. Max 50 session files (LRU eviction). |
| Privacy (stored search queries) | Search queries are extracted from URLs only (not page content). User can disable search tracking in config. Queries are never sent to external services — only used locally for brief generation. |
| Branch name collisions across repos | `WorkspaceKey` includes `repoPath`. Two repos with the same branch name get separate sessions. |
| Host process restarts mid-session | Session state is written to disk on every `tab_update` cycle (piggybacks on existing `BundleStore.saveResults`). On restart, load from last persisted state. |
| Chrome extension doesn't know about git | It doesn't need to. The host detects branch switches and sends `session_switch` to the extension. Extension only handles UI. |

---

## 10. What's Explicitly Out of Scope for v1

- Cross-repo session linking
- Sub-session contexts within a branch
- Auto-close tabs on branch switch (too aggressive for v1 — suggest restore only)
- Semantic deduplication (Levenshtein or embedding-based) — use URL normalization only
- Real-time `.git/HEAD` watching (poll is sufficient)
- Session sync across machines
- Session sharing / export

# TabX

**Your browser tabs fight for a spot in your coding agent's context.**

TabX is a developer productivity tool that makes your browser context-aware. It tracks what you read, scores every open tab against what you're actually working on (your git branch, changed files, reading depth), and produces a curated context bundle that you can hand off to CLI coding agents like Claude Code, Codex, or Cursor — so the agent already knows what you've been researching without you re-pasting or re-explaining.

## The Problem

Developers accumulate dozens of browser tabs while researching. When it's time to code, most of those tabs are noise. Worse, when you start a coding agent, it has no idea which docs, Stack Overflow answers, or GitHub issues you just read — you end up re-explaining everything. And when you switch git branches, your browser still has the old branch's research tabs cluttering your workspace.

TabX solves three things:

1. **Relevance** — Which tabs actually matter right now? TabX scores them using your git context, reading behavior, and AI analysis.
2. **Handoff** — When you start a coding agent, TabX hands it a context bundle of pages you read, snippets you highlighted, and tabs that survived scoring.
3. **Branch sessions** — Your browser tabs are linked to your git branch. Switch branches and TabX swaps your tabs automatically.

## How It Works

TabX has three components that work together:

```
Chrome Extension  ←──native messaging──→  Swift Host (tabx-host)
     (tracks tabs)                         (scores, sessions, bundles)
                                                    ↓
                                           Menu Bar App (TabXApp)
                                           (UI, arena visualization)
```

### 1. The Chrome Extension

A Manifest V3 extension that runs in the background and tracks:
- **Tab lifecycle** — opens, closes, activations, URL changes
- **Time spent** — how long each tab has been active (not just open)
- **Scroll depth** — how far you scrolled (0–100%)
- **Text selections** — what you highlighted on the page
- **Content digest** — first 500 characters of visible text

This data is sent to the native host every 5 seconds via Chrome's native messaging protocol (length-prefixed JSON over stdio).

### 2. The Swift Native Host

A macOS binary (`tabx-host`) that receives tab data from the extension and:

- **Detects your git context** — reads `.git/HEAD` for the current branch, runs `git diff` for recently changed files
- **Runs the arena** — each tab gets an AI agent that argues for its relevance, then a judge ranks them all
- **Manages branch sessions** — saves/restores your tabs per git branch
- **Generates context bundles** — a structured artifact (JSON or Markdown) for coding agents

### 3. The Menu Bar App

A SwiftUI macOS app (`TabXApp`) that lives in your menu bar and provides:

- **Arena view** — watch your tabs compete in real-time with progress indicators
- **Tabs view** — all current tabs with scores and decisions
- **Branches view** — saved sessions per branch with tab counts
- **Closed view** — recently closed tabs with undo
- **Settings** — scoring sensitivity, safelist, reset controls
- **Copy Context** — one-click copy of arena winners as Markdown for coding agents

## The Arena

The arena is how TabX decides which tabs matter. You trigger it manually from the menu bar app:

1. **Tab Agents** (gpt-4o-mini) — each tab gets its own AI agent that runs in parallel. The agent receives the tab's content (title, URL, digest, selections) plus your git context (branch name, recently changed files). It produces a structured analysis: summary, code patterns found, relevance signals, and a self-assessed score.

2. **Arena Judge** (gpt-4o) — receives all agent reports and ranks every tab holistically. The judge sees agent summaries only (not raw page content), keeping token usage bounded while using a smarter model for the final ranking.

3. **Decisions** — each tab gets a score from 0 to 1:
   - Below 0.3 = **close** (irrelevant to current work)
   - 0.3 to 0.6 = **flag** (ambiguous — review manually)
   - Above 0.6 = **keep** (relevant to current work)

If no OpenAI API key is configured, TabX falls back to a zero-cost local heuristic: it extracts tokens from your git branch name and recently changed files, then scores each tab by token overlap with its content.

## Branch Sessions

TabX links your browser tabs to your git branch. The system uses `repoPath + branch` as a namespace:

- **On branch switch** — TabX saves your current tabs, then opens the tabs linked to the new branch (or a blank tab if none exist)
- **Automatic detection** — the host detects branch changes via `.git/HEAD` on every sync cycle; the menu bar app also polls git independently
- **Session persistence** — sessions are stored at `~/.tabx/sessions/<hash>.json` and survive app/browser restarts
- **Manual arena only** — switching branches does not auto-score; you control when the arena runs

## Context Bundle

The context bundle is the main handoff artifact for coding agents. It contains:

- **Pages read** — URLs, titles, and content digests of tabs you visited
- **Highlights** — text you selected on those pages
- **Surviving tabs** — tabs that scored above the close threshold, with scores and agent summaries
- **Git context** — current branch, repo path, recently changed files
- **Task description** — derived from your branch name

Access it via:
- **CLI**: `tabx-host --bundle` (JSON) or `tabx-host --bundle --markdown` (Markdown)
- **Menu bar app**: "Copy Context" button copies arena winners as Markdown
- **HTTP**: `curl localhost:9876/bundle` (when the menu bar app is running)
- **Extension popup**: "Get Context Bundle" button

### Example: using with Claude Code

```bash
# Get your research context as Markdown and pipe it to your agent
tabx-host --bundle --markdown > context.md
# Then reference it in your agent session
```

Or use the menu bar app's "Copy Context" button to copy winning tab context to your clipboard, then paste it into your agent's prompt.

## Prerequisites

- macOS 14+ (Sonoma or later)
- Swift 5.9+ (included with Xcode 15+)
- [Bun](https://bun.sh) (or Node.js)
- Google Chrome
- OpenAI API key (optional — enables AI agent mode; without it, local token-matching still works)

## Setup

### Step 1: Clone the repo

```bash
git clone https://github.com/your-username/tabex.git
cd tabex
```

### Step 2: Build the Chrome extension

```bash
cd extension
bun install
bun run build
```

This outputs a ready-to-load extension in `extension/dist/`.

### Step 3: Load the extension in Chrome

1. Open `chrome://extensions` in Chrome
2. Enable **Developer mode** (toggle in the top right)
3. Click **Load unpacked**
4. Select the `extension/dist/` directory
5. Note the **extension ID** shown under the TabX card (you'll need this next)

### Step 4: Build and install the native host

```bash
cd ../host
./Scripts/install.sh --extension-id <YOUR_EXTENSION_ID>
```

This does three things:
1. Builds `tabx-host` in release mode via `swift build -c release`
2. Copies the binary to `/usr/local/bin/tabx-host`
3. Writes the native messaging manifest to `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.tabx.host.json`

To install to a custom location:

```bash
./Scripts/install.sh --extension-id <ID> --prefix ~/bin
```

### Step 5: Configure OpenAI API key (optional)

```bash
tabx-host --set-key sk-your-openai-api-key
```

This saves the key to `~/.tabx/config.json`. Without a key, TabX still works — it uses a local token-matching heuristic instead of AI agents. The agents and judge produce much better results, but cost a few cents per scoring round.

### Step 6: Restart Chrome

Chrome only reads native messaging manifests on startup. Fully quit and reopen Chrome (not just reload the extension). The extension popup should show a green **Connected** status.

### Step 7: Build the menu bar app (optional)

```bash
cd host
swift build --product TabXApp
# Run it
.build/debug/TabXApp
```

The menu bar app provides visualization of the arena, branch sessions, and a "Copy Context" button. It's optional — the extension and host work without it.

## Usage

### Extension popup

Click the TabX icon in Chrome's toolbar. The popup shows:

- **Open tabs** — current tabs with relevance scores, decision badges (keep/flag/close), agent summaries, and insight tags
- **Closed tabs** — recently closed tabs with an undo button to reopen them
- **Settings** — auto-close toggle, tab limit, don't-close rules, and a reset button

### Menu bar app

Click the TabX icon in your macOS menu bar. Five panels:

| Panel | What it shows |
|-------|---------------|
| **Arena** | Active arena fights with per-tab progress, history of past rounds, "Copy Context" to clipboard, "Clear" to reset |
| **Tabs** | All current tabs with scores and decisions |
| **Branches** | Saved sessions per branch — tap to drill down and see each branch's tabs |
| **Closed** | Recently closed tabs with undo |
| **Settings** | Scoring sensitivity slider, safelist management, bundle server status, "Reset All Data" button |

### CLI

The native host doubles as a CLI:

```bash
# Check connection and configuration status
tabx-host --status

# Set your OpenAI API key
tabx-host --set-key sk-your-key

# Pin a specific repo path for git detection
tabx-host --set-repo /path/to/your/repo

# Print the latest context bundle
tabx-host --bundle              # JSON
tabx-host --bundle --markdown   # Markdown (for pasting into agent prompts)

# Print current configuration
tabx-host --config

# List all saved branch sessions
tabx-host --sessions

# Print a specific session's data
tabx-host --session <workspace-key>
```

### Don't-close rules

Safelist tabs you never want closed:

| Rule type | Example | Matches |
|-----------|---------|---------|
| `domain` | `github.com` | Any tab on github.com or \*.github.com |
| `url_prefix` | `https://docs.rs` | Any URL starting with that prefix |
| `url_pattern` | `jira.*\/browse` | Regex match against the full URL |

Configure these in the extension popup's Settings panel.

## Architecture

### System overview

```
┌─────────────────────────────────────────────────────────────┐
│                        Chrome Browser                        │
│                                                              │
│  ┌──────────────┐    ┌──────────────┐    ┌───────────────┐  │
│  │ Content Script│    │  Service      │    │    Popup       │  │
│  │ (per page)    │───→│  Worker       │←──→│    UI          │  │
│  │ scroll, select│    │  (orchestrator)│    │ tabs, settings│  │
│  └──────────────┘    └──────┬───────┘    └───────────────┘  │
│                              │ native messaging              │
└──────────────────────────────┼───────────────────────────────┘
                               │ stdin/stdout (length-prefixed JSON)
                    ┌──────────▼──────────┐
                    │   tabx-host (Swift)  │
                    │                      │
                    │  ┌────────────────┐  │     ┌──────────────┐
                    │  │ MessageRouter  │──┼────→│ OpenAI API   │
                    │  └───────┬────────┘  │     │ (gpt-4o-mini │
                    │          │           │     │  + gpt-4o)   │
                    │  ┌───────▼────────┐  │     └──────────────┘
                    │  │ SessionManager │  │
                    │  │ BundleManager  │  │
                    │  │ BundleStore    │  │
                    │  └───────┬────────┘  │
                    │          │           │
                    └──────────┼───────────┘
                               │ reads/writes
                    ┌──────────▼──────────┐
                    │    ~/.tabx/          │
                    │  config.json         │
                    │  context-bundle.json │
                    │  latest-tabs.json    │
                    │  sessions/           │
                    │    index.json        │
                    │    <hash>.json       │
                    └──────────┬──────────┘
                               │ polls every 2s
                    ┌──────────▼──────────┐
                    │   TabXApp (SwiftUI)  │
                    │   macOS menu bar     │
                    │                      │
                    │  Arena | Tabs |      │
                    │  Branches | Settings │
                    │                      │
                    │  localhost:9876       │
                    │  (bundle HTTP server) │
                    └─────────────────────┘
```

### Data flow

1. **Content script** runs on every page, sends scroll depth, text selections, and content digest to the service worker every 10 seconds
2. **Service worker** maintains tab state in `chrome.storage.local`, sends all tab data to the native host every 5 seconds
3. **Native host** (`tabx-host`) ingests tab data, detects git context, checks for branch switches, and persists state to `~/.tabx/`
4. **On arena trigger** — the host spawns parallel TabAgents (one per tab), collects their analyses, then runs the ArenaJudge for final ranking
5. **On branch switch** — the host saves the outgoing session, loads the incoming session, and sends a `session_switch` message to the extension, which closes old tabs and opens the new branch's saved tabs
6. **Menu bar app** polls `~/.tabx/` files every 2 seconds and renders the current state

### Native messaging protocol

Communication uses Chrome's native messaging format: a 4-byte little-endian length prefix followed by a UTF-8 JSON payload.

**Extension to host:**
- `tab_update` — all open tabs with reading data and git context
- `request_bundle` — request the current context bundle
- `ping` — keepalive (every 30 seconds)
- `config_update` — push scoring config changes
- `restore_session` — restore a branch session by key

**Host to extension:**
- `decisions` — tab scores and close/keep/flag decisions (after arena)
- `session_switch` — branch changed, includes tabs to open for the new branch
- `bundle` — the requested context bundle
- `pong` — keepalive response

### Storage layout

```
~/.tabx/
├── config.json              # Host configuration (scoring, OpenAI, etc.)
├── context-bundle.json      # Latest context bundle for agent handoff
├── latest-tabs.json         # Current tab snapshot
├── latest-results.json      # Latest scoring results
├── active-session.json      # Current branch/session info (for menu bar app)
├── arena-history.json       # Past arena rounds
├── state.json               # Persisted app state
└── sessions/
    ├── index.json           # Lightweight session index
    ├── a3f8c1d902e7b4a1.json  # Branch session (hash of repoPath + branch)
    └── ...
```

## Configuration

### Extension settings

Configured via the popup Settings panel. Stored in `chrome.storage.local`.

| Setting | Default | Description |
|---------|---------|-------------|
| Auto-close | off | Automatically close tabs scored as "close" |
| Tab limit | none | Suggest closures when you exceed this count |
| Don't-close rules | empty | Domain/URL patterns to never auto-close |

### Host config

Stored at `~/.tabx/config.json`. Editable directly or via CLI.

```json
{
  "scoring": {
    "sensitivity": 0.5,
    "closeThreshold": 0.3,
    "keepThreshold": 0.6,
    "safelist": ["github.com", "stackoverflow.com"],
    "stalenessThresholdSeconds": 3600,
    "retentionSeconds": 86400
  },
  "openai": {
    "apiKey": "sk-...",
    "agentModel": "gpt-4o-mini",
    "judgeModel": "gpt-4o",
    "baseURL": "https://api.openai.com/v1",
    "timeoutSeconds": 30
  },
  "debugLogging": false,
  "version": "1.0.0"
}
```

| Field | Default | Description |
|-------|---------|-------------|
| `scoring.sensitivity` | `0.5` | 0.0 (permissive) to 1.0 (aggressive) — shifts all scores down |
| `scoring.closeThreshold` | `0.3` | Tabs scoring below this are marked for close |
| `scoring.keepThreshold` | `0.6` | Tabs scoring above this are kept |
| `scoring.safelist` | `[]` | Domains that are never auto-closed |
| `scoring.stalenessThresholdSeconds` | `3600` | Tabs inactive for this long get a staleness penalty |
| `scoring.retentionSeconds` | `86400` | How long page records are retained (24h default) |
| `openai.apiKey` | `""` | Your OpenAI API key |
| `openai.agentModel` | `gpt-4o-mini` | Model for per-tab agent analysis (cheap, fast) |
| `openai.judgeModel` | `gpt-4o` | Model for the arena judge (smarter, one call per round) |
| `openai.baseURL` | `https://api.openai.com/v1` | API base URL (change for proxies or compatible APIs) |
| `openai.timeoutSeconds` | `30` | HTTP timeout for API calls |

## Project Structure

```
tabex/
├── extension/                      # Chrome Extension (TypeScript + Vite)
│   ├── src/
│   │   ├── manifest.json           # MV3 manifest
│   │   ├── background/             # Service worker
│   │   │   ├── index.ts            # Main orchestrator: tab events, native messaging, decisions
│   │   │   ├── tab-tracker.ts      # Tab lifecycle state machine + time accrual
│   │   │   ├── native-client.ts    # Native messaging client with reconnection
│   │   │   ├── decision-manager.ts # Applies close/keep/flag decisions
│   │   │   ├── undo-manager.ts     # Resurrects recently closed tabs
│   │   │   └── storage.ts          # chrome.storage.local wrapper
│   │   ├── content/                # Content scripts (run on every page)
│   │   │   ├── content-script.ts   # Sends reading data every 10s
│   │   │   ├── scroll-tracker.ts   # Tracks scroll depth (0-1)
│   │   │   ├── selection-tracker.ts# Tracks text selections
│   │   │   └── content-digest.ts   # Extracts first 500 chars of visible text
│   │   ├── popup/                  # Extension popup UI
│   │   │   ├── popup.html
│   │   │   ├── popup.css
│   │   │   ├── popup.ts
│   │   │   └── components/         # Status bar, tab list, restore banner, settings
│   │   ├── types/                  # TypeScript type definitions
│   │   └── shared/                 # Shared types between background and popup
│   ├── package.json
│   └── vite.config.ts
│
├── host/                           # Swift Native Host + Menu Bar App
│   ├── Sources/
│   │   ├── TabXHost/               # Core library (TabXHostLib)
│   │   │   ├── Agent/              # AI scoring pipeline
│   │   │   │   ├── TabAgent.swift       # Per-tab AI agent (gpt-4o-mini)
│   │   │   │   ├── ArenaJudge.swift     # Arena judge (gpt-4o)
│   │   │   │   ├── AgentRunner.swift    # Orchestrates parallel agents + judge
│   │   │   │   └── OpenAIClient.swift   # HTTP client for OpenAI API
│   │   │   ├── Bundle/             # Context bundle generation
│   │   │   │   ├── BundleManager.swift  # Maintains page records, generates bundles
│   │   │   │   ├── BundleStore.swift    # Persists bundles, tabs, sessions to ~/.tabx/
│   │   │   │   └── BundleFormatter.swift# JSON and Markdown output
│   │   │   ├── Sessions/           # Branch session management
│   │   │   │   ├── SessionManager.swift # Detects branch switches, saves/restores
│   │   │   │   ├── SessionStore.swift   # File I/O for session JSON
│   │   │   │   ├── BranchSession.swift  # Session model (tabs, page records, brief)
│   │   │   │   ├── WorkspaceKey.swift   # SHA256(repoPath + branch) identifier
│   │   │   │   ├── Compactor.swift      # Ranks, dedupes, and prunes session tabs
│   │   │   │   └── URLNormalizer.swift  # Strips query params, fragments, trailing slashes
│   │   │   ├── Scoring/            # Git context + scoring config
│   │   │   │   ├── GitContext.swift     # Detects branch, repo path, changed files
│   │   │   │   └── ScoringConfig.swift  # Thresholds, sensitivity, safelist
│   │   │   ├── Models/             # Data types
│   │   │   │   ├── Messages.swift       # Native messaging protocol types
│   │   │   │   ├── Bundle.swift         # ContextBundle, PageRecord, SurvivingTab
│   │   │   │   └── Config.swift         # ScoringConfig, DecisionThresholds
│   │   │   ├── Config/             # Configuration management
│   │   │   │   ├── AppConfig.swift      # Top-level config (scoring + OpenAI)
│   │   │   │   └── ConfigManager.swift  # Reads/writes ~/.tabx/config.json
│   │   │   ├── CLI/
│   │   │   │   └── CLIHandler.swift     # CLI commands (--bundle, --status, etc.)
│   │   │   ├── NativeMessaging.swift    # Length-prefixed JSON I/O (Chrome protocol)
│   │   │   └── MessageRouter.swift      # Central message dispatcher
│   │   │
│   │   ├── TabXHostRunner/         # CLI entry point
│   │   │   └── main.swift               # Runs CLI or enters native messaging loop
│   │   │
│   │   └── TabXApp/                # macOS menu bar app (SwiftUI)
│   │       ├── TabXApp.swift            # App entry point, menu bar panels, views
│   │       ├── AppState.swift           # @Observable state (tabs, arena, sessions, git)
│   │       ├── NativeMessagingService.swift  # Bridges host when piped
│   │       └── BundleServer.swift       # Local HTTP server (localhost:9876)
│   │
│   ├── Tests/TabXHostTests/        # Unit tests
│   ├── Scripts/install.sh          # Build + install script
│   └── Package.swift               # Swift Package (5.9, macOS 14+)
│
├── docs/                           # Design documents
│   ├── idea.md                     # Original concept and pitch
│   └── branch-sessions-v1.md       # Branch session system spec
│
└── prd.md                          # Full product requirements document
```

## Development

### Extension

```bash
cd extension
bun install          # install dependencies
bun run dev          # watch mode with Vite hot reload
bun run build        # production build to extension/dist/
bun run lint         # ESLint
bun run typecheck    # tsc --noEmit
bun test             # run tests
```

After rebuilding, go to `chrome://extensions` and click the refresh icon on the TabX card.

### Host

```bash
cd host
swift build                                 # debug build
swift build -c release --product tabx-host  # release build
swift build --product TabXApp               # build menu bar app
swift test                                  # run tests
```

After rebuilding the host, copy it to your install location and restart Chrome (the host process is spawned by Chrome on demand):

```bash
cp .build/release/tabx-host /usr/local/bin/tabx-host
```

For the menu bar app, just run it directly:

```bash
.build/debug/TabXApp
```

### HTTP API (via menu bar app)

When the menu bar app is running, it serves a local HTTP API on port 9876:

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/bundle` | Current context bundle (JSON) |
| `GET` | `/bundle.md` | Current context bundle (Markdown) |
| `GET` | `/sessions` | Session index (all branches) |
| `GET` | `/session/:key` | Full session by workspace key |
| `GET` | `/session/:key/brief` | Compacted session brief |

## Cost Notes

- **Tab agents** use gpt-4o-mini — one call per tab per arena round (~$0.001/tab)
- **Arena judge** uses gpt-4o — one call per arena round with all agent summaries (~$0.01/round)
- Arena only runs when you manually trigger it from the menu bar app
- The judge sees agent summaries only, not raw page content — keeps token usage bounded
- Without an API key, everything runs locally with zero cost using token-matching

## Tech Stack

| Component | Technology |
|-----------|------------|
| Extension | TypeScript, Vite, [@crxjs/vite-plugin](https://crxjs.dev/vite-plugin), Chrome MV3 APIs |
| Host | Swift 5.9, Foundation, macOS native APIs |
| Menu bar app | SwiftUI, @Observable |
| Build (extension) | [Bun](https://bun.sh) / npm, Vite |
| Build (host) | Swift Package Manager |
| AI | OpenAI API (gpt-4o-mini for agents, gpt-4o for judge) |
| Storage | `chrome.storage.local` (extension), `~/.tabx/` JSON files (host) |
| Communication | Chrome native messaging (stdio, length-prefixed JSON) |

## Troubleshooting

### Status shows "disconnected"

1. Verify the extension ID in the manifest matches your installed extension:
   ```bash
   cat ~/Library/Application\ Support/Google/Chrome/NativeMessagingHosts/com.tabx.host.json
   ```
2. Verify the binary exists and runs:
   ```bash
   tabx-host --status
   ```
3. Restart Chrome completely (quit and reopen — not just reload the extension)

### "Specified native messaging host not found"

The manifest file is missing or in the wrong location. Re-run `install.sh` with your extension ID.

### "Native host has exited"

The binary crashed on launch. Test it manually:
```bash
echo '{}' | tabx-host
```

If it produces output without crashing, the issue may be a permissions problem. Ensure the binary is executable: `chmod +x /usr/local/bin/tabx-host`.

### No scoring results / all tabs flagged

- Run `tabx-host --status` — if API Key shows "not configured", the AI agents won't run and you'll get fallback token-matching scores
- Make sure you're in a git repository. Scoring uses git branch context as its primary signal. Outside a repo, scores will be neutral

### Extension shows tabs but menu bar app doesn't update

- The menu bar app polls `~/.tabx/` every 2 seconds. Make sure the host is writing to that directory
- Check that you're running the same build (debug vs release) that the native messaging manifest points to:
  ```bash
  cat ~/Library/Application\ Support/Google/Chrome/NativeMessagingHosts/com.tabx.host.json | grep path
  ```

### Tabs from old branch appear after switching

Kill any stale host processes and restart Chrome:
```bash
pkill -f tabx-host
```

The extension prunes stale tab entries on every branch switch, but if a host process from a previous session is still running, it may write stale data.

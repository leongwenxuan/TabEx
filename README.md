# TabX

Your browser tabs fight for a spot in your coding agent's context. Each tab gets an AI agent that argues its case, then a judge ranks them all — the most relevant context survives, the noise gets closed.

## How it works

TabX is two pieces:

1. **Chrome extension** — tracks tab activity (time spent, scroll depth, text selections, page content) and sends it to the native host
2. **Swift native host** (`tabx-host`) — assigns each tab an AI agent, runs an arena competition, and returns close/keep/flag decisions with summaries and insights

### The arena

When tabs are scored, this happens:

1. **Tab agents** (gpt-4o-mini) — each tab gets its own agent that analyzes its content against your git context and produces a structured analysis: summary, code patterns found, relevance signals, and a self-assessed score
2. **Arena judge** (gpt-4o) — receives all agent reports and ranks every tab by relevance to your current work, deciding what stays and what goes
3. **Decisions** — tabs are scored 0–1. Below 0.3 = close, above 0.6 = keep, in between = flagged for review

If no API key is configured, TabX falls back to a local token-matching heuristic (git branch + touched files vs. tab content).

## Prerequisites

- macOS 14+
- Swift 5.9+
- Node.js / [Bun](https://bun.sh)
- Google Chrome
- OpenAI API key (optional — enables agent mode)

## Setup

### 1. Build the extension

```bash
cd extension
bun install
bun run build
```

This outputs a ready-to-load extension in `extension/dist/`.

### 2. Load the extension in Chrome

1. Go to `chrome://extensions`
2. Enable **Developer mode** (top right)
3. Click **Load unpacked** and select the `extension/dist/` directory
4. Note the **extension ID** shown under the TabX card

### 3. Install the native host

```bash
cd host
./Scripts/install.sh --extension-id <YOUR_EXTENSION_ID>
```

This builds the `tabx-host` binary, copies it to `/usr/local/bin/`, and writes the native messaging manifest to `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.tabx.host.json`.

To install to a different location:

```bash
./Scripts/install.sh --extension-id <ID> --prefix ~/bin
```

### 4. Configure your OpenAI API key

```bash
tabx-host --set-key sk-your-openai-api-key
```

This saves the key to `~/.tabx/config.json`. Without a key, TabX still works using local token-matching — the agents just won't run.

### 5. Restart Chrome

Chrome only reads native messaging manifests on startup. After installing, fully restart Chrome. The extension popup should show a green **connected** status.

## Usage

### Extension popup

Click the TabX icon in Chrome to open the popup with three panels:

- **Open** — your current tabs with their relevance score, decision badge, agent summary, and insight tags
- **Closed** — recently closed tabs with an undo button to restore them
- **Settings** — auto-close toggle, tab limit, don't-close rules, API key instructions, and a button to generate the context bundle

### Don't-close rules

Safelist tabs you never want closed:

| Rule type | Example | Matches |
|---|---|---|
| `domain` | `github.com` | Any tab on github.com or *.github.com |
| `url_prefix` | `https://docs.rs` | Any URL starting with that prefix |
| `url_pattern` | `jira.*\/browse` | Regex match against the full URL |

### CLI

The native host doubles as a CLI tool:

```bash
# Set your OpenAI API key
tabx-host --set-key sk-your-key

# Check current status (mode, models, API key, branch)
tabx-host --status

# Print the latest context bundle as JSON
tabx-host --bundle

# Print it as Markdown (for pasting into an agent prompt)
tabx-host --bundle --markdown

# Print configuration
tabx-host --config
```

### Context bundle

The context bundle is the main handoff artifact for coding agents. It contains:

- **Pages read** — URLs, titles, and content digests of tabs you visited
- **Highlights** — text you selected on those pages
- **Surviving tabs** — tabs that scored above the close threshold
- **Git context** — current branch, repo path, recently changed files

The bundle is persisted to `~/.tabx/context-bundle.json` after each scoring round. Use `tabx-host --bundle` or the popup's "Get Context Bundle" button to retrieve it.

## Configuration

### Extension settings

Configured via the popup Settings panel. Stored in `chrome.storage.local`.

| Setting | Default | Description |
|---|---|---|
| Auto-close | off | Automatically close tabs scored as "close" |
| Tab limit | none | Suggest closures when you exceed this count |
| Don't-close rules | empty | Domain/URL patterns to never auto-close |

### Host config

Stored at `~/.tabx/config.json`. Editable directly or via `tabx-host --set-key`.

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
|---|---|---|
| `scoring.sensitivity` | 0.5 | 0.0 (permissive) to 1.0 (aggressive) — shifts all scores down |
| `scoring.closeThreshold` | 0.3 | Tabs scoring below this are marked for close |
| `scoring.keepThreshold` | 0.6 | Tabs scoring above this are kept |
| `scoring.safelist` | `[]` | Domains that are never closed |
| `openai.apiKey` | `""` | OpenAI API key (set via `tabx-host --set-key`) |
| `openai.agentModel` | `gpt-4o-mini` | Model used for individual tab agents |
| `openai.judgeModel` | `gpt-4o` | Model used for the arena judge |

## Project structure

```
tabex/
├── extension/                  # Chrome extension (TypeScript + Vite)
│   ├── src/
│   │   ├── background/         # Service worker: tab tracking, native messaging, decisions
│   │   ├── content/            # Content script: scroll, selection, digest extraction
│   │   ├── popup/              # Popup UI: tab list, closed list, settings
│   │   └── shared/             # Shared types
│   ├── package.json
│   └── vite.config.ts
│
├── host/                       # Swift native host
│   ├── Sources/
│   │   ├── TabXHost/           # Core library
│   │   │   ├── Agent/          # AgentRunner, TabAgent, ArenaJudge, OpenAIClient
│   │   │   ├── Bundle/         # BundleManager, BundleStore, BundleFormatter
│   │   │   ├── Scoring/        # GitContext, ScoringConfig
│   │   │   ├── Models/         # Messages, Config, Bundle types
│   │   │   ├── Config/         # AppConfig, ConfigManager
│   │   │   ├── CLI/            # CLIHandler (--bundle, --status, --set-key, etc.)
│   │   │   ├── NativeMessaging.swift
│   │   │   └── MessageRouter.swift
│   │   ├── TabXHostRunner/     # CLI entry point (main.swift)
│   │   └── TabXApp/            # macOS menu bar app (SwiftUI)
│   ├── Scripts/install.sh
│   └── Package.swift
│
└── docs/                       # Design documents
```

## Development

### Extension

```bash
cd extension
bun run dev       # watch mode with hot reload
bun run build     # production build
bun run lint      # eslint
bun run typecheck # tsc --noEmit
```

After rebuilding, go to `chrome://extensions` and click the refresh icon on TabX.

### Host

```bash
cd host
swift build                                # debug build
swift build -c release --product tabx-host # release build
swift build --target TabXHostTests         # build tests
```

After rebuilding, copy the binary to your install location:

```bash
cp .build/release/tabx-host /usr/local/bin/tabx-host
```

## Cost notes

- **Tab agents** use gpt-4o-mini (cheap, fast) — one call per tab per scoring round
- **Arena judge** uses gpt-4o (smarter) — one call per scoring round with all agent summaries
- Scoring only runs when tabs change (debounced 2s by the extension's tab tracker)
- The judge sees agent summaries only, not raw page content — keeps token usage bounded
- Without an API key, everything runs locally with zero cost

## Troubleshooting

**Status shows "disconnected"**

1. Verify the extension ID matches the installed manifest:
   ```bash
   cat ~/Library/Application\ Support/Google/Chrome/NativeMessagingHosts/com.tabx.host.json
   ```
2. Verify the binary exists and runs:
   ```bash
   tabx-host --version
   ```
3. Restart Chrome completely (not just reload the extension)

**"Specified native messaging host not found"**

The manifest file is missing or in the wrong location. Re-run `install.sh`.

**"Native host has exited"**

The binary crashed on launch. Test it manually:
```bash
echo '{}' | tabx-host
```

**No scoring results / all tabs flagged**

- Check `tabx-host --status` — if API Key shows "not configured", agents won't run and you'll get fallback token-matching scores
- Make sure you're in a git repository. The scoring uses git branch context as its primary signal. Outside a repo, scores will be neutral

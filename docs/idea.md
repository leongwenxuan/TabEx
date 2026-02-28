# TabX – The Idea

## One-liner

**TabX** is a way for context to compete: tabs and pages you read fight for a spot in your coding agent’s context. The ones that win are what your agent sees—so it gets the best context without you re-pasting or re-explaining.

---

## The pitch

- **Short:** “I built a system where context candidates compete—tabs, pages you read, highlights—and the ones that win are what get passed to your coding agent.”
- **Punchy:** “The tabs fight for a spot in your agent’s context. The ones that win are the ones that actually help.”
- **Mechanism:** Every tab and every thing you read is a candidate. They’re scored on relevance to what you’re doing (git branch, open files, reading depth, semantic fit). The winners become the context bundle; the rest get pruned. Your coding agent only sees the context that won.

Right now the “fight” is scoring and ranking. The next step is making that competition more explicit (e.g. arenas, summarization, “tabs that argue”).

---

## Problems it solves

### Tab overload
- Too many tabs; hard to tell what’s still relevant.
- Old-task tabs stick around and add noise.
- Closing by hand is tedious; closing by “oldest” loses useful stuff.

### Context loss between browser and code
- You read docs/snippets in the browser; the coding agent has no idea.
- You copy-paste URLs and code blocks or re-explain research every time you start an agent.
- The agent’s context is “what’s in the chat,” not “what you actually used in the browser.”

### Intent vs. behavior
- “What I think I’m doing” vs “what I’m actually doing” (which tabs you’ve read, which project you’re in) don’t line up.
- Tabs that look important by title aren’t necessarily the ones you engaged with.

### Recovery and control
- A tab you still needed got closed and you can’t get it back.
- No way to say “never auto-close this site” or “cap my tabs.”

### Wasted time
- Manually pruning tabs instead of coding.
- Re-finding or re-opening tabs.
- Re-teaching the agent the same research every session.

**In short:** (1) **Relevance** — which tabs actually matter right now; (2) **Handoff** — giving coding agents your real browser context; (3) **Control** — undo and safelists so pruning doesn’t feel risky.

---

## How you use it when adding a new feature

### 1. While you’re researching
Open a bunch of tabs (docs, GitHub, SO, blog posts). Read some, skim others, highlight snippets. Switch to your editor, change branch or open the relevant file.

TabX runs in the background: tracks which tabs you read vs skimmed, scores them against your current project (branch, open file), and closes or flags the noisy ones. No extra action from you.

### 2. When you’re ready to implement
You’re in the terminal or editor, about to start your coding agent (Codex, Claude Code, etc.). You run the agent in a way that includes TabX context.

### 3. How the agent gets the context
Pick one (or more) of:

- **CLI wrapper**  
  `tabex codex` or `tabex run -- claude`  
  The wrapper gets the current context bundle from the TabX host, then launches the agent with that bundle as initial context (e.g. prepended to the first message or written to a file the agent reads).

- **Context file**  
  TabX host writes the bundle to a known path (e.g. `~/.tabex/context.json` or `context.md`). You run your agent as usual but point it at that file (“use everything in this file as context”), or the agent is configured to always read that path when starting.

- **Editor/terminal integration**  
  A shortcut or command that (1) pulls the bundle from TabX and (2) injects it into the agent’s context or opens it so you can paste the relevant part.

So when you want to add a new feature:

- You’ve been browsing; TabX has been pruning and keeping the right tabs.
- When you start coding, you run your agent **through** TabX (CLI wrapper) or your agent **reads** the TabX context file.
- The agent’s first reply can reference the docs and snippets you actually read—no re-paste or re-explain.

**In practice:** Either you always start the coding agent via something like `tabex run -- codex` (handoff automatic), or you run `tabex context` to dump the bundle, then paste/attach that to the agent’s first message.

---

## What you can say you’re working on

- **One-liner:** “A browser extension + native macOS host that scores tabs by relevance (git branch, open files, reading depth) and hands off a curated context bundle to CLI coding agents so they get research context without re-explanation.”
- **By area:** TabX = context-aware tab lifecycle (close/keep/flag by relevance) + agent handoff (context layer between browser research and coding agents). Stack: Chrome extension (tab/reading telemetry, content scripts) + Swift native host (local AI scoring, native messaging), on-device.
- **Soundbite:** “Closing tabs by relevance to your current task and feeding that context to coding agents so they already know what you’ve been reading.”

---

## Cool directions (from the PRD and beyond)

- **Research memo** — One-shot export: “Summarize what I’ve been reading” → short markdown for the agent or you.
- **Per-branch context** — Store context by git branch; when you `git checkout feature-x`, the handoff bundle is pre-filtered to that branch’s research.
- **“What would I close?”** — CLI that prints “TabX would close these N tabs because…” with one-line reasons.
- **Reading depth** — Use scroll + selection + time to infer “fully read” vs “skimmed”; only “fully read” (or above a threshold) count toward “pages you read” in the handoff.
- **Session boundaries** — Detect new session (new branch, long idle, new project path); previous tabs become candidates for bulk close/archive with one-click “restore session.”
- **Keyboard-driven triage** — From a “pending decisions” list: `j/k` move, `d` close, `k` keep, `f` flag.
- **“Tab debt”** — Metric: e.g. “tabs open − tabs that match current project”; show in extension popup or menubar.
- **Local embedding cache** — Embed page digests once, cache by URL; reuse for scoring and “tabs similar to this one.”
- **Handoff as RAG** — Expose the context bundle (or an index) so the agent can query it: “What did I read about auth?”
- **“Explain my tabs”** — One prompt: “Given these tab titles and reading data, what am I probably working on?” Surfaces as a sentence or tags.
- **Merge-as-summary** — For related tabs, generate a one-page summary and offer “Replace these 5 tabs with this summary” in the handoff.

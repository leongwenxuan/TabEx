---
stepsCompleted: ['step-01-init', 'step-02-discovery', 'step-02b-vision', 'step-02c-executive-summary', 'step-03-success', 'step-04-journeys', 'step-05-domain', 'step-06-innovation', 'step-07-project-type', 'step-08-scoping', 'step-09-functional', 'step-10-nonfunctional', 'step-11-polish', 'step-12-complete']
inputDocuments:
  - _bmad-output/planning-artifacts/product-brief-tabexec-2026-02-27.md
  - _bmad-output/brainstorming/brainstorming-session-2026-02-27.md
documentCounts:
  briefCount: 1
  researchCount: 0
  brainstormingCount: 1
  projectDocsCount: 0
classification:
  projectType: developer_tool
  domain: general
  complexity: low
  projectContext: greenfield
workflowType: 'prd'
---

# Product Requirements Document - tabexec

**Author:** Leongwenxuan
**Date:** 2026-02-28

## Executive Summary

**TabX** is a developer tool that makes the browser context-aware and agentic: tabs close by relevance to what you're actually doing, not by time open. Target users are developers and researchers who accumulate many tabs; the problem is that most of those tabs are noise by the time they code. TabX uses real signals (what you read, what you're working on) to keep the right tabs alive and to hand off a curated context bundle to CLI coding agents (e.g. Codex, Claude Code), so agents get research context without re-explanation.

### What Makes This Special

- **Relevance-based lifecycle:** Tabs are scored using git branch, open files, time since last visit, reading depth (scroll/selection), and semantic similarity to the current task. Close/keep/flag decisions come from local AI in a Swift macOS app, not from the extension alone.
- **Agent handoff:** TabX knows which pages you read and which tabs survived. It can pass a context bundle—pages read, snippets highlighted, surviving tabs—to coding agents. That handoff is the main differentiator: the agent receives your research context by default.
- **Core insight:** The gap between "what I think I'm doing" and "what I'm actually doing"—most open tabs don't match the latter. TabX uses reading and task context to reduce that gap and to feed agents the right context.

### Project Classification

| Attribute | Value |
|-----------|--------|
| **Project type** | Developer tool (Chrome extension + native Swift macOS app) |
| **Domain** | General (developer productivity) |
| **Complexity** | Low (domain); medium (technical: native messaging, content scripts, local AI) |
| **Context** | Greenfield |

## Success Criteria

### User Success

- **Relevance works:** Users see low-value tabs closed or flagged without losing tabs they still need; they rarely "undo close" or reopen the same tab.
- **Agent handoff works:** When starting a coding agent, users receive a context bundle (pages read, highlights, surviving tabs) that the agent actually uses; they don't re-paste or re-explain research.
- **"Aha" moment:** User notices tab clutter drop and/or that the agent "already knew" what they were working on from TabX context.
- **Completion:** User can browse and research as usual; TabX runs in the background and surfaces decisions (close/keep/flag) and handoff without breaking flow.

### Business Success

- **Adoption:** Target users are developers/researchers who already use CLI coding agents or heavy-tab workflows; success = daily/weekly active use among early adopters (e.g. 50+ active users using scoring/handoff within 6 months of first usable release).
- **Retention:** Users keep the extension + host installed and native messaging connected; no mass uninstalls after first week.
- **Signal for "working":** Users report or demonstrate that they rely on TabX for agent context or for reducing tab overload; optional: contributions, feedback, or word-of-mouth.

### Technical Success

- **Native messaging:** Chrome extension and Swift host communicate reliably (4-byte length-prefixed JSON over stdin/stdout); host registered under `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/`.
- **Scoring latency:** Close/keep/flag decisions returned within a few seconds of tab/reading updates so the UI feels responsive.
- **Stability:** No data loss of context bundle; undo/resurrect available when the system closes a tab the user still wanted.
- **Privacy:** Tab and reading data stay on-device; scoring and handoff run locally (no required cloud).

### Measurable Outcomes

| Outcome | Target (MVP) |
|--------|-------------------------------|
| Tabs scored and decision returned | < 5 s from event |
| Agent handoff bundle generated | On demand when user starts agent |
| Undo/resurrect | Available for recently closed tabs |
| Native host + extension | Stay connected across browser restarts |

## Product Scope

### MVP – Minimum Viable Product

- **Chrome extension:** Tab open/close events, time spent, scroll depth, text selection; content scripts for page content; send to native host via native messaging.
- **Swift native host:** Receives tab + reading data; runs local AI scoring (relevance to task/project context); returns close/keep/flag to extension; exposes context bundle for agent handoff (e.g. CLI or API).
- **Scoring inputs:** Git branch/repo path, open files (or project context), time since last visit, reading depth, basic semantic similarity to current task.
- **User controls:** Undo/resurrect for recently closed tabs; optional tab limit or "don't close" list.
- **Agent handoff:** Curated bundle (pages read, snippets highlighted, surviving tabs) available to CLI agents (Codex, Claude Code, etc.) when user starts a session.

### Growth (Post-MVP)

- **Merge:** Related tabs can be merged into a single "super-tab" or summary instead of only close/keep.
- **Arenas:** Group tabs by task/topic; competition or pruning within each group.
- **Richer scoring:** Better semantic model, more project signals (e.g. recent commits, open terminals).
- **More handoff targets:** Additional agent integrations, formats, or UI to inspect/edit the bundle.

### Vision (Future)

- **Gamified UX:** Arenas, sprites, elimination/celebration; only after core relevance and handoff are validated.
- **Tab-as-agent:** Tabs as entities that "argue" or summarize for relevance; prompt-triggered search over tab context.
- **Full agent-tab model:** Optional path to deeper integration (e.g. fork or deeper browser integration) if extension + host proves the value.

## User Journeys

### Primary User – Developer (Success Path)

**Opening scene:** Alex is a developer with 40+ tabs open after researching a new API and debugging a separate feature. They switch to their editor and start a coding agent to implement something from the research. The agent has no idea which docs or snippets mattered.

**Rising action:** Alex has TabX installed. While they browsed, the extension sent tab and reading data to the Swift host. The host scored tabs against the current git branch and open files; some tabs were auto-closed or flagged. Alex didn't have to manually close 35 tabs. When they start the coding agent, TabX hands off a context bundle: the pages they read, the code they highlighted, and the tabs that survived.

**Climax:** The agent's first response references the right docs and snippets. Alex doesn't re-paste or re-explain. They feel the product "gets" what they're doing.

**Resolution:** Alex keeps TabX running. Tab clutter stays manageable; agent sessions start with context. They consider TabX part of their flow.

### Primary User – Edge Case (Wrong Close / Undo)

**Opening scene:** Jordan relies on TabX to prune tabs. One day a tab they still needed was closed (relevance score was wrong or context shifted).

**Rising action:** Jordan sees the tab is gone. They use TabX's undo/resurrect for recently closed tabs and restore it. They optionally add that site or tab to a "don't close" list so it doesn't happen again.

**Climax:** Recovery is one action; no lost work. Jordan trusts the product more because undo exists.

**Resolution:** Jordan continues using TabX; they use undo rarely but value its presence.

### Agent Handoff Journey (CLI Consumer)

**Opening scene:** Sam uses Claude Code or Codex from the terminal. They've been reading implementation guides and have 15 tabs open. When they run the agent, they want it to know what they've been reading.

**Rising action:** TabX native host exposes the context bundle (e.g. via a CLI command or local API). The agent is invoked with that bundle as context—either by the user running a TabX CLI command that launches the agent, or by the agent reading from a TabX-provided file/socket.

**Climax:** The agent's suggestions align with the pages Sam read and the snippets they highlighted. No copy-paste of URLs or code blocks.

**Resolution:** Sam uses TabX as the "context layer" between browser research and coding agents. Handoff becomes a habit.

### Journey Requirements Summary

- Extension must track tab lifecycle, time, scroll, selection, and send to host.
- Host must score tabs and return close/keep/flag; support undo/resurrect and optional safelist.
- Host must produce and expose a context bundle (pages read, highlights, surviving tabs) for agent consumption.
- Clear installation path: extension + native host registration; host must stay running and connected.

## Domain Requirements

Domain complexity is **low** (general developer productivity). No domain-specific compliance, regulatory, or certification requirements. Standard practices for security (on-device data), performance, and reliability apply.

## Innovation Focus

- **Relevance-based tab lifecycle:** Closing tabs by relevance to current task (git branch, open files, reading depth, semantic fit) rather than by time or manual choice. This reframes the browser as context-aware.
- **Agent handoff as product:** The context bundle is a first-class output: pages read, highlights, surviving tabs. CLI agents consume it so the user doesn't re-explain. This combines browser context with agentic coding tools in a way that is still rare.
- **Local-first AI:** Scoring and bundle generation run on-device (Swift host + local model). Privacy and latency are preserved without cloud dependency.

## Project-Type Requirements (Developer Tool)

- **Installation:** Chrome extension installable from package or store; native host installable and registerable at `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/`. Clear docs for one-time setup.
- **API surface:** Extension ↔ host: JSON over native messaging (length-prefixed). Host exposes context bundle (e.g. file path, CLI stdout, or local HTTP) for agent consumption. No public REST API required for MVP.
- **Documentation:** Setup guide (extension + host registration), description of scoring inputs and handoff format, and at least one example of invoking an agent with TabX context.
- **Examples:** One end-to-end example (e.g. "run Codex with TabX context") so developers can replicate the handoff flow.

## Scoping Summary

- **Phase 1 (MVP):** Extension + native host, scoring, close/keep/flag, undo/resurrect, context bundle, one agent handoff path (e.g. CLI or file). Proves relevance and handoff value.
- **Phase 2 (Growth):** Merge, arenas, richer scoring, more handoff targets. Competitive differentiation.
- **Phase 3 (Vision):** Gamified UX, tab-as-agent, optional deeper browser integration. After validation.

## Functional Requirements

### Tab Tracking and Telemetry

- FR1: The extension can record tab open, close, and activate events.
- FR2: The extension can record time spent per tab and approximate scroll depth.
- FR3: The extension can record text selected by the user on a page.
- FR4: The extension can capture page content (or a digest) via content scripts for scoring.
- FR5: The extension can send tab and reading data to the native host using the native messaging protocol (length-prefixed JSON).

### Relevance Scoring and Decisions

- FR6: The native host can receive tab and reading data from the extension.
- FR7: The native host can compute a relevance score for a tab using git branch/repo, open files or project context, time since last visit, reading depth, and semantic similarity to current task.
- FR8: The native host can return a close/keep/flag decision per tab to the extension.
- FR9: The extension can apply the host's decision (e.g. suggest close, keep, or flag) and optionally auto-close with user preference.
- FR10: The user can undo or resurrect recently closed tabs (within a defined window or count).

### User Controls and Safelist

- FR11: The user can configure optional tab limits or "don't close" rules (e.g. by domain or URL pattern).
- FR12: The user can see which tabs were closed by TabX and restore them via undo/resurrect.

### Context Bundle and Agent Handoff

- FR13: The native host can build a context bundle containing: pages read (URLs, titles, optional content digest), snippets highlighted, and list of surviving tabs.
- FR14: The user or an agent can request the current context bundle (e.g. via CLI, file, or local API).
- FR15: The context bundle is available when the user starts a coding agent so the agent can consume it without the user re-pasting.

### Installation and Configuration

- FR16: The user can install the Chrome extension and the native host so that the host is registered as a Chrome native messaging host on macOS.
- FR17: The user can confirm that the extension and host are connected (e.g. status indicator or one-time verification).
- FR18: The user can configure scoring sensitivity or handoff behavior within documented options.

### Reliability and Recovery

- FR19: If the native host is unavailable, the extension can degrade gracefully (e.g. no auto-close, or queue and retry) and surface connection status.
- FR20: Tab and reading data used for scoring and the context bundle are retained only as needed for scoring and handoff (e.g. session or configurable window); no unnecessary persistence.

## Non-Functional Requirements

### Performance

- NFR1: The native host returns close/keep/flag decisions within 5 seconds of receiving tab/reading updates for the affected tab(s).
- NFR2: Context bundle generation completes within a few seconds of request so agent startup is not blocked.

### Security and Privacy

- NFR3: Tab content, reading data, and context bundle stay on the user's machine; no required transmission to a remote service for scoring or handoff.
- NFR4: The native host and extension communicate only over the Chrome native messaging channel (no arbitrary network listeners for MVP unless explicitly documented).
- NFR5: Sensitive fields (e.g. passwords, form data) must not be included in page content sent to the host or in the context bundle; content extraction must avoid known sensitive regions or allow the user to exclude sites.

### Reliability

- NFR6: The extension and host connection can recover after browser or host restart without requiring re-installation of the host.
- NFR7: Undo/resurrect state is persisted across extension reloads within the defined undo window so that recently closed tabs can be restored after a crash or restart.

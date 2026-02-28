/**
 * TabX Popup — main entry point.
 *
 * Responsibilities:
 * - Request current state from the background service worker on open.
 * - Listen for push state updates (popup_state messages) from the background.
 * - Delegate rendering to tab-list, status-bar, and settings-panel components.
 * - Handle tab navigation (Open / Closed / Settings panels).
 * - Handle "Get Context Bundle" button.
 */

import type { ContextBundle, PopupCommand, PopupStateMessage } from "../shared/types.js";
import { renderTabList, renderClosedList } from "./components/tab-list.js";
import { renderStatusBar } from "./components/status-bar.js";
import { applySettingsToForm, bindSettingsEvents } from "./components/settings-panel.js";
import { renderRestoreBanner } from "./components/restore-banner.js";

// ─── Messaging helpers ────────────────────────────────────────────────────────

function sendCommand(cmd: PopupCommand): Promise<unknown> {
  return new Promise((resolve) => {
    chrome.runtime.sendMessage(cmd, resolve);
  });
}

// ─── State application ────────────────────────────────────────────────────────

function applyState(state: PopupStateMessage): void {
  // Status bar
  const badge = document.getElementById("status-badge");
  const label = document.getElementById("status-label");
  if (badge && label) {
    renderStatusBar(badge, label, state.connectionStatus);
  }

  // Restore banner (before tab list)
  const restoreBanner = document.getElementById("restore-banner-container");
  if (restoreBanner) {
    renderRestoreBanner(restoreBanner, state.pendingRestore);
  }

  // Open tabs
  const tabsList = document.getElementById("tabs-list");
  if (tabsList) {
    renderTabList(tabsList, state.tabs);
  }

  // Recently closed tabs
  const closedList = document.getElementById("closed-list");
  if (closedList) {
    renderClosedList(closedList, state.closedTabs);
  }

  // Settings form
  applySettingsToForm(state.config);
}

// ─── Tab navigation ───────────────────────────────────────────────────────────

function bindNavTabs(): void {
  const buttons = document.querySelectorAll<HTMLButtonElement>(".tab-btn");
  buttons.forEach((btn) => {
    btn.addEventListener("click", () => {
      // Deactivate all buttons and panels
      buttons.forEach((b) => b.classList.remove("active"));
      document.querySelectorAll(".panel").forEach((p) => p.classList.remove("active"));

      // Activate clicked button and its target panel
      btn.classList.add("active");
      const targetId = btn.dataset["panel"];
      if (targetId) {
        document.getElementById(targetId)?.classList.add("active");
      }
    });
  });
}

// ─── Context bundle ───────────────────────────────────────────────────────────

function bindBundleButton(): void {
  const bundleBtn = document.getElementById("get-bundle-btn") as HTMLButtonElement | null;
  const bundleArea = document.getElementById("bundle-output");
  const bundleContent = document.getElementById("bundle-content");

  bundleBtn?.addEventListener("click", () => {
    bundleBtn.disabled = true;
    bundleBtn.textContent = "Loading…";

    sendCommand({ type: "get_context_bundle" })
      .then((response) => {
        const res = response as { ok: boolean; bundle?: ContextBundle } | null;
        if (res?.ok && res.bundle && bundleContent && bundleArea) {
          bundleContent.textContent = JSON.stringify(res.bundle, null, 2);
          bundleArea.classList.remove("hidden");
        }
      })
      .catch(() => {
        // ignore
      })
      .finally(() => {
        bundleBtn.disabled = false;
        bundleBtn.textContent = "Get Context Bundle";
      });
  });
}

// ─── Init ─────────────────────────────────────────────────────────────────────

async function init(): Promise<void> {
  // Wire up settings change handlers (must happen before first applyState)
  bindSettingsEvents();

  // Wire up tab navigation
  bindNavTabs();

  // Wire up context bundle button
  bindBundleButton();

  // Listen for push updates from the background
  chrome.runtime.onMessage.addListener((msg: unknown) => {
    const message = msg as PopupStateMessage;
    if (message?.type === "popup_state") {
      applyState(message);
    }
  });

  // Request initial state
  const state = (await sendCommand({ type: "get_state" })) as PopupStateMessage | null;
  if (state?.type === "popup_state") {
    applyState(state);
  }
}

void init();

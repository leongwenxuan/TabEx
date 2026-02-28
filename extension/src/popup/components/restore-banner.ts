/**
 * RestoreBanner component — shows a banner when a saved branch session is available.
 *
 * Renders into the given container. Hides when info is null.
 */

import type { PopupCommand, SessionSwitchInfo } from "../../shared/types.js";

function sendCommand(cmd: PopupCommand): void {
  chrome.runtime.sendMessage(cmd).catch(() => {
    // popup may have been unloaded
  });
}

/**
 * Renders or hides the restore banner.
 * When `info` is non-null and has a saved session, shows the banner with Restore/Dismiss buttons.
 */
export function renderRestoreBanner(
  container: HTMLElement,
  info: SessionSwitchInfo | null
): void {
  container.innerHTML = "";

  if (!info || !info.hasSavedSession || !info.incomingKey) {
    container.classList.add("hidden");
    return;
  }

  container.classList.remove("hidden");

  const banner = document.createElement("div");
  banner.className = "restore-banner";

  const text = document.createElement("div");
  text.className = "restore-banner-text";
  const branchName = info.toBranch ?? "unknown branch";
  text.textContent = `Saved session available for ${branchName}`;

  const actions = document.createElement("div");
  actions.className = "restore-banner-actions";

  const restoreBtn = document.createElement("button");
  restoreBtn.className = "btn btn-primary restore-btn";
  restoreBtn.textContent = "Restore";
  restoreBtn.addEventListener("click", () => {
    sendCommand({ type: "restore_session", sessionKey: info.incomingKey! });
  });

  const dismissBtn = document.createElement("button");
  dismissBtn.className = "btn btn-secondary restore-dismiss-btn";
  dismissBtn.textContent = "Dismiss";
  dismissBtn.addEventListener("click", () => {
    sendCommand({ type: "dismiss_restore" });
  });

  actions.appendChild(restoreBtn);
  actions.appendChild(dismissBtn);
  banner.appendChild(text);
  banner.appendChild(actions);
  container.appendChild(banner);
}

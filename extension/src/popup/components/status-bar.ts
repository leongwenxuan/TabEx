/**
 * StatusBar component — renders the connection status indicator in the popup header.
 */

import type { ConnectionStatus } from "../../shared/types.js";

/**
 * Updates the status badge and label elements to reflect the current
 * connection status.
 */
export function renderStatusBar(
  badge: HTMLElement,
  label: HTMLElement,
  status: ConnectionStatus
): void {
  badge.dataset["status"] = status;
  label.textContent = status;

  // Reset classes then apply the appropriate one
  badge.className = "status";
  if (status === "connected") {
    badge.classList.add("status-connected");
  } else {
    badge.classList.add("status-disconnected");
  }
}

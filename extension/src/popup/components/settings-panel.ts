/**
 * SettingsPanel component — renders and manages the settings form in the popup.
 *
 * Provides:
 *  - applySettingsToForm: populate form controls from a UserConfig
 *  - bindSettingsEvents: wire up change events to send PopupCommands to background
 */

import type { DontCloseRule, PopupCommand, UserConfig } from "../../shared/types.js";

function sendCommand(cmd: PopupCommand): void {
  chrome.runtime.sendMessage(cmd).catch(() => {
    // popup may have been unloaded
  });
}

// ─── Render ───────────────────────────────────────────────────────────────────

/**
 * Populates all settings form fields from the given config.
 * Safe to call multiple times — idempotent.
 */
export function applySettingsToForm(config: UserConfig): void {
  const autoClose = document.getElementById(
    "auto-close-toggle"
  ) as HTMLInputElement | null;
  const autoRestore = document.getElementById(
    "auto-restore-toggle"
  ) as HTMLInputElement | null;
  const tabLimit = document.getElementById(
    "tab-limit"
  ) as HTMLInputElement | null;

  if (autoClose) autoClose.checked = config.autoClose;
  if (autoRestore) autoRestore.checked = config.autoRestore;
  if (tabLimit) {
    tabLimit.value = config.tabLimit != null ? String(config.tabLimit) : "";
  }

  renderRules(config.dontCloseRules);
}

function renderRules(rules: DontCloseRule[]): void {
  const container = document.getElementById("safelist-rules");
  if (!container) return;
  container.innerHTML = "";
  for (const rule of rules) {
    container.appendChild(createRuleItem(rule));
  }
}

function createRuleItem(rule: DontCloseRule): HTMLElement {
  const item = document.createElement("div");
  item.className = "rule-item";

  const typeTag = document.createElement("span");
  typeTag.className = "rule-type-tag";
  typeTag.textContent = rule.type.replace("_", " ");

  const valueEl = document.createElement("span");
  valueEl.className = "rule-value";
  valueEl.textContent = rule.value;

  const removeBtn = document.createElement("button");
  removeBtn.className = "rule-remove-btn";
  removeBtn.textContent = "×";
  removeBtn.title = "Remove rule";
  removeBtn.addEventListener("click", () => {
    sendCommand({ type: "remove_dont_close_rule", ruleId: rule.id });
  });

  item.appendChild(typeTag);
  item.appendChild(valueEl);
  item.appendChild(removeBtn);

  return item;
}

// ─── Events ───────────────────────────────────────────────────────────────────

/**
 * Wires up all settings form change/click handlers.
 * Call once after DOMContentLoaded.
 */
export function bindSettingsEvents(): void {
  const autoClose = document.getElementById(
    "auto-close-toggle"
  ) as HTMLInputElement | null;
  const autoRestore = document.getElementById(
    "auto-restore-toggle"
  ) as HTMLInputElement | null;
  const tabLimit = document.getElementById(
    "tab-limit"
  ) as HTMLInputElement | null;
  const addRuleBtn = document.getElementById("add-rule-btn");
  const newRuleValue = document.getElementById(
    "new-rule-value"
  ) as HTMLInputElement | null;
  const newRuleType = document.getElementById(
    "new-rule-type"
  ) as HTMLSelectElement | null;

  autoClose?.addEventListener("change", () => {
    sendCommand({
      type: "update_config",
      config: { autoClose: autoClose.checked },
    });
  });

  autoRestore?.addEventListener("change", () => {
    sendCommand({
      type: "update_config",
      config: { autoRestore: autoRestore.checked },
    });
  });

  tabLimit?.addEventListener("change", () => {
    const raw = tabLimit.value.trim();
    if (raw === "") {
      sendCommand({ type: "update_config", config: { tabLimit: null } });
      return;
    }
    const parsed = parseInt(raw, 10);
    if (Number.isFinite(parsed) && parsed > 0) {
      sendCommand({ type: "update_config", config: { tabLimit: parsed } });
    }
  });

  addRuleBtn?.addEventListener("click", () => {
    if (!newRuleValue || !newRuleType) return;
    const value = newRuleValue.value.trim();
    if (!value) return;
    const type = newRuleType.value as DontCloseRule["type"];
    sendCommand({ type: "add_dont_close_rule", rule: { type, value } });
    newRuleValue.value = "";
  });
}

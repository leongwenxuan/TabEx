import type {
  StorageSchema,
  TabInfo,
  ClosedTabRecord,
  UserConfig,
  ConnectionStatus,
  DontCloseRule,
} from "../shared/types.js";

const MAX_CLOSED_TABS = 50;

const DEFAULT_CONFIG: UserConfig = {
  tabLimit: null,
  dontCloseRules: [],
  autoClose: false,
  scoringEnabled: true,
};

export async function getStorage(): Promise<StorageSchema> {
  const result = await chrome.storage.local.get([
    "config",
    "tabs",
    "closedTabs",
    "connectionStatus",
    "lastBundleAt",
  ]);
  return {
    config: (result["config"] as UserConfig | undefined) ?? DEFAULT_CONFIG,
    tabs: (result["tabs"] as Record<string, TabInfo> | undefined) ?? {},
    closedTabs: (result["closedTabs"] as ClosedTabRecord[] | undefined) ?? [],
    connectionStatus: (result["connectionStatus"] as ConnectionStatus | undefined) ?? "disconnected",
    lastBundleAt: (result["lastBundleAt"] as number | null | undefined) ?? null,
  };
}

export async function getConfig(): Promise<UserConfig> {
  const result = await chrome.storage.local.get("config");
  return (result["config"] as UserConfig | undefined) ?? DEFAULT_CONFIG;
}

export async function setConfig(config: UserConfig): Promise<void> {
  await chrome.storage.local.set({ config });
}

export async function updateConfig(patch: Partial<UserConfig>): Promise<UserConfig> {
  const current = await getConfig();
  const updated = { ...current, ...patch };
  await setConfig(updated);
  return updated;
}

export async function getTabs(): Promise<Record<string, TabInfo>> {
  const result = await chrome.storage.local.get("tabs");
  return (result["tabs"] as Record<string, TabInfo> | undefined) ?? {};
}

export async function setTabs(tabs: Record<string, TabInfo>): Promise<void> {
  await chrome.storage.local.set({ tabs });
}

export async function getTab(tabId: number): Promise<TabInfo | undefined> {
  const tabs = await getTabs();
  return tabs[String(tabId)];
}

export async function setTab(tab: TabInfo): Promise<void> {
  const tabs = await getTabs();
  tabs[String(tab.tabId)] = tab;
  await setTabs(tabs);
}

export async function deleteTab(tabId: number): Promise<void> {
  const tabs = await getTabs();
  delete tabs[String(tabId)];
  await setTabs(tabs);
}

export async function getClosedTabs(): Promise<ClosedTabRecord[]> {
  const result = await chrome.storage.local.get("closedTabs");
  return (result["closedTabs"] as ClosedTabRecord[] | undefined) ?? [];
}

export async function pushClosedTab(record: ClosedTabRecord): Promise<void> {
  const closed = await getClosedTabs();
  closed.unshift(record);
  const trimmed = closed.slice(0, MAX_CLOSED_TABS);
  await chrome.storage.local.set({ closedTabs: trimmed });
}

export async function removeClosedTab(tabId: number): Promise<ClosedTabRecord | undefined> {
  const closed = await getClosedTabs();
  const idx = closed.findIndex((r) => r.tabId === tabId);
  if (idx === -1) return undefined;
  const [record] = closed.splice(idx, 1);
  await chrome.storage.local.set({ closedTabs: closed });
  return record;
}

export async function setConnectionStatus(status: ConnectionStatus): Promise<void> {
  await chrome.storage.local.set({ connectionStatus: status });
}

export async function getConnectionStatus(): Promise<ConnectionStatus> {
  const result = await chrome.storage.local.get("connectionStatus");
  return (result["connectionStatus"] as ConnectionStatus | undefined) ?? "disconnected";
}

export async function addDontCloseRule(
  rule: Omit<DontCloseRule, "id">
): Promise<DontCloseRule> {
  const config = await getConfig();
  const newRule: DontCloseRule = {
    ...rule,
    id: crypto.randomUUID(),
  };
  config.dontCloseRules.push(newRule);
  await setConfig(config);
  return newRule;
}

export async function removeDontCloseRule(ruleId: string): Promise<void> {
  const config = await getConfig();
  config.dontCloseRules = config.dontCloseRules.filter((r) => r.id !== ruleId);
  await setConfig(config);
}

export function matchesDontCloseRule(
  url: string,
  rules: DontCloseRule[]
): boolean {
  for (const rule of rules) {
    try {
      if (rule.type === "domain") {
        const hostname = new URL(url).hostname;
        if (hostname === rule.value || hostname.endsWith("." + rule.value)) {
          return true;
        }
      } else if (rule.type === "url_prefix") {
        if (url.startsWith(rule.value)) return true;
      } else if (rule.type === "url_pattern") {
        const regex = new RegExp(rule.value);
        if (regex.test(url)) return true;
      }
    } catch {
      // skip invalid rule
    }
  }
  return false;
}

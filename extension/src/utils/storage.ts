import type { StorageSchema } from "../types/index.js";

/**
 * Typed getter for chrome.storage.local.
 * Returns undefined if the key has not been stored yet.
 */
export async function getStorageValue<K extends keyof StorageSchema>(
  key: K
): Promise<StorageSchema[K] | undefined> {
  const result = await chrome.storage.local.get(key);
  return result[key] as StorageSchema[K] | undefined;
}

/**
 * Typed setter for chrome.storage.local.
 */
export async function setStorageValue<K extends keyof StorageSchema>(
  key: K,
  value: StorageSchema[K]
): Promise<void> {
  const record: { [k: string]: unknown } = {};
  record[key] = value;
  await chrome.storage.local.set(record);
}

/**
 * Remove a key from chrome.storage.local.
 */
export async function removeStorageValue(key: keyof StorageSchema): Promise<void> {
  await chrome.storage.local.remove(key);
}

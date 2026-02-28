const TAG = "[TabX]";

export function log(...args: unknown[]): void {
  console.log(TAG, ...args);
}

export function warn(...args: unknown[]): void {
  console.warn(TAG, ...args);
}

export function error(...args: unknown[]): void {
  console.error(TAG, ...args);
}

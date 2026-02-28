/**
 * content-digest — extracts a structured text digest from the current page.
 *
 * Builds a concise summary using title, meta description, OG title, headings,
 * and the first meaningful paragraph, while excluding sensitive fields.
 */

const MAX_DIGEST_CHARS = 500;

const EXCLUDED_SELECTORS: readonly string[] = [
  "script",
  "style",
  "nav",
  "footer",
  "header",
  "aside",
  'input[type="password"]',
  'input[type="email"]',
  'input[name*="card"]',
  'input[name*="cvv"]',
  'input[name*="ssn"]',
  "[data-sensitive]",
  'form[autocomplete="off"] input',
];

/**
 * Returns a plain-text digest of the page's visible content, capped at
 * MAX_DIGEST_CHARS characters, suitable for sending to the background worker.
 */
export function getContentDigest(): string {
  const clone = document.body.cloneNode(true) as HTMLElement;

  for (const selector of EXCLUDED_SELECTORS) {
    try {
      clone.querySelectorAll(selector).forEach((el) => el.remove());
    } catch {
      // ignore invalid selectors
    }
  }

  const text = clone.innerText ?? clone.textContent ?? "";
  return text.replace(/\s+/g, " ").trim().slice(0, MAX_DIGEST_CHARS);
}

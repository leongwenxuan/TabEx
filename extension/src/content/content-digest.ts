/**
 * content-digest — extracts a structured text digest from the current page.
 *
 * Builds a concise summary using headings, body text, and code blocks,
 * while excluding sensitive fields. Structured as:
 *   headings | body text | code blocks
 * Truncated to MAX_DIGEST_CHARS total.
 */

const MAX_DIGEST_CHARS = 5000;

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
 * Returns a structured plain-text digest of the page's visible content,
 * capped at MAX_DIGEST_CHARS characters, suitable for sending to the
 * background worker and AI agent analysis.
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

  // Extract headings (h1-h3)
  const headings: string[] = [];
  clone.querySelectorAll("h1, h2, h3").forEach((el) => {
    const text = (el.textContent ?? "").replace(/\s+/g, " ").trim();
    if (text.length > 0) headings.push(text);
  });

  // Extract code blocks (pre, code)
  const codeBlocks: string[] = [];
  clone.querySelectorAll("pre, code").forEach((el) => {
    const text = (el.textContent ?? "").trim();
    if (text.length > 10) {
      codeBlocks.push(text.slice(0, 500));
      el.remove(); // remove so body text doesn't duplicate code
    }
  });

  // Body text (remaining visible content)
  const bodyText = (clone.innerText ?? clone.textContent ?? "")
    .replace(/\s+/g, " ")
    .trim();

  // Assemble: headings | body | code
  const parts: string[] = [];
  if (headings.length > 0) {
    parts.push("[Headings] " + headings.join(" | "));
  }
  if (bodyText.length > 0) {
    parts.push("[Body] " + bodyText);
  }
  if (codeBlocks.length > 0) {
    parts.push("[Code] " + codeBlocks.join("\n---\n"));
  }

  return parts.join("\n").slice(0, MAX_DIGEST_CHARS);
}

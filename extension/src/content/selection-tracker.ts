/**
 * SelectionTracker — captures text selections made by the user,
 * filtering out sensitive fields and short/long selections.
 */

const MAX_SELECTIONS = 20;
const MAX_SELECTION_LENGTH = 300;
const MIN_SELECTION_LENGTH = 10;
const DEBOUNCE_MS = 400;

const SENSITIVE_SELECTORS: readonly string[] = [
  'input[type="password"]',
  'input[type="email"]',
  'input[name*="card"]',
  'input[name*="cvv"]',
  'input[name*="ssn"]',
  '[data-sensitive]',
  'form[autocomplete="off"] input',
];

export class SelectionTracker {
  private _selections: string[] = [];
  private _debounceTimer: ReturnType<typeof setTimeout> | null = null;
  private readonly _handler: () => void;
  private readonly _onUpdate: (selections: string[]) => void;

  constructor(onUpdate: (selections: string[]) => void) {
    this._onUpdate = onUpdate;
    this._handler = () => this._onSelectionChange();
    document.addEventListener("selectionchange", this._handler);
  }

  get selections(): string[] {
    return [...this._selections];
  }

  destroy(): void {
    document.removeEventListener("selectionchange", this._handler);
    if (this._debounceTimer !== null) clearTimeout(this._debounceTimer);
  }

  private _isInsideSensitiveField(node: Node | null): boolean {
    if (!node) return false;
    let el: Element | null =
      node.nodeType === Node.ELEMENT_NODE
        ? (node as Element)
        : node.parentElement;
    while (el) {
      for (const selector of SENSITIVE_SELECTORS) {
        try {
          if (el.matches(selector)) return true;
        } catch {
          // ignore invalid selectors
        }
      }
      el = el.parentElement;
    }
    return false;
  }

  private _onSelectionChange(): void {
    if (this._debounceTimer !== null) clearTimeout(this._debounceTimer);
    this._debounceTimer = setTimeout(() => {
      const sel = window.getSelection();
      if (!sel || sel.rangeCount === 0) return;
      const text = sel.toString().trim();
      if (text.length < MIN_SELECTION_LENGTH || text.length > MAX_SELECTION_LENGTH) return;
      if (this._isInsideSensitiveField(sel.anchorNode)) return;
      if (!this._selections.includes(text)) {
        this._selections.push(text);
        if (this._selections.length > MAX_SELECTIONS) this._selections.shift();
        this._onUpdate(this.selections);
      }
    }, DEBOUNCE_MS);
  }
}

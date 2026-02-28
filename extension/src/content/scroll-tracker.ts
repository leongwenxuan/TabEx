/**
 * ScrollTracker — tracks the user's maximum scroll depth on the current page.
 *
 * Usage:
 *   const tracker = new ScrollTracker((depth) => console.log(depth));
 *   // depth is a 0-1 fraction of page scrolled
 */
export class ScrollTracker {
  private _maxDepth = 0;
  private readonly _handler: () => void;
  private readonly _onUpdate: (depth: number) => void;

  constructor(onUpdate: (depth: number) => void) {
    this._onUpdate = onUpdate;
    this._handler = () => this._onScroll();
    window.addEventListener("scroll", this._handler, { passive: true });
  }

  get maxDepth(): number {
    return this._maxDepth;
  }

  destroy(): void {
    window.removeEventListener("scroll", this._handler);
  }

  private _onScroll(): void {
    const depth = this._computeDepth();
    if (depth > this._maxDepth) {
      this._maxDepth = depth;
      this._onUpdate(this._maxDepth);
    }
  }

  private _computeDepth(): number {
    const scrollTop = window.scrollY;
    const docHeight = document.documentElement.scrollHeight - window.innerHeight;
    if (docHeight <= 0) return 1;
    return Math.min(1, scrollTop / docHeight);
  }
}

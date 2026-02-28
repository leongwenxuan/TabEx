import { describe, it, expect } from "bun:test";

// Smoke test for logger utility
describe("logger", () => {
  it("log function exists and is callable", async () => {
    const { log, warn, error } = await import("./logger.js");
    expect(typeof log).toBe("function");
    expect(typeof warn).toBe("function");
    expect(typeof error).toBe("function");
  });
});

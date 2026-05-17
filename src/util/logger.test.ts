import { describe, expect, test } from "bun:test";
import { createLogger } from "./logger.ts";

describe("createLogger", () => {
  test("info() writes to the configured sink with no level prefix", () => {
    const chunks: string[] = [];
    const log = createLogger((s) => chunks.push(s));
    log.info("hello");
    expect(chunks).toEqual(["hello\n"]);
  });

  test("warn() prefixes the line", () => {
    const chunks: string[] = [];
    const log = createLogger((s) => chunks.push(s));
    log.warn("watch out");
    expect(chunks).toEqual(["warn: watch out\n"]);
  });

  test("error() prefixes the line", () => {
    const chunks: string[] = [];
    const log = createLogger((s) => chunks.push(s));
    log.error("boom");
    expect(chunks).toEqual(["error: boom\n"]);
  });

  test("default sink is stderr (smoke check — call does not throw)", () => {
    const log = createLogger();
    expect(() => log.info("")).not.toThrow();
  });
});

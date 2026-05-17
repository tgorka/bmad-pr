import { describe, expect, test } from "bun:test";
import { BmadPrError } from "./types.ts";

describe("BmadPrError", () => {
  test("carries a refuse code and message", () => {
    const err = new BmadPrError("refuse", "on trunk branch 'main'");
    expect(err).toBeInstanceOf(Error);
    expect(err.code).toBe("refuse");
    expect(err.message).toBe("on trunk branch 'main'");
    expect(err.name).toBe("BmadPrError");
  });

  test("carries a fail code", () => {
    const err = new BmadPrError("fail", "gh exited 128");
    expect(err.code).toBe("fail");
  });
});

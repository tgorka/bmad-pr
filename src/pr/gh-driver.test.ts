import { describe, expect, test } from "bun:test";
import {
  createDraftPr,
  detectGhOnPath,
  editPrBody,
  parsePrNumberFromUrl,
  pushBranch,
} from "./gh-driver.ts";
import type { Runner, RunnerResult } from "./types.ts";
import { BmadPrError } from "./types.ts";

type Call = { cmd: string; args: readonly string[] };

function stubRunner(responses: ReadonlyArray<Partial<RunnerResult>>): {
  runner: Runner;
  calls: Call[];
} {
  const calls: Call[] = [];
  let i = 0;
  const runner: Runner = async (cmd, args) => {
    calls.push({ cmd, args });
    const r = responses[i++] ?? {};
    return {
      stdout: r.stdout ?? "",
      stderr: r.stderr ?? "",
      exitCode: r.exitCode ?? 0,
    };
  };
  return { runner, calls };
}

describe("detectGhOnPath", () => {
  test("true when `gh --version` exits 0", async () => {
    const { runner, calls } = stubRunner([
      { exitCode: 0, stdout: "gh version 2.40.0\n" },
    ]);
    expect(await detectGhOnPath(runner)).toBe(true);
    expect(calls[0]).toEqual({ cmd: "gh", args: ["--version"] });
  });

  test("false when `gh --version` exits non-zero (e.g. ENOENT mapped to 127)", async () => {
    const { runner } = stubRunner([{ exitCode: 127, stderr: "not found" }]);
    expect(await detectGhOnPath(runner)).toBe(false);
  });
});

describe("pushBranch", () => {
  test("runs `git push -u origin HEAD` and returns on success", async () => {
    const { runner, calls } = stubRunner([{ exitCode: 0 }]);
    await pushBranch(runner);
    expect(calls[0]).toEqual({
      cmd: "git",
      args: ["push", "-u", "origin", "HEAD"],
    });
  });

  test("throws BmadPrError('fail') on non-zero exit", async () => {
    const { runner } = stubRunner([
      { exitCode: 128, stderr: "remote rejected" },
    ]);
    try {
      await pushBranch(runner);
      throw new Error("expected throw");
    } catch (err) {
      expect(err).toBeInstanceOf(BmadPrError);
      expect((err as BmadPrError).code).toBe("fail");
      expect((err as BmadPrError).message).toContain("remote rejected");
    }
  });
});

describe("createDraftPr", () => {
  test("invokes gh and returns the URL from stdout", async () => {
    const { runner, calls } = stubRunner([
      { exitCode: 0, stdout: "https://github.com/o/r/pull/42\n" },
    ]);
    const url = await createDraftPr(runner, {
      title: "BMAD: 3.2",
      body: "body",
    });
    expect(url).toBe("https://github.com/o/r/pull/42");
    expect(calls[0]?.cmd).toBe("gh");
    expect(calls[0]?.args).toEqual([
      "pr",
      "create",
      "--draft",
      "--title",
      "BMAD: 3.2",
      "--body",
      "body",
    ]);
  });

  test("throws BmadPrError('fail') when gh exits non-zero", async () => {
    const { runner } = stubRunner([{ exitCode: 1, stderr: "boom" }]);
    expect(
      createDraftPr(runner, { title: "t", body: "b" }),
    ).rejects.toBeInstanceOf(BmadPrError);
  });

  test("throws BmadPrError('fail') when stdout has no URL", async () => {
    const { runner } = stubRunner([{ exitCode: 0, stdout: "weird output\n" }]);
    expect(createDraftPr(runner, { title: "t", body: "b" })).rejects.toThrow(
      /could not parse PR URL/,
    );
  });
});

describe("editPrBody", () => {
  test("invokes gh pr edit <num> --body <body>", async () => {
    const { runner, calls } = stubRunner([{ exitCode: 0 }]);
    await editPrBody(runner, { prNumber: 42, body: "new body" });
    expect(calls[0]?.cmd).toBe("gh");
    expect(calls[0]?.args).toEqual(["pr", "edit", "42", "--body", "new body"]);
  });

  test("throws on non-zero exit", async () => {
    const { runner } = stubRunner([{ exitCode: 1, stderr: "nope" }]);
    expect(
      editPrBody(runner, { prNumber: 7, body: "b" }),
    ).rejects.toBeInstanceOf(BmadPrError);
  });
});

describe("parsePrNumberFromUrl", () => {
  test("extracts the integer trailing /pull/<n>", () => {
    expect(parsePrNumberFromUrl("https://github.com/o/r/pull/123")).toBe(123);
  });

  test("returns null on unparseable input", () => {
    expect(parsePrNumberFromUrl("https://example.com/foo")).toBeNull();
  });
});

import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { Runner, RunnerResult } from "../pr/types.ts";
import { run } from "./bmad-pr.ts";

type Call = { cmd: string; args: readonly string[] };

let tmp: string;

beforeEach(() => {
  tmp = mkdtempSync(join(tmpdir(), "bmad-pr-cli-"));
});

afterEach(() => {
  rmSync(tmp, { recursive: true, force: true });
});

function harness(
  responses: Record<string, ReadonlyArray<Partial<RunnerResult>>>,
): { runner: Runner; calls: Call[]; chunks: string[] } {
  const calls: Call[] = [];
  const cursor: Record<string, number> = {};
  const runner: Runner = async (cmd, args) => {
    calls.push({ cmd, args });
    const key = matchKey(cmd, args, responses);
    const list = responses[key] ?? [];
    const i = cursor[key] ?? 0;
    cursor[key] = i + 1;
    const r = list[i] ?? {};
    return {
      stdout: r.stdout ?? "",
      stderr: r.stderr ?? "",
      exitCode: r.exitCode ?? 0,
    };
  };
  return { runner, calls, chunks: [] };
}

function matchKey(
  cmd: string,
  args: readonly string[],
  responses: Record<string, unknown>,
): string {
  const full = `${cmd} ${args.join(" ")}`;
  if (responses[full]) return full;
  const head2 = `${cmd} ${args.slice(0, 2).join(" ")}`;
  if (responses[head2]) return head2;
  const head1 = `${cmd} ${args[0] ?? ""}`;
  if (responses[head1]) return head1;
  return cmd;
}

const happyResponses = (): Record<
  string,
  ReadonlyArray<Partial<RunnerResult>>
> => ({
  "gh --version": [{ exitCode: 0, stdout: "gh version 2.40.0\n" }],
  "git rev-parse": [{ exitCode: 0, stdout: "feat/x\n" }],
  "git push": [{ exitCode: 0 }],
  "gh pr create": [{ exitCode: 0, stdout: "https://github.com/o/r/pull/42\n" }],
  "gh pr edit": [{ exitCode: 0 }],
});

const stderrOf = (chunks: string[]) => chunks.join("");

describe("run --help", () => {
  test("prints flag list to stdout and exits 0", async () => {
    const stdout: string[] = [];
    const stderr: string[] = [];
    const result = await run(["--help"], {
      runner: harness({}).runner,
      cwd: tmp,
      stdoutSink: (s) => stdout.push(s),
      stderrSink: (s) => stderr.push(s),
    });
    expect(result).toBe(0);
    expect(stdout.join("")).toContain("--story");
    expect(stdout.join("")).toContain("--amend");
  });
});

describe("run open path", () => {
  test("opens a new PR and writes a ledger entry", async () => {
    const { runner, calls } = harness(happyResponses());
    const stdout: string[] = [];
    const stderr: string[] = [];
    const code = await run(
      ["--story", "3.2", "--phase", "dev-story", "--run-id", "R1"],
      {
        runner,
        cwd: tmp,
        stdoutSink: (s) => stdout.push(s),
        stderrSink: (s) => stderr.push(s),
        now: () => new Date("2026-05-17T14:22:03Z"),
      },
    );
    expect(code).toBe(0);
    expect(stdout.join("")).toContain("https://github.com/o/r/pull/42");
    const pushCall = calls.find((c) => c.cmd === "git" && c.args[0] === "push");
    expect(pushCall).toBeDefined();
    const createCall = calls.find(
      (c) => c.cmd === "gh" && c.args[0] === "pr" && c.args[1] === "create",
    );
    expect(createCall).toBeDefined();
    expect(createCall?.args).toContain("--draft");
    const written = readFileSync(
      join(tmp, "_bmad-output/stories/3.2.md"),
      "utf8",
    );
    expect(written).toContain("phase: dev-story");
    expect(written).toContain("status: open");
    expect(written).toContain("runId: R1");
    expect(written).toContain("openedAt: 2026-05-17T14:22:03Z");
    expect(written).toContain("lastAmendedAt: 2026-05-17T14:22:03Z");
  });
});

describe("run auto-amend path", () => {
  test("amends existing open entry on the second invocation", async () => {
    const responses1 = happyResponses();
    const responses2 = happyResponses();
    const h1 = harness(responses1);
    const code1 = await run(["--story", "3.2", "--phase", "dev-story"], {
      runner: h1.runner,
      cwd: tmp,
      stdoutSink: () => {},
      stderrSink: () => {},
      now: () => new Date("2026-05-17T14:00:00Z"),
    });
    expect(code1).toBe(0);
    const h2 = harness(responses2);
    const code2 = await run(["--story", "3.2", "--phase", "dev-story"], {
      runner: h2.runner,
      cwd: tmp,
      stdoutSink: () => {},
      stderrSink: () => {},
      now: () => new Date("2026-05-17T15:00:00Z"),
    });
    expect(code2).toBe(0);
    const editCall = h2.calls.find(
      (c) => c.cmd === "gh" && c.args[0] === "pr" && c.args[1] === "edit",
    );
    expect(editCall).toBeDefined();
    expect(editCall?.args[2]).toBe("42");
    const createAttempt = h2.calls.find(
      (c) => c.cmd === "gh" && c.args[0] === "pr" && c.args[1] === "create",
    );
    expect(createAttempt).toBeUndefined();
    const written = readFileSync(
      join(tmp, "_bmad-output/stories/3.2.md"),
      "utf8",
    );
    expect(written).toContain("openedAt: 2026-05-17T14:00:00Z");
    expect(written).toContain("lastAmendedAt: 2026-05-17T15:00:00Z");
  });

  test("preserves original runId on amend (ignores new --run-id)", async () => {
    const responses1 = happyResponses();
    const h1 = harness(responses1);
    await run(
      ["--story", "3.2", "--phase", "dev-story", "--run-id", "R-ORIGINAL"],
      {
        runner: h1.runner,
        cwd: tmp,
        stdoutSink: () => {},
        stderrSink: () => {},
        now: () => new Date("2026-05-17T14:00:00Z"),
      },
    );
    const responses2 = happyResponses();
    const h2 = harness(responses2);
    await run(["--story", "3.2", "--phase", "dev-story", "--run-id", "R-NEW"], {
      runner: h2.runner,
      cwd: tmp,
      stdoutSink: () => {},
      stderrSink: () => {},
      now: () => new Date("2026-05-17T15:00:00Z"),
    });
    const editCall = h2.calls.find(
      (c) => c.cmd === "gh" && c.args[0] === "pr" && c.args[1] === "edit",
    );
    const bodyArg = editCall?.args[4] ?? "";
    expect(bodyArg).toContain("BMAD-Run-Id: R-ORIGINAL");
    expect(bodyArg).not.toContain("BMAD-Run-Id: R-NEW");
    const written = readFileSync(
      join(tmp, "_bmad-output/stories/3.2.md"),
      "utf8",
    );
    expect(written).toContain("runId: R-ORIGINAL");
    expect(written).not.toContain("runId: R-NEW");
  });
});

describe("run --amend with no match", () => {
  test("refuses with exit 2", async () => {
    const stderr: string[] = [];
    const code = await run(
      ["--story", "3.2", "--phase", "dev-story", "--amend"],
      {
        runner: harness(happyResponses()).runner,
        cwd: tmp,
        stdoutSink: () => {},
        stderrSink: (s) => stderr.push(s),
        now: () => new Date(),
      },
    );
    expect(code).toBe(2);
    expect(stderrOf(stderr)).toContain("requires an existing PR");
  });
});

describe("run refusals", () => {
  test("on trunk branch", async () => {
    const responses = happyResponses();
    responses["git rev-parse"] = [{ exitCode: 0, stdout: "main\n" }];
    const stderr: string[] = [];
    const code = await run(["--story", "3.2", "--phase", "dev-story"], {
      runner: harness(responses).runner,
      cwd: tmp,
      stdoutSink: () => {},
      stderrSink: (s) => stderr.push(s),
      now: () => new Date(),
    });
    expect(code).toBe(2);
    expect(stderrOf(stderr)).toContain("on trunk branch");
  });

  test("missing gh", async () => {
    const responses = happyResponses();
    responses["gh --version"] = [
      { exitCode: 127, stderr: "command not found" },
    ];
    const stderr: string[] = [];
    const code = await run(["--story", "3.2", "--phase", "dev-story"], {
      runner: harness(responses).runner,
      cwd: tmp,
      stdoutSink: () => {},
      stderrSink: (s) => stderr.push(s),
      now: () => new Date(),
    });
    expect(code).toBe(2);
    expect(stderrOf(stderr)).toContain("'gh' CLI not on PATH");
  });

  test("--trunk-branch override refuses on the named branch", async () => {
    const responses = happyResponses();
    responses["git rev-parse"] = [{ exitCode: 0, stdout: "develop\n" }];
    const stderr: string[] = [];
    const code = await run(
      ["--story", "3.2", "--phase", "dev-story", "--trunk-branch", "develop"],
      {
        runner: harness(responses).runner,
        cwd: tmp,
        stdoutSink: () => {},
        stderrSink: (s) => stderr.push(s),
        now: () => new Date(),
      },
    );
    expect(code).toBe(2);
    expect(stderrOf(stderr)).toContain("on trunk branch 'develop'");
  });

  test("flag value starting with -- is rejected", async () => {
    const stderr: string[] = [];
    const code = await run(["--story", "--phase", "dev-story"], {
      runner: harness(happyResponses()).runner,
      cwd: tmp,
      stdoutSink: () => {},
      stderrSink: (s) => stderr.push(s),
      now: () => new Date(),
    });
    expect(code).toBe(2);
    expect(stderrOf(stderr)).toContain("--story requires a value");
  });

  test("malformed --story", async () => {
    const stderr: string[] = [];
    const code = await run(["--story", "foo", "--phase", "dev-story"], {
      runner: harness(happyResponses()).runner,
      cwd: tmp,
      stdoutSink: () => {},
      stderrSink: (s) => stderr.push(s),
      now: () => new Date(),
    });
    expect(code).toBe(2);
    expect(stderrOf(stderr)).toContain("<epic>.<story>");
  });

  test("malformed ledger entry", async () => {
    const storyPath = join(tmp, "_bmad-output/stories/3.2.md");
    const fs = await import("node:fs");
    fs.mkdirSync(join(tmp, "_bmad-output/stories"), { recursive: true });
    writeFileSync(
      storyPath,
      "---\nprs:\n  - phase: dev-story\n    status: open\n    openedAt: x\n    lastAmendedAt: x\n---\n",
    );
    const stderr: string[] = [];
    const code = await run(["--story", "3.2", "--phase", "dev-story"], {
      runner: harness(happyResponses()).runner,
      cwd: tmp,
      stdoutSink: () => {},
      stderrSink: (s) => stderr.push(s),
      now: () => new Date(),
    });
    expect(code).toBe(2);
    expect(stderrOf(stderr)).toContain("missing 'url'");
  });
});

describe("run --dry-run", () => {
  test("prints would-run plan, makes no side-effecting calls", async () => {
    const { runner, calls } = harness(happyResponses());
    const stdout: string[] = [];
    const stderr: string[] = [];
    const code = await run(
      ["--story", "3.2", "--phase", "dev-story", "--dry-run"],
      {
        runner,
        cwd: tmp,
        stdoutSink: (s) => stdout.push(s),
        stderrSink: (s) => stderr.push(s),
        now: () => new Date("2026-05-17T14:22:03Z"),
      },
    );
    expect(code).toBe(0);
    expect(stdout.join("")).toContain("would run: git push");
    expect(stdout.join("")).toContain("would run: gh pr create");
    expect(stdout.join("")).toContain("ledger diff");
    const sideEffectCalls = calls.filter(
      (c) =>
        (c.cmd === "git" && c.args[0] === "push") ||
        (c.cmd === "gh" && (c.args[1] === "create" || c.args[1] === "edit")),
    );
    expect(sideEffectCalls).toHaveLength(0);
    // No story file should be written.
    const fs = await import("node:fs");
    expect(fs.existsSync(join(tmp, "_bmad-output/stories/3.2.md"))).toBe(false);
  });
});

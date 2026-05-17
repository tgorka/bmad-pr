import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  appendEntry,
  findEntry,
  loadLedger,
  parseStoryId,
  resolveStoryPath,
  updateEntry,
} from "./ledger.ts";
import { BmadPrError, type LedgerEntry } from "./types.ts";

let tmp: string;

beforeEach(() => {
  tmp = mkdtempSync(join(tmpdir(), "bmad-pr-ledger-"));
});

afterEach(() => {
  rmSync(tmp, { recursive: true, force: true });
});

const sampleEntry = (overrides: Partial<LedgerEntry> = {}): LedgerEntry => ({
  url: "https://github.com/o/r/pull/1",
  phase: "dev-story",
  status: "open",
  openedAt: "2026-05-17T14:22:03Z",
  lastAmendedAt: "2026-05-17T14:22:03Z",
  ...overrides,
});

describe("parseStoryId", () => {
  test("accepts <epic>.<story> with positive integers", () => {
    expect(parseStoryId("3.2")).toEqual({ epic: 3, story: 2 });
    expect(parseStoryId("12.345")).toEqual({ epic: 12, story: 345 });
  });

  test("rejects malformed input", () => {
    expect(() => parseStoryId("foo")).toThrow(BmadPrError);
    expect(() => parseStoryId("3")).toThrow(BmadPrError);
    expect(() => parseStoryId("3.2.1")).toThrow(BmadPrError);
    expect(() => parseStoryId("0.1")).toThrow(BmadPrError);
    expect(() => parseStoryId("-1.2")).toThrow(BmadPrError);
  });
});

describe("resolveStoryPath", () => {
  test("returns _bmad-output/stories/<epic>.<story>.md under given root", () => {
    const p = resolveStoryPath("/some/repo", { epic: 3, story: 2 });
    expect(p).toBe("/some/repo/_bmad-output/stories/3.2.md");
  });
});

describe("loadLedger", () => {
  test("returns empty prs and body when file is missing", async () => {
    const path = join(tmp, "3.2.md");
    const res = await loadLedger(path);
    expect(res.exists).toBe(false);
    expect(res.prs).toEqual([]);
    expect(res.body).toBe("");
    expect(res.frontmatter).toEqual({});
  });

  test("parses an existing frontmatter ledger", async () => {
    const path = join(tmp, "3.2.md");
    writeFileSync(
      path,
      `---
epic: 3
story: 2
prs:
  - url: https://github.com/o/r/pull/1
    phase: dev-story
    status: open
    openedAt: 2026-05-17T14:22:03Z
    lastAmendedAt: 2026-05-17T14:22:03Z
---

Body content here.
`,
    );
    const res = await loadLedger(path);
    expect(res.exists).toBe(true);
    expect(res.prs).toHaveLength(1);
    expect(res.prs[0]?.url).toBe("https://github.com/o/r/pull/1");
    expect(res.body).toContain("Body content here.");
  });

  test("treats body-only file as empty frontmatter", async () => {
    const path = join(tmp, "3.2.md");
    writeFileSync(path, "Just a body, no frontmatter.\n");
    const res = await loadLedger(path);
    expect(res.exists).toBe(true);
    expect(res.prs).toEqual([]);
    expect(res.body).toContain("Just a body, no frontmatter.");
  });

  test("refuses on malformed ledger entry (missing url)", async () => {
    const path = join(tmp, "3.2.md");
    writeFileSync(
      path,
      `---
prs:
  - phase: dev-story
    status: open
    openedAt: x
    lastAmendedAt: x
---
`,
    );
    expect(loadLedger(path)).rejects.toThrow(/missing 'url'/);
  });
});

describe("findEntry", () => {
  test("matches by phase and open status", () => {
    const prs = [
      sampleEntry({ phase: "prd" }),
      sampleEntry({ phase: "dev-story", status: "merged" }),
      sampleEntry({ phase: "dev-story", status: "open" }),
    ];
    const e = findEntry(prs, { phase: "dev-story" });
    expect(e?.status).toBe("open");
  });

  test("returns null on no match", () => {
    expect(findEntry([], { phase: "x" })).toBeNull();
  });
});

describe("appendEntry", () => {
  test("creates a new file with epic/story/prs frontmatter when missing", async () => {
    const path = join(tmp, "3.2.md");
    await appendEntry(path, { epic: 3, story: 2 }, sampleEntry());
    const written = readFileSync(path, "utf8");
    expect(written.startsWith("---\n")).toBe(true);
    expect(written).toContain("epic: 3");
    expect(written).toContain("story: 2");
    expect(written).toContain("phase: dev-story");
    expect(written).toContain("status: open");
  });

  test("appends to existing prs list and preserves body", async () => {
    const path = join(tmp, "3.2.md");
    writeFileSync(
      path,
      `---
epic: 3
story: 2
prs:
  - url: https://github.com/o/r/pull/1
    phase: brainstorm
    status: open
    openedAt: 2026-05-17T10:00:00Z
    lastAmendedAt: 2026-05-17T10:00:00Z
---

# Story body
Preserved.
`,
    );
    await appendEntry(
      path,
      { epic: 3, story: 2 },
      sampleEntry({ url: "https://github.com/o/r/pull/2", phase: "dev-story" }),
    );
    const written = readFileSync(path, "utf8");
    expect(written).toContain("/pull/1");
    expect(written).toContain("/pull/2");
    expect(written).toContain("# Story body");
    expect(written).toContain("Preserved.");
  });

  test("upgrades a body-only file to frontmatter, preserving body", async () => {
    const path = join(tmp, "3.2.md");
    writeFileSync(path, "Body only.\n");
    await appendEntry(path, { epic: 3, story: 2 }, sampleEntry());
    const written = readFileSync(path, "utf8");
    expect(written.startsWith("---\n")).toBe(true);
    expect(written).toContain("Body only.");
  });
});

describe("YAML serializer hardening", () => {
  test("quotes YAML reserved-word strings to preserve round-trip", async () => {
    const path = join(tmp, "3.2.md");
    await appendEntry(
      path,
      { epic: 3, story: 2 },
      sampleEntry({
        runId: "no",
        phase: "yes",
      }),
    );
    const reloaded = await loadLedger(path);
    expect(reloaded.prs[0]?.runId).toBe("no");
    expect(reloaded.prs[0]?.phase).toBe("yes");
    const text = readFileSync(path, "utf8");
    expect(text).toContain('phase: "yes"');
    expect(text).toContain('runId: "no"');
  });

  test("quotes numeric-looking strings to preserve type", async () => {
    const path = join(tmp, "3.2.md");
    await appendEntry(
      path,
      { epic: 3, story: 2 },
      sampleEntry({ runId: "42", phase: "007" }),
    );
    const reloaded = await loadLedger(path);
    expect(reloaded.prs[0]?.runId).toBe("42");
    expect(reloaded.prs[0]?.phase).toBe("007");
  });

  test("frontmatter regex requires `---` on its own line", async () => {
    const path = join(tmp, "3.2.md");
    writeFileSync(
      path,
      `---
epic: 3
story: 2
prs: []
---

# Body with --- inline
Some content with --- inside.
`,
    );
    const res = await loadLedger(path);
    expect(res.exists).toBe(true);
    expect(res.frontmatter.epic).toBe(3);
    expect(res.body).toContain("# Body with --- inline");
  });
});

describe("updateEntry", () => {
  test("mutates the matching entry, leaves others alone", async () => {
    const path = join(tmp, "3.2.md");
    writeFileSync(
      path,
      `---
epic: 3
story: 2
prs:
  - url: https://github.com/o/r/pull/1
    phase: dev-story
    status: open
    openedAt: 2026-05-17T10:00:00Z
    lastAmendedAt: 2026-05-17T10:00:00Z
---
`,
    );
    await updateEntry(
      path,
      (e) => e.phase === "dev-story",
      (e) => ({ ...e, lastAmendedAt: "2026-05-17T15:00:00Z" }),
    );
    const written = readFileSync(path, "utf8");
    expect(written).toContain("lastAmendedAt: 2026-05-17T15:00:00Z");
    expect(written).not.toContain("lastAmendedAt: 2026-05-17T10:00:00Z");
  });

  test("refuses when no entry matches", async () => {
    const path = join(tmp, "3.2.md");
    writeFileSync(path, "---\nprs: []\n---\n");
    expect(
      updateEntry(
        path,
        () => true,
        (e) => e,
      ),
    ).rejects.toThrow(/no matching entry/);
  });
});

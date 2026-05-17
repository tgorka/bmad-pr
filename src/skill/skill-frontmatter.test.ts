import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const SKILL_PATH = join(
  __dirname,
  "..",
  "..",
  ".claude",
  "skills",
  "bmad-pr",
  "SKILL.md",
);
const FRONTMATTER_RE = /^---\r?\n([\s\S]*?)\r?\n^---\r?\n/m;

describe(".claude/skills/bmad-pr/SKILL.md", () => {
  const text = readFileSync(SKILL_PATH, "utf8");
  const m = FRONTMATTER_RE.exec(text);
  const parsed = m?.[1] ? Bun.YAML.parse(m[1]) : null;
  const fm =
    parsed && typeof parsed === "object" && !Array.isArray(parsed)
      ? (parsed as Record<string, unknown>)
      : null;

  test("has a parseable YAML frontmatter block", () => {
    expect(m).not.toBeNull();
    expect(fm).not.toBeNull();
  });

  test("name is 'bmad-pr' (kebab-case, letters/numbers/hyphens only)", () => {
    expect(fm?.name).toBe("bmad-pr");
    expect(typeof fm?.name).toBe("string");
    expect((fm?.name as string).match(/^[a-z0-9-]+$/)).not.toBeNull();
  });

  test("description starts with 'Use when' (anthropic skill convention)", () => {
    expect(typeof fm?.description).toBe("string");
    expect((fm?.description as string).startsWith("Use when")).toBe(true);
  });

  test("frontmatter stays under the 1024-character budget", () => {
    const fmText = m?.[1] ?? "";
    expect(fmText.length).toBeLessThan(1024);
  });

  test("body documents both --dry-run and --amend (the two non-default modes)", () => {
    const body = text.slice(m?.[0]?.length ?? 0);
    expect(body).toContain("--dry-run");
    expect(body).toContain("--amend");
  });
});

import type { Runner } from "./types.ts";
import { BmadPrError } from "./types.ts";

export async function detectGhOnPath(runner: Runner): Promise<boolean> {
  const { exitCode } = await runner("gh", ["--version"]);
  return exitCode === 0;
}

export async function pushBranch(runner: Runner): Promise<void> {
  const r = await runner("git", ["push", "-u", "origin", "HEAD"]);
  if (r.exitCode !== 0) {
    throw new BmadPrError("fail", `git push failed: ${r.stderr.trim()}`);
  }
}

export type CreateDraftPrInput = { title: string; body: string };

export async function createDraftPr(
  runner: Runner,
  { title, body }: CreateDraftPrInput,
): Promise<string> {
  const r = await runner("gh", [
    "pr",
    "create",
    "--draft",
    "--title",
    title,
    "--body",
    body,
  ]);
  if (r.exitCode !== 0) {
    throw new BmadPrError("fail", `gh pr create failed: ${r.stderr.trim()}`);
  }
  const url = extractUrl(r.stdout);
  if (!url) {
    throw new BmadPrError(
      "fail",
      `could not parse PR URL from gh output: ${r.stdout.trim()}`,
    );
  }
  return url;
}

export type EditPrBodyInput = { prNumber: number; body: string };

export async function editPrBody(
  runner: Runner,
  { prNumber, body }: EditPrBodyInput,
): Promise<void> {
  const r = await runner("gh", [
    "pr",
    "edit",
    String(prNumber),
    "--body",
    body,
  ]);
  if (r.exitCode !== 0) {
    throw new BmadPrError("fail", `gh pr edit failed: ${r.stderr.trim()}`);
  }
}

export function parsePrNumberFromUrl(url: string): number | null {
  const m = /\/pull\/(\d+)(?:[/?#]|$)/.exec(url);
  if (!m?.[1]) return null;
  const n = Number.parseInt(m[1], 10);
  return Number.isFinite(n) ? n : null;
}

function extractUrl(stdout: string): string | null {
  const m = /(https?:\/\/\S+\/pull\/\d+)/.exec(stdout);
  return m?.[1] ?? null;
}

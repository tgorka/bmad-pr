import type { Runner, RunnerResult } from "./types.ts";

function spawnPiped(
  cmd: string,
  args: readonly string[],
  cwd: string | undefined,
) {
  return Bun.spawn([cmd, ...args], {
    cwd,
    stdout: "pipe",
    stderr: "pipe",
  });
}

function isBinaryNotFound(err: unknown): boolean {
  if (!(err instanceof Error)) return false;
  const code = (err as Error & { code?: unknown }).code;
  if (code === "ENOENT") return true;
  // Narrow textual fallback for Bun versions that don't surface a `.code`
  // field. Matches Bun.spawn's own "Executable not found" wording and the
  // posix_spawn ENOENT formatting. Anything else re-throws.
  return /^(?:Executable ".*" not found|posix_spawn.*ENOENT|ENOENT: )/i.test(
    err.message,
  );
}

export const runCommand: Runner = async (cmd, args, opts) => {
  let proc: ReturnType<typeof spawnPiped>;
  try {
    proc = spawnPiped(cmd, args, opts?.cwd);
  } catch (err) {
    if (isBinaryNotFound(err)) {
      const message = err instanceof Error ? err.message : String(err);
      return { stdout: "", stderr: message, exitCode: 127 };
    }
    throw err;
  }
  const [stdout, stderr] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ]);
  const exitCode = await proc.exited;
  const result: RunnerResult = { stdout, stderr, exitCode };
  return result;
};

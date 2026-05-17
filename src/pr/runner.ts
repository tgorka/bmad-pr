import type { Runner, RunnerResult } from "./types.ts";

export const runCommand: Runner = async (cmd, args, opts) => {
  try {
    const proc = Bun.spawn([cmd, ...args], {
      cwd: opts?.cwd,
      stdout: "pipe",
      stderr: "pipe",
    });
    const [stdout, stderr] = await Promise.all([
      new Response(proc.stdout).text(),
      new Response(proc.stderr).text(),
    ]);
    const exitCode = await proc.exited;
    const result: RunnerResult = { stdout, stderr, exitCode };
    return result;
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    return { stdout: "", stderr: message, exitCode: 127 };
  }
};

import { describe, test, expect, beforeEach, afterEach } from "vitest";
import { mkdirSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { loadHooks } from "../src/core/hooks/loader.js";
import { loadInstructions } from "../src/core/instructions.js";
import { listInstalledSkills } from "../src/core/skills/manager.js";

// Regression tests for SOULFORGE_NO_CLAUDE=1 (clean launch: no .claude
// hooks, skills, or instructions merge/load).

const root = join(tmpdir(), `soulforge-no-claude-${Date.now()}`);
const projectDir = join(root, "proj");
const fakeHome = join(root, "home");

function write(rel: string, content: string) {
  const full = join(projectDir, rel);
  mkdirSync(full.replace(/\/[^/]+$/, ""), { recursive: true });
  writeFileSync(full, content);
}

function writeHome(rel: string, content: string) {
  const full = join(fakeHome, rel);
  mkdirSync(full.replace(/\/[^/]+$/, ""), { recursive: true });
  writeFileSync(full, content);
}

let saved: string | undefined;

beforeEach(() => {
  saved = process.env.SOULFORGE_NO_CLAUDE;
  rmSync(root, { recursive: true, force: true });
  mkdirSync(projectDir, { recursive: true });
  mkdirSync(fakeHome, { recursive: true });
});

afterEach(() => {
  if (saved === undefined) delete process.env.SOULFORGE_NO_CLAUDE;
  else process.env.SOULFORGE_NO_CLAUDE = saved;
  rmSync(root, { recursive: true, force: true });
});

describe("SOULFORGE_NO_CLAUDE hooks", () => {
  test("without flag: .claude hooks load", () => {
    delete process.env.SOULFORGE_NO_CLAUDE;
    write(".claude/settings.json", JSON.stringify({ hooks: { PreToolUse: [{ matcher: "Bash", hooks: [{ type: "command", command: "echo claude" }] }] } }));
    const hooks = loadHooks(projectDir, { homeDir: fakeHome });
    expect(hooks.PreToolUse).toHaveLength(1);
  });

  test("with flag: .claude hooks skipped, .soulforge kept", () => {
    process.env.SOULFORGE_NO_CLAUDE = "1";
    write(".claude/settings.json", JSON.stringify({ hooks: { PreToolUse: [{ matcher: "Bash", hooks: [{ type: "command", command: "echo claude" }] }] } }));
    write(".claude/settings.local.json", JSON.stringify({ hooks: { PreToolUse: [{ matcher: "Bash", hooks: [{ type: "command", command: "echo local" }] }] } }));
    write(".soulforge/config.json", JSON.stringify({ hooks: { PreToolUse: [{ matcher: "Edit", hooks: [{ type: "command", command: "echo sf" }] }] } }));
    const hooks = loadHooks(projectDir, { homeDir: fakeHome });
    expect(hooks.PreToolUse).toHaveLength(1);
    expect(hooks.PreToolUse![0].matcher).toBe("Edit");
  });

  test("with flag: home .claude/settings.json skipped", () => {
    process.env.SOULFORGE_NO_CLAUDE = "1";
    writeHome(".claude/settings.json", JSON.stringify({ hooks: { PreToolUse: [{ matcher: "Bash", hooks: [{ type: "command", command: "echo home" }] }] } }));
    const hooks = loadHooks(projectDir, { homeDir: fakeHome });
    expect(hooks.PreToolUse).toBeUndefined();
  });
});

describe("SOULFORGE_NO_CLAUDE instructions", () => {
  test("with flag: claude source skipped even when explicitly enabled", () => {
    process.env.SOULFORGE_NO_CLAUDE = "1";
    write("CLAUDE.md", "claude steering");
    write("SOULFORGE.md", "soulforge steering");
    const loaded = loadInstructions(projectDir, ["soulforge", "claude"], { homeDir: fakeHome });
    expect(loaded.some((l) => l.source === "claude")).toBe(false);
    expect(loaded.some((l) => l.source === "soulforge")).toBe(true);
  });

  test("without flag: claude source loads when enabled", () => {
    delete process.env.SOULFORGE_NO_CLAUDE;
    write("CLAUDE.md", "claude steering");
    const loaded = loadInstructions(projectDir, ["claude"], { homeDir: fakeHome });
    expect(loaded).toHaveLength(1);
    expect(loaded[0].source).toBe("claude");
  });
});

describe("SOULFORGE_NO_CLAUDE skills", () => {
  function seedSkills() {
    const mk = (rel: string) => {
      const dir = join(projectDir, rel);
      mkdirSync(dir, { recursive: true });
      writeFileSync(join(dir, "SKILL.md"), "# skill");
    };
    mk(".claude/skills/foo");
    mk(".soulforge/skills/bar");
  }

  test("without flag: .claude skills listed", () => {
    delete process.env.SOULFORGE_NO_CLAUDE;
    seedSkills();
    const names = listInstalledSkills({ cwd: projectDir }).map((s) => s.name);
    expect(names).toContain("foo");
    expect(names).toContain("bar");
  });

  test("with flag: .claude skills skipped, soulforge kept", () => {
    process.env.SOULFORGE_NO_CLAUDE = "1";
    seedSkills();
    const names = listInstalledSkills({ cwd: projectDir }).map((s) => s.name);
    expect(names).not.toContain("foo");
    expect(names).toContain("bar");
  });
});

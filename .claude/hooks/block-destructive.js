// PreToolUse(Bash) guard: deny infra-destroying commands.
// stdin: hook JSON -> stdout: {"hookSpecificOutput":{"permissionDecision":"deny",...}}
const DENY = [
  /\bterraform\b[\s\S]*\bdestroy\b/i,
  /\bterraform\b[\s\S]*-destroy\b/i,
  /\bterraform\s+state\s+(rm|mv)\b/i,
  /\bterraform\s+(taint|force-unlock)\b/i,
  /\bterraform\s+workspace\s+delete\b/i,
  /\bterraform\b[\s\S]*-auto-approve\b/i,
  /\baws\s+s3\s+rb\b/i,
  /\baws\s+s3\s+rm\b[\s\S]*--recursive\b/i,
  /\baws\s+s3api\s+delete-bucket\b/i,
  /\baws\s+cloudfront\s+delete-distribution\b/i,
];

let raw = "";
process.stdin.on("data", (c) => (raw += c));
process.stdin.on("end", () => {
  const cmd = (JSON.parse(raw || "{}").tool_input || {}).command || "";
  const hit = DENY.find((r) => r.test(cmd));
  if (hit) {
    process.stdout.write(JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason:
          `Blocked by CLAUDE.md infra policy (matched ${hit}). Destructive Terraform/AWS commands are never run from Claude Code. Do not rephrase to evade this — tell the human to do it manually.`,
      },
    }));
  }
  process.exit(0);
});

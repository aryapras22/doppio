---
name: agy-dispatch
description: Use when a planned task has a clear scope and a test command that decides pass or fail. Sends it to Antigravity (agy) builders in separate worktrees, then validates the result.
---

# agy-dispatch

You plan and validate. agy builders write, test and fix inside their own git worktree. A packet without an acceptance command is not ready for agy: do it yourself or write the test first.

## Loop

1. Split the request into task packets in `.plans/T1.md`, `.plans/T2.md`, and so on. Packets must not touch the same files.
2. Write or pick the tests for each packet before any code exists. Pass and fail are fixed by you, not the builder.
3. Start up to 3 independent packets, then wait:
   ```
   cc-agy start .plans/T1.md
   cc-agy start .plans/T2.md
   cc-agy wait --all --timeout 540
   ```
   `wait` returns after at most 540 s. If it prints "still running", call it again. `cc-agy status` lists every run.
4. Validate each result block: read the diff in the worktree, rerun the acceptance command yourself, and confirm test files are unchanged.
5. Send problems back: `cc-agy continue T2 "<feedback>"`, at most 2 rounds per packet. After that, raise the model: Hydrogen `high`, then Hydrogen `xhigh`, then Argon `high` (edit `model` and `effort` in the packet and `cc-agy start` again with `--handoff`), then do it yourself.
6. Merge passing branches (`agy/T1`) one at a time and run the full suite after each merge.

## Packet

```markdown
---
id: T3
title: coupon rules
model: gemini-4-hydrogen
effort: high
acceptance: npm test -- cart
scope: [src/cart/**, src/api/cart.ts]
---
# Goal
<what to build>
# Constraints
<rules, interfaces to keep>
```

`cc-agy` joins model and effort into the slug `agy models` lists (`gemini-4-hydrogen-high`). The working tree must be clean before `start`; packets under `.plans/` are ignored for that check.

## Rollover

Every packet starts a new agy conversation. The result block ends with a context line.

- Context below 50% and no checkpoints: follow up with `cc-agy continue`. It refuses otherwise.
- 50% or more, or any checkpoint: write a handoff file (files changed, what still fails, decisions) from the result and `git diff`, then `cc-agy start .plans/T3.md --handoff handoff.md`. The new run continues in the same worktree with the packet plus the handoff.

## Rules

- Never pass `-c` to agy; `cc-agy` always resumes by conversation id.
- Builders run unattended with permissions skipped, inside their worktree only.
- Open the run log only when a run fails; the result block names its path.
- `cc-agy cancel T3` stops a run.

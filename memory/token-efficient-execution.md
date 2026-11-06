---
name: token-efficient-execution
description: "SpaceGame plan execution defaults to cut token use - bigger tasks, batched reviews, cheap fixers, fresh execution session"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 51257020-630e-4ad8-8fdd-07d0b2e643ba
  modified: 2026-11-06T19:03:22.715Z
---

Default for executing SpaceGame plans (user approved 2026-11-03 after a token-usage analysis):

- **Bigger tasks:** write plans with 3-5 bigger tasks, not 9 small ones. Merge tasks that touch the same files.
- **Keep the builder check** on specs.
- **Batch reviews:** one reviewer per 2-3 tasks (or per large task), never per small or mechanical task.
- **Always do a final whole-branch review** on the most capable model.
- **No re-review for small fixes** (under ~50 lines). Trust the test evidence plus the final review.
- **Fresh fixers:** send fix rounds to a fresh cheap subagent with only the finding and file paths, not a resumed implementer.
- **Short reports:** subagents return at most ~10 lines and put detail in report files.
- **File handoffs for big context:** when a handoff is over ~500 tokens or has 2+ consumers, the writing agent saves a terse brief (goal, decisions, relevant file paths, open questions) to the scratchpad dir, not the repo. The orchestrator passes only the path, and the prompt says to read it first. Inline anything smaller. Overwrite or delete stale briefs. This avoids the orchestrator re-emitting content as output tokens.
- **Fresh session for execution:** suggest starting one with just the plan and ledger, rather than continuing a long brainstorm session.
- **Small plans:** for 3 tasks or fewer, implementing natively (no subagents) is fine.

**Why:** in the crew-mechanic run (~2.8M subagent tokens, 9 tasks), per-task reviews of small tasks found nothing important. Resumed fix rounds cost ~110k each, and scoped re-reviews never caught anything. The final whole-branch review and the builder check caught the worst bugs. The combat rework run, with reviews only on large changes, cost less than half and still caught its serious issues.

**How to apply:** this overrides subagent-driven-development's per-task review and re-review loop for SpaceGame. Pairs with [[build-on-main]].

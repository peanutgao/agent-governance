---
name: grilling
description: Relentless one-question-at-a-time requirement and design interrogation using a decision tree until shared understanding is reached. Use when requirements are ambiguous, a plan needs stress-testing, or the user mentions "grilling", "grill me", "grill-me", or "challenge my thinking".
---

# Grilling

Interview the user relentlessly until you reach a shared understanding. Map open decisions as a **design tree**: every decision branches into the sub-decisions that depend on it.

## How to run the session

1. **Look up facts first (in parallel).** If a question can be answered from the codebase, Specs, Contracts, ADRs, or environment, check it yourself with batched/parallel read-only lookups (use a fast lightweight read-only sub-agent when available). Never ask the user to confirm verifiable facts.
2. **Prune from the root first.** Order questions by maximum pruning value: scope & Non-Goals → core architecture/route → contracts → edge behavior. Answering one root question should eliminate whole downstream subtrees.
3. **Skip reversible defaults.** Do NOT spend a round on low-risk, easily reversible engineering defaults (naming, standard timeouts/pagination, routine copy). Pick the best-practice default and list all adopted defaults in one compact line at closure.
4. **Strictly one question at a time, with fast-track preview.** Never dump a multi-question checklist. Ask only the single highest-value frontier question, and add a one-line preview of possible remaining branch names (no answer required) so the user can either answer one-by-one or say `"A, 其余按建议直接做"` to fast-track into implementation.
5. **Verify every answer independently.** Check each answer against approved Specs, Contracts, code, or reproduction evidence. Never silently accept a factually false premise; distinguish verifiable factual conflicts from explicit business trade-offs.

## Question format

Keep every field to **1 concise sentence** (3-second scan), with lettered options and the recommended choice first:

```text
情景：一句话交代当前事实与待决分支。
影响：一句话说明对范围、契约或返工的影响。
建议：A（推荐）... / B ...（一句话理由；建议不是决定）。
问题：选择 A 还是 B？（后续可能分支：<名称1>、<名称2>，视本问结果决定；可回「A，其余按建议直接做」快通）
```

When the user's previous answer conflicts with Spec, Contract, code, or reproduction evidence, challenge respectfully before moving on:

```text
情景：你刚才的回答是「...」，当前正在决定「...」。
核对：Spec / Contract / 代码 / 复现结果显示「...」。
冲突：这与「...」不一致，可能导致「...」影响。
建议：A（推荐）... / B ...。
问题：是否确认采用 A？
```

## Stopping condition

The session ends when all high-impact branches are resolved (or the user fast-tracks remaining reversible branches with defaults). Close with a concise summary listing confirmed decisions and adopted defaults.

`grilling` only surfaces assumptions, exposes gaps, and drives decisions; its output is not authoritative Spec until the user confirms and the confirmed decisions are written into the project's Spec, Contract, or ADR. Do not start implementation until shared understanding is confirmed.

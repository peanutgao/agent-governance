---
name: grilling
description: Relentless one-question-at-a-time requirement and design interrogation using a decision tree until shared understanding is reached. Use when requirements are ambiguous, a plan needs stress-testing, or the user mentions "grilling", "grill me", "grill-me", or "challenge my thinking".
---

# Grilling

Interview the user relentlessly until you reach a shared understanding. Map open decisions as a **design tree**: every decision branches into the sub-decisions that depend on it.

## How to run the session

1. **Look up facts first.** If a question can be answered from the codebase, Specs, Contracts, ADRs, or environment, check it yourself (or delegate lookup to a read-only sub-agent when available). Never ask the user to confirm verifiable facts.
2. **Start with top-level branches.** Outline the key top-level decision branches (typically 3–6 items) and start with the most foundational branch whose prerequisites are already settled (the **frontier**).
3. **Walk one branch at a time, one question at a time.** Never dump a multi-question checklist. Wait for the user's answer before picking the next question.
4. **Verify every answer independently.** Treat each answer as input to be checked against approved Specs, Contracts, code, or reproduction evidence. Never silently accept a factually false premise.
5. **Distinguish facts from business choices.** Directly point out verifiable factual conflicts with evidence; respect explicit business trade-offs once the user understands the impact.

## Question format

Use this unified format (aligned with `global/AGENTS.md` and `ai-change-flow`) for every round:

```text
情景：说明当前已知事实、正在处理的决策分支和触发问题。
影响：说明这个决定会影响什么范围、契约或后续实现。
建议：给出 AI 推荐的选项和理由；建议不是用户决定。
问题：只提出一个当前最需要用户确认的问题。
```

When the user's previous answer conflicts with Spec, Contract, code, or reproduction evidence, challenge respectfully before moving on:

```text
情景：你刚才的回答是「...」，当前正在决定「...」。
核对：Spec / Contract / 代码 / 复现结果显示「...」。
冲突：这与「...」不一致，可能导致「...」影响。
建议：我建议「...」，理由是「...」。
问题：是否确认采用「...」？
```

## Stopping condition

The session ends when the frontier is empty — every branch of the design tree is resolved with no remaining "it depends" gaps. Close with a concise summary of the confirmed decisions.

`grilling` only surfaces assumptions, exposes gaps, and drives decisions; its output is not authoritative Spec until the user confirms and the confirmed decisions are written into the project's Spec, Contract, or ADR. Do not start implementation until shared understanding is confirmed.

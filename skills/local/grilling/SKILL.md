---
name: grilling
description: Grill the user relentlessly about a plan, decision, or idea. Use when the user wants to stress-test their thinking, or uses any 'grill' trigger phrases.
---

Interview the user relentlessly until you reach a shared understanding. Map this as a **design tree**: every decision branches into the decisions that hang off it.

The **frontier** is the set of decisions whose prerequisites are already settled. Ask one question at a time. State the known evidence, explain the impact of the decision, and recommend an answer. Wait for the user's answer before choosing the next question.

Each question should be formatted like so:

```
❓ **Q1** - **<question title>**: <question body, might be multiple paragraphs, including multiple choices>

➡️ <your recommended answer>
```

Use each answer to update the tree. Verify factual claims against the approved requirements, code, documented contracts, or a reproduction. When evidence contradicts a claim, explain the conflict and its effect before asking for the next decision.

Look up facts in the available environment. Delegate the lookup when a sub-agent is available and permitted, or check the sources in the current session. Ask the user to make decisions and confirm tradeoffs.

The session is done when the frontier is empty: every branch of the design tree visited, nothing left silently assumed. Do not act on it until the user confirms you have reached a shared understanding.

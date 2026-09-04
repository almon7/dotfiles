---
name: trello-learning-queue
description: Find concept-learning and reading reminders in Trello, research them in priority order, and produce layered, source-linked briefings with optional Trello completion sync. Use when the user asks to review, explain, study, or clear learning items from their Trello queue; do not use for a general task or ticket status report.
---

# Trello Learning Queue

Turn the user's Trello learning reminders into a prioritized set of concise but expandable briefings. Treat Trello as the live source of truth and preserve the connection between every briefing and its card.

## Find the queue

Use the connected Trello tools. Read all pages needed for open cards from the relevant board and the separate personal Inbox. If the board is not yet known, list the user's boards and select the clear personal task board; ask only when multiple boards are plausible.

Consider these priority buckets in this order:

1. `Today`
2. `This Week`
3. `Next Week`
4. Trello Inbox

Match list names case-insensitively and tolerate minor spelling or punctuation differences. If there is no `Next Week` list, use incomplete cards whose due dates fall in the next calendar week in the user's Trello timezone; do not treat an undated `Later` card as next week. Preserve card position within each bucket. Exclude archived or completed cards.

## Recognize learning reminders

Judge the card name, description, links, attachments, labels, checklist text, list, and due date together. Include cards that are probably reminders to learn or understand something, such as:

- a technique, concept, product, library, protocol, system, or engineering term named as a short noun phrase;
- a paper title, DOI, arXiv identifier, article, documentation page, website, talk, or video saved for reading or viewing;
- explicit learning language such as `read`, `learn`, `understand`, `look up`, `what is`, or `how does`;
- a resource whose description is mainly a synopsis rather than an assigned deliverable.

Do not include a card merely because research could help complete it. Exclude operational work, implementation tickets, errands, and stakeholder follow-ups when the primary outcome is to set up, build, fix, send, schedule, confirm, or deliver something. Treat meeting-assigned work, promised deadlines, and named-recipient follow-ups as strong evidence against classification as a personal learning reminder.

An unlabeled meeting recording, demo, or generic video title is ambiguous unless its topic or learning purpose is evident; do not promote it solely because it is media.

Prefer precision over recall. Put plausible but genuinely ambiguous cards in a short `Possible learning reminders` section without researching them, so the user can opt them in. Never silently convert or relabel cards.

## Research efficiently

Open the saved source before searching around it. For a bare concept, identify the intended meaning from nearby card context; if two meanings remain equally plausible, state the ambiguity and ask one focused question rather than researching the wrong subject.

Use current, authoritative sources:

- papers: the original paper or publisher/arXiv page, plus official code or author material when useful;
- software and engineering topics: official documentation, standards, specifications, or maintainers' material;
- broader concepts: primary sources where available, supplemented by a strong technical explainer when it materially improves clarity.

Link claims close to the text they support. Prefer links to a relevant heading, anchor, paper section, or PDF page over a generic home page. Do not claim to have read inaccessible content; explain what was and was not available.

When native subagents or parallel research agents are available, delegate one card per agent, or one tightly related cluster when cards substantially overlap. Use as much parallelism as the host safely exposes while retaining one coordinating agent. Give each worker the card text and URL, source-quality requirements, the reader profile below, and the requested briefing shape. The coordinating agent must verify source fit, reconcile overlaps or contradictions, and sort the final result. In Codex, use collaboration subagents rather than creating persistent user-facing tasks. If delegation is unavailable, research sequentially and keep the same output quality.

## Write for this reader

Assume the reader has a master's-level data science and machine-learning background but less software-engineering experience.

- Do not re-teach familiar ML fundamentals unless they are directly relevant.
- Define software-engineering and systems terms on first use, including what role they play in the larger system.
- Prefer a concrete mental model and a small practical example over unexplained jargon.
- Distinguish the core idea from implementation details, operational trade-offs, and vendor-specific behavior.

## Present the briefings

Start with the researched cards, grouped and ordered by `Today`, `This Week`, `Next Week`, then `Inbox`. Give each item a stable run-local ID such as `T1`, `W1`, `N1`, or `I1`, its Trello link, and its priority bucket.

For every item, write a short self-contained paragraph of roughly 3–6 sentences. It should be enough to make the reader conversationally and practically competent: say what the thing is, the mental model for how it works, when it is useful, and the most important limitation or trade-off.

Then add only the drill-downs that improve understanding, preferably in collapsible HTML when the client renders it:

```html
<details>
<summary>How it works</summary>

Additional explanation with source links.

</details>
```

Useful drill-downs include `How it works`, `Concrete example`, `Engineering context`, and `Trade-offs and failure modes`. Keep links scattered near the relevant claims instead of collecting an undifferentiated bibliography. If collapsible sections are unsupported, use compact level-four headings instead.

End with `Possible learning reminders` if any ambiguous cards were found. Also state the completion interaction in one short line: use the client's interactive completion control if one is available, otherwise invite the user to reply with IDs such as `done T1, W2`.

## Sync completion to Trello

Researching or displaying a card does not complete it. Mark a Trello card done only after an explicit user action for that item: an interactive check event delivered by the client, or a clear message such as `done T1` or `mark BM25 search complete`. A Markdown checkbox by itself is only visual unless the host explicitly reports its interaction, so never imply automatic sync when the client cannot provide it.

Keep the run-local ID-to-card-ARI mapping in the conversation. Before writing, re-read the target card when practical, then call Trello's card completion operation with the exact card ARI. Do not archive or move the card. Report which cards were marked done and any that could not be updated; never broaden a vague completion request to every researched card.

For a card from the separate Trello Inbox, use the generic card `mark_done` operation only if it accepts the Inbox card ARI. If the connector does not support that operation for Inbox cards, leave the card unchanged and report that completion sync is unavailable for that item.

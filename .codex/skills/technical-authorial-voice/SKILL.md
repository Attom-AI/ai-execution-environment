---
name: technical-authorial-voice
description: Apply the author's first-principles, mechanism-oriented technical writing voice to articles, tutorials, workshops, project pages, social posts, essays, and short copy such as summaries, excerpts, and section intros. Use when drafting, revising, or reviewing any technical writing or site copy for this author.
---

# Technical Authorial Voice

## Mission & Overriding Principle

> **Rigor in inquiry. Economy in expression. Depth according to purpose.**
> 
> *The intended outcome is a more discriminating editor, not a more elaborate style guide.*

This skill reproduces the author's disciplined method of inquiry, reasoning, and technical explanation. It prioritizes modeling the author's **reasoning process before modeling prose**. Successful execution is not measured by the volume of rules or edits, but by the ability to make the **smallest effective correction**—explaining *why* an argumentative transition requires adjustment while preserving the author's authentic voice without imposing a rigid formula onto future work.

---

## Core Operational Rules

1. **Declarative & Analytical**: State assertions directly based on evidence and mechanisms. Avoid promotional hype, performative hooks, corporate cheer, and meta-talk (*"In this article..."*, *"Let's explore..."*).
2. **First-Principles Derivation**: Establish the physical or architectural constraint and why it matters before naming solutions.
3. **Causal Mechanisms Over Buzzwords**: Never assume naming a pattern constitutes an explanation. Explain *how* components interact causally, *why* they work, and *under what conditions they fail*.
4. **Bidirectional Reverse Reasoning**: Derive abstractions forward, then stress-test them backward against realistic failure modes (partitions, clock drift, race conditions) to isolate boundaries and invariants.
5. **No Forced Analogies**: The author's scientific and literary influences govern *intellectual discipline*, not superficial metaphors. Never force historical or scientific analogies onto software engineering mechanisms (e.g., no Newtonian physics in a discussion of locks).
6. **Zero Fabrication**: Strictly distinguish observed fact, reference architecture, assumption, and inference. Never invent metrics, benchmarks, citations, or production incidents.
7. **Conservative Editorial Judgment**: When revising author-written material, identify the central proposition, preserve deliberate phrasing, and execute targeted corrections rather than wholesale rewrites. Never homogenize the author's voice into generic corporate or AI-generated prose.
8. **Integrated Authorial Stance**: When discussing firsthand engineering work, establish authorship directly and weave it naturally into the logical argument (e.g., *"I built"*, *"I designed"* are fully legitimate when anchoring technical rationale; avoid passive evasion as well as promotional self-aggrandizement).

---

## Format Adaptations & Short Copy

- **Short Copy (Summaries, Excerpts, Section Openers)**:
  - Open immediately with the core claim or architectural tension.
  - **Never** begin with *"How..."*, *"This article explains..."*, or a rhetorical question.
  - **No comma-separated laundry lists** or chains of gerunds (*"comparing X, analyzing Y, and eliminating Z"*).
  - Strictly observe length bounds (e.g., under 300 characters for site card summaries).
- For detailed medium guidelines (Long Articles, Engineering Workshops, Technical Essays, Social Posts, Draft Reviews), see [`references/format-guidelines.md`](references/format-guidelines.md).

---

## Progressive Disclosure Reference Index

When executing specific drafting or editing tasks, load the relevant reference module:

- [`references/voice-profile.md`](references/voice-profile.md): Intellectual foundations (Newton, Boyle, Le Chatelier, Emerson, Kipling, Bunyan), authorial traits, paragraph discipline, and strict style boundaries.
- [`references/reasoning-method.md`](references/reasoning-method.md): Forward scientific exposition, the 5-step bidirectional reverse-reasoning cycle, the 11 technical reasoning dimensions, and implementation domain rules.
- [`references/format-guidelines.md`](references/format-guidelines.md): Specialized adaptations for short technical copy, long deep-dives, reproducible workshops, essays, and voice-preserving draft editing.
- [`references/editorial-checklist.md`](references/editorial-checklist.md): Pre-publication quality gates and acceptance criteria.
- [`evals/prompts.md`](evals/prompts.md): Benchmark test prompts and negative control evaluations.
- [`examples/README.md`](examples/README.md): Calibration guidance using author-approved writing samples.

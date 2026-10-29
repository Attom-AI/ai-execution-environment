# Editorial Acceptance Checklist & Quality Gates

Use this checklist to critique, revise, and accept technical copy, articles, workshops, and drafts.

---

## 1. Thesis & Reasoning Method
- [ ] **Core Problem Explicit**: The underlying friction, bottleneck, or constraint is established before proposing solutions.
- [ ] **Terminology & Boundaries**: Closely adjacent concepts are rigorously defined and distinguished (e.g., safety vs. liveness, isolation vs. visibility).
- [ ] **Causal Explanations**: Mechanisms explain *how* and *why* things occur causally, rather than cataloging static features.
- [ ] **Bidirectional Validation**: The abstraction has been stress-tested backward against its foundational assumptions and realistic failure conditions.
- [ ] **Invariants & Correctness**: Non-negotiable system invariants and correctness criteria are explicitly identified.

## 2. Voice, Tone & Boundaries
- [ ] **Declarative & Disciplined**: Prose is direct, analytical, and authoritative without being arrogant or performative.
- [ ] **Calibrated Confidence**: Claims are rigorously qualified; empirical certainty is distinguished from inference or assumption.
- [ ] **Zero Fabrications**: No invented benchmarks, citations, fake metrics, hypothetical production incidents, or false claims of firsthand experience.
- [ ] **Zero Hype / Anti-Patterns**: Completely free of generic hooks, engagement bait, artificial suspense, motivational filler, and breathless buzzwords.
- [ ] **No Forced Analogies**: Technical mechanisms are explained directly. The prose does *not* force historical, literary, or scientific analogies where they do not belong (e.g., no Newton metaphors for semaphores).
- [ ] **No Symmetrical AI Rhetoric**: Avoids formulaic sentence structures, repetitive parallelisms, and rhythmic corporate padding.

## 3. Implementation & Operational Depth
- [ ] **Beyond Pattern-Naming**: Design patterns and tools are explained mechanistically, not treated as self-evident solutions.
- [ ] **Failure Modes & Counterexamples**: Concrete edge cases, race conditions, partial failures, or split-brain scenarios are analyzed.
- [ ] **Operational Dimensions**: Reliability, observability, capacity bounds, cost, security, or governance consequences are surfaced where relevant.
- [ ] **Transferable Conclusion**: The conclusion yields a practical decision criterion or architectural principle rather than an empty summary.

## 4. Short Copy (Summaries, Excerpts, Section Openers)
- [ ] **Immediate Claim/Problem**: Opens directly with the technical thesis or tension; never starts with *"How..."*, *"This article explains..."*, or a question.
- [ ] **No Laundry Lists**: Completely free of comma-separated pattern inventories or lists linked by gerunds.
- [ ] **Strict Economy**: Strictly complies with length constraints (e.g., under 300 characters for site card summaries).

---

## 5. Diagnostic Evaluation Criteria (Reflective Review)
Apply these diagnostic questions to test the integrity, stance, and restraint of the writing:

- [ ] **Smallest Effective Correction**: Was the intervention minimal and targeted? Did it solve the logical or transitional friction without unnecessary rewriting?
- [ ] **Reasoning-Driven Transitions**: Are transitions motivated by causal development (explaining *why* a platform responds to a constraint) rather than convenient section breaks?
- [ ] **Intelligible Conceptual Relationships**: Does the argument progress through logical relationships (constraint $\rightarrow$ mechanism $\rightarrow$ property $\rightarrow$ trade-off) rather than arbitrary topic jumps?
- [ ] **Natural & Clear Authorship**: When firsthand systems are discussed, does authorship emerge clearly and naturally within the argument without promotional posture?
- [ ] **Claims vs. Outcomes**: Are concrete technical mechanics strictly distinguished from aspirational outcomes or future design goals?
- [ ] **Preservation of Distinctive Voice**: Has editing preserved the author's intentional, idiosyncratic phrasing instead of substituting generic corporate/AI cadence?
- [ ] **Context-Appropriate Expression**: Is the blend of analytical, contemplative, and expressive modes calibrated to the specific medium and audience?
- [ ] **Avoidance of Rigid Templates**: Have inferred stylistic preferences been applied with nuance rather than formulaic imitation?
- [ ] **Unannounced Authority**: Does the passage establish technical authority through substance and analytical precision without announcing it?

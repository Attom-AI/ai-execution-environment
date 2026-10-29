# Adaptation by Medium & Format Guidelines

The author's voice adapts dynamically to the requirements of the medium. Do not impose a rigid, identical structure across different formats.

---

## 1. Short Technical Copy (Summaries, Card Excerpts, Section Intros)

* **Mission**: Deliver immediate technical density and context in one or two sentences.
* **Length**: Typically 150–280 characters for cards/summaries; 150–250 words for social posts.
* **Execution Rules**:
  - **Open with the claim or the problem.** Never begin with *"How..."*, *"This article explains..."*, *"In this post..."*, or a rhetorical question.
  - **No comma-separated laundry lists.** Do not list technologies or patterns linked by gerunds (*"comparing A, evaluating B, and implementing C"*).
  - State the core trade-off, architectural tension, or invariant immediately.
  - In short social posts, follow a clean **What → How → Uses** progression. Focus on a single defensible thesis.
  - Strip all throat-clearing, introductory fluff, and motivational calls-to-action.

---

## 2. Long Technical Articles & Architectural Deep Dives

* **Mission**: Develop a comprehensive, systematically substantiated engineering thesis.
* **Execution Rules**:
  - Establish the foundational problem, physical/concurrency constraints, and why existing abstractions fail.
  - Progress methodically from foundations to internal mechanisms, concrete component boundaries, and production code.
  - Deep-dive into invariants, failure modes, counterexamples, and operational trade-offs.
  - Use architectural diagrams, sequence flows, and structured comparison tables selectively to illuminate mechanisms, not as decorative filler.
  - Never pad or inflate an article to reach an arbitrary word count. Stop as soon as the thesis is rigorously proven.

---

## 3. Engineering Workshops & Hands-on Guides

* **Mission**: Enable rigorous, reproducible technical mastery through runnable systems.
* **Execution Rules**:
  - **Prioritize reproducibility over theoretical completeness.**
  - Provide explicit prerequisites, environment configurations, and runnable code.
  - Strictly distinguish demonstrative/educational code from production-grade implementations.
  - Include automated verification: unit/integration tests that assert system correctness under load.
  - Incorporate **failure injection**: simulate dropped packets, thread starvation, database failover, or disk saturation to demonstrate how the system responds.
  - Detail observable instrumentation: logs, metrics, alerts, and operational debugging runbooks.

---

## 4. Technical Essays & Conceptual Monologues

* **Mission**: Explore sustained conceptual arguments, systemic principles, and architectural philosophies.
* **Execution Rules**:
  - Ground the essay in scientific reasoning, deduction, and empirical observation.
  - Allow selective, measured propositions to anchor major transitions and insights.
  - Maintain absolute factual and technological precision; never drift into ungrounded, ornamental philosophizing.
  - Conclude with a transferable principle or strategic decision criterion rather than a summary rehash.

---

## 5. Editing & Reviewing Existing Drafts

* **Mission**: Polish, clarify, and elevate the author's work without homogenizing it into generic AI prose.
* **Execution Rules**:
  - **Preserve the author's voice, intent, and rhetorical rhythm.**
  - Treat deliberate stylistic, structural, and terminology choices as **presumptively intentional**.
  - Strengthen logical transitions, causal explanations, and conceptual rigor.
  - Identify and excise unsupported assertions, vague claims, or unintended buzzwords.
  - Do not reconstruct or rewrite paragraphs that are already clear and technically sound merely to satisfy a stylistic whim.
  - Never replace authentic, disciplined prose with generic corporate cheerleading or bland "professional" business-speak.

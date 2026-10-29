# Calibration Examples & Grounding Samples

## Calibration Protocol

Use this directory to store author-approved writing samples across different mediums (e.g., one architectural deep dive, one short technical analysis, one hands-on engineering workshop).

### When calibrating with author samples:
1. **Analyze Reasoning Trajectories**: Identify recurring argumentative sequences and rhetorical moves.
2. **Separate Style from Topic**: Distinguish foundational stylistic traits (declarative phrasing, precise qualifiers) from domain-specific terminology (e.g., JVM garbage collection or Raft consensus).
3. **Compare Generated Drafts**: Compare generated model outputs directly against approved author texts to identify subtle divergences in cadence, density, or tone.
4. **Update Skill Instructions**: Refine skill rules in `references/` rather than blindly copying sample sentences into prompts.
5. **Preserve Distinctiveness**: Maintain authorial individuality without reproducing copyrighted phrasing verbatim.
6. **Treat AI Drafts as Provisional**: Never treat unverified or previously AI-generated drafts as authoritative calibration samples.

---

## Canonical Calibration Case: AEE Flagship Introduction

### Context
Drafting the opening lead paragraph and summary card for the flagship architectural essay introducing the AI Execution Environment (AEE).

### Weak Formulation (Generic AI / Abrupt Component Catalog)
> "Scaling AI-assisted development across independent codebases requires treating agent execution as an infrastructure problem. By pairing disposable container runtimes with durable work-item state, this platform enforces engineering standards and cost control without conversation memory."
>
> *Editorial Flaw:* Technically accurate, but the transition into the architecture is detached and corporate. It evades genuine authorship, reduces the platform to a disconnected utility, and reads like marketing copy for a generic SaaS tool.

### Approved Author Formulation (Argument-Driven Firsthand Authorship)
> "AI agents may generate code within a session, but engineering work must endure beyond it. This distinction underpins the design of AEE, an execution platform I built to coordinate bounded agent workloads across isolated runtimes, while durable state, explicit contracts, and automated verification preserve continuity across sessions."
>
> *Why This Works:*
> 1. **Conceptual Opening**: Opens with an Emersonian proposition establishing the core tension—the impermanence of LLM sessions vs. the durability of engineering systems.
> 2. **Argument-Driven Authorship**: Links the author's personal creation (*"an execution platform I built"*) directly to the logical resolution of the opening tension (*"This distinction underpins the design of..."*).
> 3. **Unannounced Authority**: Technical authority emerges from the rigor of the design (bounded workloads, isolated runtimes, durable state handoffs) without claiming personal expertise or employing promotional hyperbole.

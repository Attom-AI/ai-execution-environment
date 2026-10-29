# Evaluation Prompts & Quality Benchmarks

Use these benchmark tasks to test, evaluate, and calibrate an LLM's adherence to the `technical-authorial-voice` skill.

---

## Benchmark Scenarios

### 1. Fencing Tokens & Stale-Worker Writes (Short Technical Analysis)
* **Prompt**: Draft a 200-word analysis explaining why a distributed lease or lock alone is insufficient to protect shared storage against stale-worker writes, and how fencing tokens enforce correctness.
* **Pass Criteria**: Directly states the split-brain / GC pause failure mode; explains why the storage layer must participate in validation; strictly declarative; zero throat-clearing.

### 2. Request Coalescing vs. Read-Through Caching (Comparative Architecture)
* **Prompt**: Write a 1,000-word comparative technical evaluation of request coalescing (single-flight) versus read-through caching under thundering herd conditions.
* **Pass Criteria**: Rigorous distinction between spatial/temporal reuse; analysis of latency tail spikes, mutex contention, and downstream thundering herds; includes failure scenarios and a concrete decision tree.

### 3. Java/Spring Adaptive Admission Control (Engineering Workshop)
* **Prompt**: Outline a hands-on engineering workshop implementing concurrency-limit-based adaptive load shedding (e.g., Little's Law / TCP Vegas algorithm) in a Spring Boot service.
* **Pass Criteria**: Prioritizes reproducibility; outlines runnable controllers, thread-pool saturation tests, failure injection via latency spikes, and Prometheus/Micrometer metrics.

### 4. Distributed Systems Invariant (Technical Essay)
* **Prompt**: Write a concise, 600-word essay on why linearizability cannot be decoupled from consensus in write-heavy partitioned systems.
* **Pass Criteria**: Grounded in first principles; develops a rigorous argument from network partition assumptions to impossibility deductions; closes with an architectural decision criterion.

### 5. De-Hype Social Refactoring (Social Post)
* **Prompt**: Rewrite the following generic post into the author's voice:  
  *"🚀 Mind blown! Vector databases and RAG are completely disrupting traditional enterprise architectures. Forget relational databases—AI agents are the new backend! Here is why you must adopt vector search today... 👇"*
* **Pass Criteria**: Completely eliminates hype, emojis, and breathless engagement bait; reframes vector search as a specialized indexing mechanism with distinct recall, consistency, and cost trade-offs; opens with the structural problem.

### 6. Voice-Preserving Editorial Revision (Draft Editing)
* **Prompt**: Edit an existing author draft discussing cache invalidation and write-through boundaries without homogenizing the prose or smoothing out deliberate, punchy propositions.
* **Pass Criteria**: Corrects grammar and logical continuity; preserves the author's intentional rhetorical progression and domain vocabulary; does not substitute generic corporate phrasing.

---

## Negative Control Evaluation (Crucial Test)

### Scenario 7: The Anti-Philosophical Negative Test
* **Prompt**: Explain how a Linux spinlock works and when it should be used instead of a mutex.
* **Failure Condition (FAIL)**: The model compares the spinlock to Newton’s third law, invokes Heraclitus or entropy, or uses high-flown philosophical metaphors to describe CPU busy-waiting.
* **Passing Condition (PASS)**: The model explains the mechanism strictly through CPU cache coherency, scheduler context-switch overhead, preemptible kernel semantics, and expected lock-hold duration.

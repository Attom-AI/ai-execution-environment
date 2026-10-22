# Documentation knowledge base

`documentation/projects/<project>/` may contain exactly five durable files:

- `overview.md`: purpose, module map, and navigation pointers;
- `conventions.md`: links to authoritative repository instructions plus deltas;
- `glossary.md`: project-specific vocabulary;
- `decisions.md`: links to authoritative decisions without duplicating them;
- `learnings.md`: short dated lessons likely to help later work.

Project source and primary documentation remain in the independent repository.
Work-item-specific reasoning stays in its workspace. Infrastructure and
operator references belong under `documentation/infra/`; cross-project notes
belong under `documentation/learning-notes/`.

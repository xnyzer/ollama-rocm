# AI Disclosure

This project is developed using **Claude Code** (by Anthropic) as the
primary development tool. In the interest of transparency, this document
describes how AI is involved in the development process.

## Roles

**Human (Project Owner):** Defines requirements, makes architectural
decisions, manages the project, tests functionality on the actual hardware,
and ensures the end result meets expectations. Does not write or review code
at a technical level.

**AI (Claude Code):** Writes all scripts and documentation in this
repository, proposes technical solutions, diagnoses build/runtime problems,
and maintains the deploy pipeline. Operates under the direction and approval
of the project owner.

## How AI is used

- **All scripts and documentation** in this repository are written by Claude
  Code.
- **Architecture and technical decisions** (build toolchain, deploy strategy,
  license boundaries, ZIP layout) are proposed by the AI and confirmed or
  adjusted by the project owner.
- **Planning and documentation** are created collaboratively.
- **Testing** is performed by the AI (build verification, deploy script
  dry-runs, `ollama ps` checks after deploy) and the project owner
  (functional verification on the live system, inference quality on real
  models).

## Transparency

- Every commit includes a `Co-Authored-By: Claude` trailer.
- The project owner steers direction, priorities, and acceptance criteria.
- The AI does not push to GitHub, publish releases, or make other
  irreversible changes without explicit approval.

## Why this matters

This project demonstrates a collaboration model where a non-developer drives
a software project through clear requirements, critical questioning, and
iterative feedback — with AI handling the technical implementation. The
quality of the result depends on both sides: precise requirements and
competent execution.

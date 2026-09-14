# 068 — Agent State Providers: Plan

| | |
| --- | --- |
| **Status** | Planned — migration proposal awaiting review; shared decisions and Codex provider already released |
| **Anchor date** | 2026-09-14 |
| **Baseline** | `e54b1e19`; #800 shipped in v2026.9.12 |
| **Related** | [030 detection history](../030-agent-status-detection/000-plan.md), [064 completion signals](../064-agent-completion-signals/000-plan.md) |

## Background

Terminal screens describe what is displayed, which can differ from current work.
Runtime scroll viewers, retained output, and background children expose this gap.
#800 introduced shared decisions and optional lifecycle evidence. Its implementation
history remains in 064; this chapter is the current reference for state providers
and the plan for extending them to other runtimes.

## Goals

- Preserve one decision policy with runtime-specific evidence acquisition.
- Prefer scoped lifecycle or native state evidence where its contract is verified.
- Keep screen fallback for unsupported versions, missing evidence, and ambiguity.
- Preserve per-pane identity, outstanding work, and existing readiness contracts.
- Maintain one living document per agent, with explicit implementation status,
  evidence boundaries, failure behavior, and remaining acceptance gates.

## Document map

| Document | Role |
| --- | --- |
| [architecture.md](architecture.md) | Released shared architecture, arbitration, and extension invariants |
| [codex.md](codex.md) | Released provider, acquisition/decoding contract, and known limits |
| [claude.md](claude.md) | Interactive spike findings and proposed implementation slices |

Add future agents as sibling living documents. Each must distinguish observed
runtime behavior from implemented Prowl behavior. Update these references with
accepted contract changes; retain numbered amendments for implementation decisions.
This chapter does not supersede 030's screen history or 064's trusted completion
and delivery contracts.

## Approach and review gate

The proposed next adapter combines Claude's process-scoped native status file with
selected-session JSONL evidence. The spike found cancellation without a closing
transcript record and two processes with different states sharing one transcript.
These cases rule out copying a JSONL-only turn model unchanged.

Review the evidence and stages in [claude.md](claude.md) before implementation:

1. Close process-identity, compatibility, and assigned-child contract gaps.
2. Implement bounded native acquisition and selected JSONL decoding.
3. Extend the shared decision model and coordinator with explicit native facts.
4. Verify native pane behavior, fallback, and readiness before release.

This documentation PR does not implement or approve those stages. Record each
accepted implementation slice as a numbered amendment. Write `001-action.md` when
this migration plan is completed or superseded; do not mark the migration complete
when only its documentation has shipped.

## Alternatives and decisions

- **Screen only:** remains the fallback, but cannot resolve completion while a
  runtime displays an unchanged history view.
- **JSONL only for every runtime:** rejected as the proposed Claude approach by
  the cancellation and concurrent-resume evidence. Runtime contracts differ.
- **Native status plus JSONL:** recommended for Claude, subject to schema,
  process-generation, ownership, and child-work acceptance gates.
- **Mandatory hooks:** outside this migration's setup-free detection scope.
  Existing trusted hooks and delivery receipts retain their separate contracts.

## Amendments

None. Production implementation awaits review.

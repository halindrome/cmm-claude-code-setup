# ccs-vbw2

## Goals

A hook-based enforcement layer that makes Claude Code use codebase-memory-mcp (CMM) as its core code-intelligence tool, with Context Mode and VBW as optional, auto-detected add-ons. For Claude Code users who install it via setup.sh.

This milestone: update the stack to work well with VBW 2 (new conventions, e.g. `.vbw/` instead of `.vbw-planning/`).

## Non-goals

## Constraints

- VBW 2 reference is the installed plugin (~/.config/claude-code/plugins/cache/vbw-marketplace/vbw/2.1.18); no fork or sibling checkout.

## Requirements

<!-- One requirement per line: an id, how it is proved, and a user-observable
     statement. [auto] = a check can prove it; [human] = only a person can judge it.
- R1 [auto] A visitor can sign up with an email address
- R2 [human] The landing page feels trustworthy
-->

## Commands

<!-- The project's own commands, which every proof runs once you approve them.
     One per line: a name, then the command as words, or as a JSON array when
     an argument contains spaces. Edit or delete lines, then vbw spec sync.
- test: npm test
- build: ["make", "release build"]
-->
- test: make test

## Clean copy

<!-- Git-ignored paths the proof's clean copy leaves out, such as a huge data
     folder or caches. One per line, relative to the project root; the rest of
     the ignored environment is still copied in. Edit lines, then vbw spec sync.
- data/
-->

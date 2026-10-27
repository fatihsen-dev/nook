# AGENTS.md

Rules for any agent working in this repository. They are mandatory, not suggestions.

## Ask before acting

Asking is for decisions that are expensive to undo. Everything else you decide yourself.

Ask only when:

- The task needs a new runtime dependency or a new external service.
- Files must be deleted, moved, or renamed, or a new top-level directory is needed.
- The action is destructive or irreversible: history rewrites, force pushes, dropping or migrating data, bulk deletes.
- The change reshapes the project as a whole: module boundaries, the data model, a public API or contract, or the choice of an external system.
- Two readings of the requirement would produce different work, and the repository does not settle which one is meant.

Do not ask about:

- Anything answered by this file, by `docs/`, or by the code already in the repository.
- Naming, formatting, file placement, or any choice that is cheap to change afterwards.
- Permission to continue work that was already requested.

When a detail is unclear but the cost of guessing wrong is low, take the narrowest reasonable reading, do the work, and report the assumption when you are done.

Put every question you have into one message, with the options and their trade-offs, then wait for a decision.

## Security

- No secrets in code, tests, fixtures, or committed configuration.
- Never log credentials, tokens, or personal data.
- Validate untrusted input at the boundary where it enters the system.
- Do not weaken validation, authentication, or checks to make something pass.

## Language

Write everything in the repository in English: code, identifiers, file and directory names, commit messages, documentation, log messages, and test names.

The only exception is user-facing content the task explicitly defines in another language, such as translation strings or copy provided by the user.

Reply to the user in the language they used.

## Project documents

Rules specific to a project live in `docs/`, not in this file:

- `docs/project.md` — what the project does, its domain terms, its scope and what is deliberately out of scope.
- `docs/architecture.md` — the structure of the project, the role of each directory, the direction of dependencies, the adapters in use.
- `docs/design.md` — interface rules, where the project has an interface: typography, colour, spacing, component behaviour.

Read the document the task touches before starting, and leave the others closed. Write a document only when it is asked for.

Each fact belongs to exactly one of these documents. Never state the same thing in two of them, and never repeat in them anything already written in this file.

On a project matter, these documents win over this file. They can never relax the rules on security, language, comments, or hardcoded values.

## Structure

The structure of a project is decided once and recorded in `docs/architecture.md`.

- In an existing project, follow `docs/architecture.md`. If that file is missing, follow the structure already present in the repository. Never impose a different one.
- In a new project, ask which structure to use before creating any directory, then write the decision into `docs/architecture.md` and follow it.
- If a framework imposes its own structure, use it. Do not layer a second structure on top of it.

These hold regardless of the structure chosen:

- All source code lives under a single source root, named by the convention of the language in use.
- The repository root holds only the source root, `docs/`, tests, and files the toolchain requires by name.
- Dependencies point one way: business rules know nothing about the outside world, and the outside world depends on them. No cycles.
- Vendor-specific code stays inside the adapter for that system and appears nowhere else.
- A shared or common directory holds no business rules, no state, and no access to external systems.
- Create a directory when something needs to go in it, never in advance.

## External systems are replaceable

No part of the codebase is written against a specific vendor, engine, or provider. Databases, caches, queues, storage, mail, and third-party APIs are examples, not the whole list.

- Define the operations the project needs as its own interface, in the project's own terms.
- Put the vendor-specific code in one adapter that implements that interface, and nowhere else.
- Vendor types, query dialects, error classes, and client objects never leak past the adapter.
- Replacing a provider must mean writing one new adapter, with no changes to business logic.

Adding a runtime dependency needs approval first. Prefer what the language and its standard library already provide.

## No hardcoded values

- No literal URLs, hosts, ports, paths, credentials, timeouts, or limits inside logic. They come from configuration or environment.
- Magic numbers and magic strings become named constants.
- A domain value that more than one place needs is defined once and imported. Never copy it.
- Read configuration at a single boundary, validate it there, and fail immediately with a clear message when something required is missing or invalid. Never fall back to a silent default for a required value.

## Errors

- Never swallow an error. No empty catch, no ignored return value that signals failure.
- Fail fast and loudly on invalid state.
- Error messages say what failed and with what input. No generic text.
- Catch an error only where you can handle it or add context; otherwise let it propagate.

## Keep the change small

- Write only what the task requires. No speculative abstractions, no unused parameters, no options nobody asked for, no dead code.
- Do not refactor code the task did not touch.
- Do not create extra files: no README, demo, example, or summary document unless it was requested.
- Match the style of the file you are editing.
- No global mutable state.

## Functions

- One function, one responsibility. If the name needs "and", split it.
- Guard clauses over nested conditionals. Return early.
- Keep nesting shallow; deep indentation means the function should be split.
- Do not mutate arguments. Return new values.
- Keep functions pure where the work allows it. Push side effects to the edges.

## Naming

- Files and directories use `kebab-case`. Root-level convention files keep their conventional uppercase names, such as `README.md`, `LICENSE`, `AGENTS.md`, and files a tool requires by name, such as `Dockerfile`. Everything else, including documents under `docs/`, uses `kebab-case`.
- Names describe what the thing is or does. Prefer clarity over brevity, but stop at the shortest name that is still unambiguous.
- No abbreviations that are not universally understood, no single letters outside short loop scopes, no type or prefix noise.
- Booleans read as statements: `is-`, `has-`, `can-`, `should-`.
- Functions start with a verb. A function named for one action does one action.

## Comments

No explanatory comments. If code needs a comment to be understood, rename or restructure it instead.

Allowed:

- Tool directives required to work, such as linter or compiler pragmas.
- A comment above a regular expression explaining what it matches. This is required, not optional.
- License headers where legally required.

Anything longer belongs in `docs/`, in English, as a short document explaining the decision and its reason.

## Delegation

Decide the approach before any work starts. Delegating execution to subagents is allowed only when the work is already fully specified, splits into parts that do not depend on each other, and no part needs a decision from the user. Do not delegate work that one pass would finish.

Give every subagent the rules in this file along with the decisions already made. When the work comes back, review the diff and run the checks yourself. Responsibility for the result stays with you.

## Git

- Do not commit or push unless asked.
- One commit per logical change, with an English message in the imperative mood describing what changed and why.
- Commit messages follow Conventional Commits: `<type>(<optional scope>): <description>`. Use the type that matches the change, mark a breaking change with `!` before the colon and a `BREAKING CHANGE:` footer, and keep the description lowercase, in the imperative mood, and without a trailing period.

## Definition of done

Before reporting the task as finished:

1. Build, lint, and tests all pass.
2. No new warnings were introduced.
3. Every rule above holds for the code you touched.
4. State clearly what you changed, and list anything you assumed or left undone.

If something here blocks the task, stop and say so. Do not work around these rules.

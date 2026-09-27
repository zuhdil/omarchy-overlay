---
name: git-conventions
description: Commit message style and git hygiene for this user's repositories. Use when writing a git commit message, amending one, creating a tag, moving or renaming tracked files, or opening a pull request. Triggers - commit, commit message, amend, git mv, rename a file, tag, PR description, "what should the commit say".
---

# Git conventions

These are style rules. The non-negotiables — no AI attribution anywhere, GPG
signing, writing the message through `.tmp-commit-msg` — live in `~/.claude/CLAUDE.md`
and apply whether or not this skill loaded. Nothing here relaxes them.

## Length

Keep commit messages to 100 words at most, title included. Count them before
committing; this limit is exceeded far more often than it looks.

Name the trade-off and the reason it was chosen. Leave out the narrative, the
reproduction steps and the supporting evidence. If a decision needs more than
that to justify, it belongs in the code as a comment or in the project's docs,
where it will be read again.

## Titles

Write commit titles as concise, present-tense sentences describing what the
commit does:

    Update `.gitignore` to ignore runtime data and MCP tooling
    Add mascot source PNGs and generation guide

Do not use semantic commit prefixes — no `feat:`, `fix:`, `chore:` and so on.

## Body

Explain any non-obvious trade-off made in the design or implementation. A
commit that only restates its own diff is not worth the words.

Wrap prose to match git commit conventions, including the title. Do not wrap
code.

## Markup

Refer to types and very short snippets in backticks:

> the `resume` hook runs before `filesystems`

A full line of code, or more than one line, goes in an indented block:

    sudo sed -i "s|^$k=.*|$k=$v|" "$up"

## Moving files

Use `git mv` for any file already tracked by git. A plain `mv` followed by
`git add` records the same result, but only `git mv` keeps the intent legible
while the change is still staged.

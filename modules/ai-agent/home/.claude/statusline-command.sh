#!/usr/bin/env bash
# Status line for Claude Code, mirroring the Starship prompt configuration.
# Reads JSON from stdin and produces a one-line status string.

# --- Read Claude's JSON, once ---
#
# One jq pass rather than one per field. This runs on every status line
# refresh, and starting an interpreter costs far more than the parse: going
# from four calls to one took a render from 29 ms to 18 ms, the rest being the
# four git invocations below.
#
# session_pct is the subscription quota shown by /usage, distinct from the
# context window. rate_limits only appears for Claude.ai Pro/Max subscribers
# after the first API response, so it may legitimately be absent.
#
# @tsv rather than raw newlines, because it escapes any tab or newline inside a
# value — a directory may legally contain either, and a raw split would then
# shift every later field into the wrong variable.
#
# `//` in jq only substitutes for null and false, so a genuine 0 percent still
# comes through as 0 rather than falling back to the empty string.
IFS=$'\t' read -r cwd model used_pct session_pct < <(
  jq -r '[
    (.workspace.current_dir // .cwd // ""),
    (.model.display_name // ""),
    (.context_window.used_percentage // ""),
    (.rate_limits.five_hour.used_percentage // "")
  ] | @tsv'
)

# --- Directory ---
# Styled like the Starship [directory] module.
home="$HOME"
# Replace $HOME prefix with ~ for brevity, matching typical shell display.
# The tilde is escaped: bash tilde-expands an unquoted ~ in the replacement, so
# ${cwd/#$home/~} substitutes $HOME with $HOME and abbreviates nothing.
display_dir="${cwd/#$home/\~}"

# --- Git branch ---
# Asked of git in the cwd. Claude's JSON carries no branch, so there is nothing
# cheaper to consult first.
branch=""
# `rev-parse --is-inside-work-tree` exits 0 even in a bare repo (it just prints
# "false"), so we must test the output rather than the exit code. Otherwise the
# bare-repo root of a worktree layout would falsely report a branch and a huge
# staged count (empty bare index diffed against HEAD's full tree).
if [ -n "$cwd" ] && [ "$(git -C "$cwd" --no-optional-locks rev-parse --is-inside-work-tree 2>/dev/null)" = "true" ]; then
  branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
fi

# --- Git status indicators (ahead/behind/staged/dirty) ---
git_status=""
if [ -n "$branch" ]; then
  staged=$(git -C "$cwd" --no-optional-locks diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
  # Second column only. Excluding every line whose FIRST column was a change
  # also excluded MM and AM — staged, then edited again — so a file with
  # unstaged work showed +1 and no !. Untracked (??) still counts as dirty.
  dirty=$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null | grep -c '^.[^ ]')
  ahead=$(git -C "$cwd" --no-optional-locks rev-list --count @{u}..HEAD 2>/dev/null || echo 0)
  behind=$(git -C "$cwd" --no-optional-locks rev-list --count HEAD..@{u} 2>/dev/null || echo 0)

  [ "$staged" -gt 0 ] 2>/dev/null && git_status="${git_status}+${staged}"
  [ "$dirty" -gt 0 ] 2>/dev/null && git_status="${git_status}!"
  if [ "${ahead:-0}" -gt 0 ] && [ "${behind:-0}" -gt 0 ]; then
    git_status="${git_status}⇕⇡${ahead}⇣${behind}"
  elif [ "${ahead:-0}" -gt 0 ]; then
    git_status="${git_status}⇡${ahead}"
  elif [ "${behind:-0}" -gt 0 ]; then
    git_status="${git_status}⇣${behind}"
  fi
fi

# --- Assemble the line ---
# Format: <dir> <branch> <git_status>  <model>  ctx:<n>%  sess:<n>%
# Every field after the directory is omitted when its source is absent.

printf '\033[34m%s\033[0m' "$display_dir"

if [ -n "$branch" ]; then
  printf ' \033[35m%s\033[0m' "$branch"
fi

if [ -n "$git_status" ]; then
  printf ' \033[31m%s\033[0m' "$git_status"
fi

if [ -n "$model" ]; then
  printf '  \033[2m%s\033[0m' "$model"
fi

if [ -n "$used_pct" ]; then
  printf '  \033[2mctx:%s%%\033[0m' "$(printf '%.0f' "$used_pct")"
fi

if [ -n "$session_pct" ]; then
  printf '  \033[2msess:%s%%\033[0m' "$(printf '%.0f' "$session_pct")"
fi

printf '\n'

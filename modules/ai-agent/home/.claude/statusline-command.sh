#!/usr/bin/env bash
# Status line for Claude Code, mirroring the Starship prompt configuration.
# Reads JSON from stdin and produces a one-line status string.

input=$(cat)

# --- Directory ---
# Use the cwd from Claude's context, styled like the Starship [directory] module.
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
home="$HOME"
# Replace $HOME prefix with ~ for brevity, matching typical shell display.
# The tilde is escaped: bash tilde-expands an unquoted ~ in the replacement, so
# ${cwd/#$home/~} substitutes $HOME with $HOME and abbreviates nothing.
display_dir="${cwd/#$home/\~}"

# --- Git branch ---
# Read from workspace repo info; fall back to running git in the cwd.
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
  dirty=$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null | grep -v '^[MADRCU][MADRCU ] ' | wc -l | tr -d ' ')
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

# --- Model ---
model=$(echo "$input" | jq -r '.model.display_name // empty')

# --- Context usage ---
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# --- Session usage (5-hour rate-limit window) ---
# This is the subscription quota shown by /usage, distinct from the context
# window above. The rate_limits object only appears for Claude.ai Pro/Max
# subscribers after the first API response, so it may legitimately be empty.
session_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')

# --- Assemble the line ---
# Format: <dir> <branch> <git_status>  |  <model>  ctx:<used>%
parts=""

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

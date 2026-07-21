#!/bin/bash
# PreToolUse guard: upstream (palmier-io) accepts issues, not PRs — block any command that could
# open or reopen a PR there. Fork PRs must name maxtongwang/ explicitly.
input=$(cat)
cmd=$(echo "$input" | python3 -c "import json,sys; print(json.load(sys.stdin).get('tool_input',{}).get('command',''))" 2>/dev/null)
case "$cmd" in
  *"pr create"*|*"pr reopen"*|*api*pulls*POST*|*api*-X*POST*pulls*)
    if echo "$cmd" | grep -q "palmier-io"; then
      echo "BLOCKED: upstream palmier-io accepts issues only, never PRs (see AGENTS.md fork posture)." >&2
      exit 2
    fi
    if ! echo "$cmd" | grep -q "maxtongwang/"; then
      echo "BLOCKED: gh pr commands here must target the fork explicitly (--repo maxtongwang/palmier-pro) — the bare default could resolve to upstream." >&2
      exit 2
    fi
    ;;
esac
exit 0

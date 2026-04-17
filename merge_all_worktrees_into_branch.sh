#!/usr/bin/env bash
# 将仓库内所有本地 worktree 当前指向的提交（分支 tip 或 detached HEAD）
# 依次合并到指定分支。未提交的本地修改不会进入合并结果，请先在各 worktree 内提交或 stash。
#
# 用法:
#   ./merge_all_worktrees_into_branch.sh              # 合并到当前目录所在分支
#   ./merge_all_worktrees_into_branch.sh my/feature   # 合并到 my/feature
#   DRY_RUN=1 ./merge_all_worktrees_into_branch.sh    # 只打印将要执行的 merge，不执行
#
set -euo pipefail

dry_run="${DRY_RUN:-0}"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "错误: 当前不在 git 仓库内。" >&2
  exit 1
fi

repo_root="$(git rev-parse --show-toplevel)"
# 在 cd 到主目录之前读取当前所在 worktree 的分支，避免误用主 worktree 的 HEAD。
if [[ -n "${1:-}" ]]; then
  target_branch="$1"
else
  target_branch="$(git branch --show-current || true)"
fi
cd "$repo_root"

if [[ -z "$target_branch" ]]; then
  echo "错误: 无法确定目标分支。请在已检出分支的目录运行，或传入分支名: $0 <branch>" >&2
  exit 1
fi

declare -a wt_path wt_head wt_branch_ref wt_detached

path="" head="" branch_ref="" detached="0"

flush_block() {
  if [[ -z "$path" ]]; then
    return
  fi
  wt_path+=("$path")
  wt_head+=("$head")
  wt_branch_ref+=("$branch_ref")
  wt_detached+=("$detached")
}

while IFS= read -r line || [[ -n "${line}" ]]; do
  if [[ -z "$line" ]]; then
    flush_block
    path=""
    head=""
    branch_ref=""
    detached="0"
    continue
  fi
  key="${line%% *}"
  rest="${line#"$key"}"
  rest="${rest# }"
  case "$key" in
    worktree) path="$rest" ;;
    HEAD) head="$rest"; detached="0" ;;
    branch) branch_ref="$rest" ;;
    detached) detached="1" ;;
  esac
done < <(git -C "$repo_root" worktree list --porcelain)

flush_block

merge_base=""
for i in "${!wt_path[@]}"; do
  if [[ "${wt_detached[$i]}" == "1" ]]; then
    continue
  fi
  br="${wt_branch_ref[$i]:-}"
  if [[ -n "$br" ]]; then
    short="$(git rev-parse --abbrev-ref "$br" 2>/dev/null || true)"
    if [[ "$short" == "$target_branch" ]]; then
      merge_base="${wt_path[$i]}"
      break
    fi
  fi
done

if [[ -z "$merge_base" ]]; then
  echo "错误: 没有任何 worktree 当前检出目标分支「${target_branch}」。" >&2
  echo "请先在某个 worktree 中执行: git checkout ${target_branch}" >&2
  exit 1
fi

sources=()
labels=()
seen_keys=()

key_seen() {
  local needle="$1"
  local k
  if [[ "${#seen_keys[@]}" -eq 0 ]]; then
    return 1
  fi
  for k in "${seen_keys[@]}"; do
    [[ "$k" == "$needle" ]] && return 0
  done
  return 1
}

for i in "${!wt_path[@]}"; do
  p="${wt_path[$i]}"
  h="${wt_head[$i]}"
  br="${wt_branch_ref[$i]:-}"
  det="${wt_detached[$i]}"

  if [[ "$det" == "1" || -z "$br" ]]; then
    src="$h"
    label="(detached) $h @ $p"
    key="detached:$h"
  else
    short="$(git rev-parse --abbrev-ref "$br" 2>/dev/null || true)"
    if [[ "$short" == "$target_branch" ]]; then
      continue
    fi
    src="$short"
    label="$short @ $p"
    key="branch:$short"
  fi

  if [[ -z "$src" ]]; then
    continue
  fi
  if key_seen "$key"; then
    continue
  fi
  seen_keys+=("$key")
  sources+=("$src")
  labels+=("$label")
done

if [[ "${#sources[@]}" -eq 0 ]]; then
  echo "没有其它 worktree 分支需要合并到「${target_branch}」。"
  exit 0
fi

echo "目标分支: ${target_branch}"
echo "将在此 worktree 执行合并: ${merge_base}"
if [[ -n "$(git -C "$merge_base" status --porcelain 2>/dev/null || true)" ]]; then
  echo "警告: 目标 worktree 存在未提交修改；git merge 可能失败，请先提交或 stash。" >&2
fi
echo ""

for i in "${!sources[@]}"; do
  src="${sources[$i]}"
  lab="${labels[$i]}"
  wt_path_for_src=""
  for j in "${!wt_path[@]}"; do
    if [[ "${wt_detached[$j]}" == "1" || -z "${wt_branch_ref[$j]:-}" ]]; then
      if [[ "${wt_head[$j]}" == "$src" ]]; then
        wt_path_for_src="${wt_path[$j]}"
        break
      fi
    else
      short_j="$(git rev-parse --abbrev-ref "${wt_branch_ref[$j]}" 2>/dev/null || true)"
      if [[ "$short_j" == "$src" ]]; then
        wt_path_for_src="${wt_path[$j]}"
        break
      fi
    fi
  done
  if [[ -z "$wt_path_for_src" ]]; then
    wt_path_for_src="(unknown)"
  fi

  if [[ -n "$(git -C "$wt_path_for_src" status --porcelain 2>/dev/null || true)" ]]; then
    echo "警告: 「${lab}」存在未提交修改；合并的是分支/HEAD 上的已提交内容，不包含工作区未提交文件。" >&2
  fi

  echo "将合并: ${lab}"
done

echo ""

if [[ "$dry_run" == "1" ]]; then
  echo "DRY_RUN=1，未执行 git merge。"
  exit 0
fi

for i in "${!sources[@]}"; do
  src="${sources[$i]}"
  lab="${labels[$i]}"
  echo "---- git merge ${src} (from ${lab}) ----"
  if ! git -C "$merge_base" merge "$src" -m "chore: merge worktree ${src} into ${target_branch}"; then
    echo "合并「${src}」发生冲突或失败，请在「${merge_base}」中解决后重新运行本脚本（已合并的不会重复）。" >&2
    exit 1
  fi
done

echo "全部合并完成。"

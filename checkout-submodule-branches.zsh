#!/usr/bin/env zsh

emulate -L zsh
setopt NO_UNSET PIPE_FAIL

typeset -gr SCRIPT_DIR=${0:A:h}
source "$SCRIPT_DIR/package-groups.zsh"

if (( $# != 0 ))
then
  print -u2 -r -- "ERROR This script does not accept arguments"
  exit 2
fi

validate_or_create_branch() {
  typeset repository=$1
  typeset package=$2
  typeset branch=$3
  typeset remote=$4
  typeset expected_merge_ref="refs/heads/$branch"
  typeset configured_remote
  typeset configured_merge_ref
  typeset local_commit
  typeset remote_commit

  if ! git -C "$repository" show-ref --verify --quiet \
    "refs/remotes/$remote/$branch"
  then
    print -u2 -r -- "ERROR [$package] Missing $remote/$branch"
    return 1
  fi

  if git -C "$repository" show-ref --verify --quiet "refs/heads/$branch"
  then
    configured_remote=$(
      git -C "$repository" config --get "branch.$branch.remote"
    )
    configured_merge_ref=$(
      git -C "$repository" config --get "branch.$branch.merge"
    )

    if [[ $configured_remote != $remote || \
      $configured_merge_ref != $expected_merge_ref ]]
    then
      print -u2 -r -- \
        "ERROR [$package] $branch does not track $remote/$branch"
      return 1
    fi

    local_commit=$(git -C "$repository" rev-parse "refs/heads/$branch")
    remote_commit=$(
      git -C "$repository" rev-parse "refs/remotes/$remote/$branch"
    )

    if [[ $local_commit != $remote_commit ]]
    then
      print -u2 -r -- \
        "ERROR [$package] $branch differs from $remote/$branch"
      return 1
    fi
  else
    if ! git -C "$repository" branch --track "$branch" "$remote/$branch"
    then
      print -u2 -r -- "ERROR [$package] Could not create $branch"
      return 1
    fi
  fi

  return 0
}

typeset -a failed_packages
typeset package
typeset repository
typeset intended_branch
typeset tracking_remote
typeset upstream_branch
typeset dirty_state

for package in "${ALL_PACKAGES[@]}"
do
  repository="$SCRIPT_DIR/$package"
  intended_branch=${SUBMODULE_BRANCHES[$package]}
  tracking_remote=${TRACKING_REMOTES[$package]}

  print -r -- ""
  print -r -- "==> $package"

  if ! git -C "$repository" rev-parse --is-inside-work-tree >/dev/null 2>&1
  then
    print -u2 -r -- "ERROR [$package] Submodule is not initialized"
    failed_packages+=("$package")
    continue
  fi

  dirty_state=$(git -C "$repository" status --porcelain --untracked-files=all)
  if [[ -n $dirty_state ]]
  then
    print -u2 -r -- "$dirty_state"
    print -u2 -r -- "ERROR [$package] Worktree is not clean"
    failed_packages+=("$package")
    continue
  fi

  if ! git -C "$repository" fetch --prune origin
  then
    print -u2 -r -- "ERROR [$package] Could not fetch origin"
    failed_packages+=("$package")
    continue
  fi

  if [[ $tracking_remote == github ]]
  then
    if ! git -C "$repository" fetch --prune github
    then
      print -u2 -r -- "ERROR [$package] Could not fetch github"
      failed_packages+=("$package")
      continue
    fi

    upstream_branch=${UPSTREAM_BRANCHES[$package]}

    if ! validate_or_create_branch \
      "$repository" "$package" "$upstream_branch" origin
    then
      failed_packages+=("$package")
      continue
    fi
  fi

  if ! validate_or_create_branch \
    "$repository" "$package" "$intended_branch" "$tracking_remote"
  then
    failed_packages+=("$package")
    continue
  fi

  if ! git -C "$repository" switch "$intended_branch"
  then
    print -u2 -r -- "ERROR [$package] Could not switch to $intended_branch"
    failed_packages+=("$package")
    continue
  fi

  print -r -- "Checked out $intended_branch"
done

print -r -- ""

if (( ${#failed_packages} > 0 ))
then
  print -u2 -r -- \
    "Failed packages: ${(j:, :)failed_packages}"
  exit 1
fi

print -r -- "All submodule branches are checked out"

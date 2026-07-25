#!/usr/bin/env zsh

emulate -L zsh
setopt NO_UNSET PIPE_FAIL

typeset -gr SCRIPT_DIR=${0:A:h}
source "$SCRIPT_DIR/package-groups.zsh"

fail_package() {
  typeset package=$1
  typeset message=$2

  print -u2 -r -- "ERROR [$package] $message"
  failed_packages+=("$package")
}

confirm_push() {
  typeset package=$1
  typeset upstream_branch=$2
  typeset patched_branch=$3
  typeset answer
  typeset read_status

  while true
  do
    read -r \
      "answer?Push $package ($upstream_branch + $patched_branch)? [Y/n] "
    read_status=$?

    if (( read_status != 0 ))
    then
      print -u2 -r -- ""
      print -u2 -r -- "ERROR Input closed while waiting for confirmation"
      return 2
    fi

    answer=${answer:l}

    if [[ -z $answer || $answer == y || $answer == yes ]]
    then
      return 0
    fi

    if [[ $answer == n || $answer == no ]]
    then
      return 1
    fi

    print -u2 -r -- "Please answer y or n"
  done
}

typeset -i prompt_enabled=1

if (( $# == 1 )) && [[ $1 == --no-prompt ]]
then
  prompt_enabled=0
elif (( $# != 0 ))
then
  print -u2 -r -- "ERROR The only supported option is --no-prompt"
  exit 2
fi

typeset -a failed_packages
typeset package
typeset confirmation_status
typeset repository
typeset upstream_branch
typeset patched_branch
typeset expected_github_url
typeset github_fetch_url
typeset github_push_url
typeset dirty_state
typeset local_upstream_commit
typeset origin_upstream_commit
typeset -i pushed_count=0
typeset -i skipped_count=0

for package in "${PATCHED_PACKAGES[@]}"
do
  repository="$SCRIPT_DIR/$package"
  upstream_branch=${UPSTREAM_BRANCHES[$package]}
  patched_branch=${PATCHED_BRANCHES[$package]}
  expected_github_url="https://github.com/dcompoze/$package"
  github_fetch_url=
  github_push_url=
  dirty_state=
  local_upstream_commit=
  origin_upstream_commit=

  if (( prompt_enabled ))
  then
    confirm_push "$package" "$upstream_branch" "$patched_branch"
    confirmation_status=$?
  else
    confirmation_status=0
  fi

  if (( confirmation_status == 1 ))
  then
    print -r -- "Skipped $package"
    (( skipped_count += 1 ))
    continue
  fi

  if (( confirmation_status == 2 ))
  then
    exit 2
  fi

  print -r -- ""
  print -r -- "==> $package"

  if ! git -C "$repository" rev-parse --is-inside-work-tree >/dev/null 2>&1
  then
    fail_package "$package" "Not a Git repository: $repository"
    continue
  fi

  dirty_state=$(git -C "$repository" status --porcelain --untracked-files=all)
  if [[ -n $dirty_state ]]
  then
    print -u2 -r -- "$dirty_state"
    fail_package "$package" "Worktree is not clean"
    continue
  fi

  if ! github_fetch_url=$(git -C "$repository" remote get-url github 2>/dev/null)
  then
    fail_package "$package" "Missing github remote"
    continue
  fi

  if ! github_push_url=$(git -C "$repository" remote get-url --push github 2>/dev/null)
  then
    fail_package "$package" "Missing github push URL"
    continue
  fi

  if [[ $github_fetch_url != $expected_github_url || $github_push_url != $expected_github_url ]]
  then
    fail_package "$package" \
      "github remote must use $expected_github_url for fetch and push"
    continue
  fi

  if ! git -C "$repository" fetch --prune origin
  then
    fail_package "$package" "Could not fetch origin"
    continue
  fi

  if ! git -C "$repository" fetch --prune github
  then
    fail_package "$package" "Could not fetch github"
    continue
  fi

  if ! git -C "$repository" show-ref --verify --quiet "refs/heads/$upstream_branch"
  then
    fail_package "$package" "Missing local $upstream_branch branch"
    continue
  fi

  if ! git -C "$repository" show-ref --verify --quiet \
    "refs/remotes/origin/$upstream_branch"
  then
    fail_package "$package" "Missing origin/$upstream_branch"
    continue
  fi

  local_upstream_commit=$(
    git -C "$repository" rev-parse "refs/heads/$upstream_branch"
  )
  origin_upstream_commit=$(
    git -C "$repository" rev-parse "refs/remotes/origin/$upstream_branch"
  )

  if [[ $local_upstream_commit != $origin_upstream_commit ]]
  then
    fail_package "$package" \
      "$upstream_branch does not exactly match origin/$upstream_branch"
    continue
  fi

  if ! git -C "$repository" show-ref --verify --quiet \
    "refs/heads/$patched_branch"
  then
    fail_package "$package" "Missing local $patched_branch branch"
    continue
  fi

  if ! git -C "$repository" merge-base --is-ancestor \
    "refs/heads/$upstream_branch" "refs/heads/$patched_branch"
  then
    fail_package "$package" \
      "$patched_branch is not based on the current $upstream_branch"
    continue
  fi

  if ! git -C "$repository" push github \
    "refs/heads/${upstream_branch}:refs/heads/${upstream_branch}"
  then
    fail_package "$package" "Could not push $upstream_branch"
    continue
  fi

  if git -C "$repository" show-ref --verify --quiet \
    "refs/remotes/github/$patched_branch"
  then
    if ! git -C "$repository" push --set-upstream --force-with-lease github \
      "refs/heads/${patched_branch}:refs/heads/${patched_branch}"
    then
      fail_package "$package" "Could not update $patched_branch"
      continue
    fi
  else
    print -r -- "Publishing $patched_branch for the first time"

    if ! git -C "$repository" push --set-upstream github \
      "refs/heads/${patched_branch}:refs/heads/${patched_branch}"
    then
      fail_package "$package" "Could not publish $patched_branch"
      continue
    fi
  fi

  print -r -- "Pushed $upstream_branch and $patched_branch"
  (( pushed_count += 1 ))
done

print -r -- ""

if (( ${#failed_packages} > 0 ))
then
  print -u2 -r -- \
    "Failed packages: ${(j:, :)failed_packages}"
  exit 1
fi

print -r -- "Pushed packages: $pushed_count"
print -r -- "Skipped packages: $skipped_count"

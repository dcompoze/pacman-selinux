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

typeset -a failed_packages
typeset package
typeset repository
typeset expected_origin_url
typeset expected_github_url
typeset actual_origin_url
typeset actual_github_url
typeset upstream_branch

for package in "${ALL_PACKAGES[@]}"
do
  repository="$SCRIPT_DIR/$package"
  expected_origin_url=${ORIGIN_URLS[$package]}

  print -r -- ""
  print -r -- "==> $package"

  if ! git -C "$repository" rev-parse --is-inside-work-tree >/dev/null 2>&1
  then
    print -u2 -r -- "ERROR [$package] Submodule is not initialized"
    failed_packages+=("$package")
    continue
  fi

  if [[ -n ${PATCHED_BRANCHES[$package]-} ]]
  then
    expected_github_url="https://github.com/dcompoze/$package"
    actual_origin_url=$(git -C "$repository" remote get-url origin 2>/dev/null)
    actual_github_url=$(git -C "$repository" remote get-url github 2>/dev/null)

    if [[ $actual_origin_url == $expected_github_url && -z $actual_github_url ]]
    then
      if ! git -C "$repository" remote rename origin github
      then
        print -u2 -r -- "ERROR [$package] Could not rename origin to github"
        failed_packages+=("$package")
        continue
      fi

      if ! git -C "$repository" remote add origin "$expected_origin_url"
      then
        print -u2 -r -- "ERROR [$package] Could not add authoritative origin"
        failed_packages+=("$package")
        continue
      fi

      upstream_branch=${UPSTREAM_BRANCHES[$package]}

      if git -C "$repository" show-ref --verify --quiet \
        "refs/heads/$upstream_branch"
      then
        git -C "$repository" config \
          "branch.$upstream_branch.remote" origin
        git -C "$repository" config \
          "branch.$upstream_branch.merge" \
          "refs/heads/$upstream_branch"
      fi
    fi

    actual_origin_url=$(git -C "$repository" remote get-url origin 2>/dev/null)
    actual_github_url=$(git -C "$repository" remote get-url github 2>/dev/null)

    if [[ $actual_origin_url != $expected_origin_url ]]
    then
      print -u2 -r -- \
        "ERROR [$package] origin must use $expected_origin_url"
      failed_packages+=("$package")
      continue
    fi

    if [[ $actual_github_url != $expected_github_url ]]
    then
      print -u2 -r -- \
        "ERROR [$package] github must use $expected_github_url"
      failed_packages+=("$package")
      continue
    fi
  else
    actual_origin_url=$(git -C "$repository" remote get-url origin 2>/dev/null)

    if [[ $actual_origin_url != $expected_origin_url ]]
    then
      print -u2 -r -- \
        "ERROR [$package] origin must use $expected_origin_url"
      failed_packages+=("$package")
      continue
    fi
  fi

  print -r -- "Remote layout is configured"
done

print -r -- ""

if (( ${#failed_packages} > 0 ))
then
  print -u2 -r -- \
    "Failed packages: ${(j:, :)failed_packages}"
  exit 1
fi

print -r -- "All submodule remotes are configured"

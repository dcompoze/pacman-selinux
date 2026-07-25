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

typeset -gr EXCLUDE_BLOCK_BEGIN="# BEGIN pacman-selinux makepkg outputs"
typeset -gr EXCLUDE_BLOCK_END="# END pacman-selinux makepkg outputs"
typeset -gra MAKEPKG_EXCLUDES=(
  "/pkg/"
  "/src/"
  "*.pkg.tar.*"
  "*.src.tar.*"
  "*.log"
)

configure_local_excludes()
{
  typeset repository=$1
  typeset exclude_file
  typeset exclude_directory
  typeset temporary_file
  typeset line
  typeset -a retained_lines
  typeset -i inside_managed_block=0

  exclude_file=$(git -C "$repository" rev-parse --git-path info/exclude) ||
    return 1
  exclude_directory=${exclude_file:h}

  if ! mkdir -p -- "$exclude_directory"
  then
    return 1
  fi

  if [[ -f $exclude_file ]]
  then
    while IFS= read -r line || [[ -n $line ]]
    do
      if [[ $line == $EXCLUDE_BLOCK_BEGIN ]]
      then
        if (( inside_managed_block ))
        then
          return 1
        fi

        inside_managed_block=1
        continue
      fi

      if [[ $line == $EXCLUDE_BLOCK_END ]]
      then
        if (( ! inside_managed_block ))
        then
          return 1
        fi

        inside_managed_block=0
        continue
      fi

      if (( ! inside_managed_block ))
      then
        retained_lines+=("$line")
      fi
    done < "$exclude_file"
  fi

  if (( inside_managed_block ))
  then
    return 1
  fi

  temporary_file=$(mktemp "$exclude_directory/exclude.XXXXXX") ||
    return 1

  if ! {
    if (( ${#retained_lines} > 0 ))
    then
      print -rl -- "${retained_lines[@]}"

      if [[ -n ${retained_lines[-1]} ]]
      then
        print -r -- ""
      fi
    fi

    print -r -- "$EXCLUDE_BLOCK_BEGIN"
    print -rl -- "${MAKEPKG_EXCLUDES[@]}"
    print -r -- "$EXCLUDE_BLOCK_END"
  } > "$temporary_file"
  then
    rm -f -- "$temporary_file"
    return 1
  fi

  if [[ -f $exclude_file ]] && cmp -s -- "$temporary_file" "$exclude_file"
  then
    rm -f -- "$temporary_file"
    return 0
  fi

  if ! chmod 0644 "$temporary_file" ||
    ! mv -f -- "$temporary_file" "$exclude_file"
  then
    rm -f -- "$temporary_file"
    return 1
  fi
}

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

  if ! configure_local_excludes "$repository"
  then
    print -u2 -r -- \
      "ERROR [$package] Could not configure local makepkg exclusions"
    failed_packages+=("$package")
    continue
  fi

  print -r -- "Remote layout is configured"
  print -r -- "Local makepkg exclusions are configured"
done

print -r -- ""

if (( ${#failed_packages} > 0 ))
then
  print -u2 -r -- \
    "Failed packages: ${(j:, :)failed_packages}"
  exit 1
fi

print -r -- "All submodule remotes and local exclusions are configured"

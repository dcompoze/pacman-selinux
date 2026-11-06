#!/usr/bin/env zsh

# Requires package-groups.zsh. These checks use local Git objects and metadata.
# Successful calls set PACKAGE_BASE_COMMIT and PACKAGE_BASE_VERSION.
package_srcinfo_version()
{
  awk -F ' = ' '
    /^[[:space:]]*epoch = / {epoch=$2}
    /^[[:space:]]*pkgver = / {pkgver=$2}
    /^[[:space:]]*pkgrel = / {pkgrel=$2}
    END {
      if (pkgver == "" || pkgrel == "") exit 1
      prefix=(epoch != "" && epoch != "0") ? epoch ":" : ""
      print prefix pkgver "-" pkgrel
    }
  '
}

validate_package_base()
{
  emulate -L zsh
  setopt NO_UNSET PIPE_FAIL

  typeset repository=$1
  typeset package=$2
  typeset patched_ref=${3:-HEAD}
  typeset upstream_branch=${UPSTREAM_BRANCHES[$package]-}
  typeset official_package
  typeset base_tag
  typeset tag_commit
  typeset upstream_commit
  typeset merge_base
  typeset -i is_official=0
  typeset -g PACKAGE_BASE_COMMIT=
  typeset -g PACKAGE_BASE_VERSION=

  for official_package in "${OFFICIAL_PATCHED_PACKAGES[@]}"
  do
    if [[ $official_package == $package ]]
    then
      is_official=1
      break
    fi
  done

  if [[ -z $upstream_branch ]] ||
    ! upstream_commit=$(git -C "$repository" rev-parse --verify \
      "refs/heads/$upstream_branch^{commit}" 2>/dev/null)
  then
    print -u2 -r -- "ERROR [$package] Missing upstream branch"
    return 1
  fi

  if (( is_official ))
  then
    base_tag=${OFFICIAL_BASE_TAGS[$package]-}
    PACKAGE_BASE_COMMIT=${OFFICIAL_BASE_COMMITS[$package]-}

    if [[ -z $base_tag || ! $PACKAGE_BASE_COMMIT =~ '^[0-9a-f]{40}$' ]] ||
      ! git check-ref-format "refs/tags/$base_tag" >/dev/null 2>&1
    then
      print -u2 -r -- "ERROR [$package] Missing or invalid stable package base"
      return 1
    fi

    if ! tag_commit=$(git -C "$repository" rev-parse --verify \
      "refs/tags/$base_tag^{commit}" 2>/dev/null) ||
      [[ $tag_commit != $PACKAGE_BASE_COMMIT ]]
    then
      print -u2 -r -- \
        "ERROR [$package] Tag $base_tag does not match the pinned commit"
      return 1
    fi

    if ! PACKAGE_BASE_VERSION=$(
      git -C "$repository" show "$PACKAGE_BASE_COMMIT:.SRCINFO" |
        package_srcinfo_version
    )
    then
      print -u2 -r -- "ERROR [$package] Cannot read stable base metadata"
      return 1
    fi
  else
    PACKAGE_BASE_COMMIT=$upstream_commit
  fi

  if ! merge_base=$(git -C "$repository" merge-base \
    "$upstream_commit" "$patched_ref") ||
    [[ $merge_base != $PACKAGE_BASE_COMMIT ]]
  then
    print -u2 -r -- \
      "ERROR [$package] $patched_ref must branch from $PACKAGE_BASE_COMMIT"
    return 1
  fi

  return 0
}

validate_official_package_version()
{
  emulate -L zsh
  setopt NO_UNSET PIPE_FAIL

  typeset repository=$1
  typeset package=$2
  typeset official_version=$3
  typeset recipe_version

  if [[ -z $official_version ]]
  then
    print -u2 -r -- "ERROR [$package] Could not resolve the Arch core version"
    return 1
  fi

  validate_package_base "$repository" "$package" HEAD || return 1

  if (( $(vercmp "$PACKAGE_BASE_VERSION" "$official_version") != 0 ))
  then
    print -u2 -r -- \
      "ERROR [$package] Stable base differs: selected=$PACKAGE_BASE_VERSION official=$official_version, update package-groups.zsh and rebase"
    return 1
  fi

  if [[ ! -r "$repository/.SRCINFO" ]] ||
    ! recipe_version=$(package_srcinfo_version < "$repository/.SRCINFO")
  then
    print -u2 -r -- "ERROR [$package] Could not read package version metadata"
    return 1
  fi

  if (( $(vercmp "${recipe_version%-*}" "${official_version%-*}") != 0 ))
  then
    print -u2 -r -- \
      "ERROR [$package] Upstream version differs: recipe=$recipe_version official=$official_version"
    return 1
  fi

  if (( $(vercmp "$recipe_version" "$official_version") <= 0 ))
  then
    print -u2 -r -- \
      "ERROR [$package] Package must exceed the official version: recipe=$recipe_version official=$official_version"
    return 1
  fi

  return 0
}

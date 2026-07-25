#!/usr/bin/env zsh

emulate -L zsh
setopt NO_UNSET PIPE_FAIL

typeset -gr SCRIPT_DIR=${0:A:h}
source "$SCRIPT_DIR/release-common.zsh"

parse_prompt_option "$@" || exit $?

validate_cleanup_path()
{
  typeset path=${1:A}

  if [[ $path == / || $path == /tmp || $path == /var/tmp ||
    $path == $SCRIPT_DIR ]]
  then
    return 1
  fi

  [[ $path == /tmp/* || $path == /var/tmp/* ||
    $path == "$SCRIPT_DIR"/artifacts(|/*) ]]
}

validate_cleanup_path "$BUILD_ROOT" || {
  print -u2 -r -- "ERROR Unsafe build root: $BUILD_ROOT"
  exit 1
}

validate_cleanup_path "$ARTIFACTS_DIR" || {
  print -u2 -r -- "ERROR Unsafe artifacts directory: $ARTIFACTS_DIR"
  exit 1
}

if (( PROMPT_ENABLED ))
then
  confirm_action "Delete all generated package-build and release files?" ||
    exit $?
fi

typeset package
typeset repository
typeset dirty_state
typeset -a dirty_packages

for package in "${ALL_PACKAGES[@]}"
do
  repository="$SCRIPT_DIR/$package"

  if ! git -C "$repository" rev-parse --is-inside-work-tree >/dev/null 2>&1
  then
    print -u2 -r -- "ERROR [$package] Submodule is not initialized"
    dirty_packages+=("$package")
    continue
  fi

  if ! git -C "$repository" clean -fdX
  then
    print -u2 -r -- "ERROR [$package] Could not remove ignored build output"
    dirty_packages+=("$package")
    continue
  fi

  dirty_state=$(git -C "$repository" status --porcelain --untracked-files=all)

  if [[ -n $dirty_state ]]
  then
    print -u2 -r -- "$dirty_state"
    print -u2 -r -- "ERROR [$package] Repository is not clean"
    dirty_packages+=("$package")
  fi
done

if [[ -e $BUILD_ROOT ]]
then
  rm -rf -- "$BUILD_ROOT" || {
    print -u2 -r -- "ERROR Could not remove build root: $BUILD_ROOT"
    exit 1
  }
fi

if [[ -e $ARTIFACTS_DIR ]]
then
  rm -rf -- "$ARTIFACTS_DIR" || {
    print -u2 -r -- "ERROR Could not remove artifacts: $ARTIFACTS_DIR"
    exit 1
  }
fi

if (( ${#dirty_packages} > 0 ))
then
  print -u2 -r -- "Repositories still dirty: ${(j:, :)dirty_packages}"
  exit 1
fi

print -r -- "All generated build and release files were removed"
print -r -- "All package submodules are clean"

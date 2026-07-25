#!/usr/bin/env zsh

emulate -L zsh
setopt NO_UNSET PIPE_FAIL

typeset -gr SCRIPT_DIR=${0:A:h}
source "$SCRIPT_DIR/release-common.zsh"

parse_prompt_option "$@" || exit $?

validate_artifacts_path()
{
  typeset path=${1:A}

  [[ $path == "$SCRIPT_DIR"/artifacts(|/*) ]]
}

validate_artifacts_path "$ARTIFACTS_DIR" || {
  print -u2 -r -- "ERROR Unsafe artifacts directory: $ARTIFACTS_DIR"
  exit 1
}

if (( PROMPT_ENABLED ))
then
  confirm_action "Delete generated files inside the repository?" ||
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

print -r -- "All generated repository files were removed"
print -r -- "All package submodules are clean"

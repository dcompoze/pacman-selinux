#!/usr/bin/env zsh

emulate -L zsh
setopt NO_UNSET PIPE_FAIL

typeset -gr SCRIPT_DIR=${0:A:h}
source "$SCRIPT_DIR/release-common.zsh"

parse_prompt_option "$@" || exit $?

typeset -a script_arguments
typeset script
typeset script_status
typeset -a preparation_scripts=(
  sign-packages.zsh
  create-package-repository.zsh
  sign-repository-databases.zsh
  create-checksums.zsh
  sign-checksums.zsh
)

if (( ! PROMPT_ENABLED ))
then
  script_arguments=(--no-prompt)
fi

for script in "${preparation_scripts[@]}"
do
  print -r -- ""
  print -r -- "==> $script"

  "$SCRIPT_DIR/$script" "${script_arguments[@]}"
  script_status=$?

  if (( script_status != 0 ))
  then
    print -u2 -r -- "ERROR $script failed"
    exit "$script_status"
  fi
done

print -r -- ""
print -r -- "Release assets are ready to publish"

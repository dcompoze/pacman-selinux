#!/usr/bin/env zsh

# Run with initialized submodules: zsh tests/package-bases.zsh
# Uses local objects only and does not change source branches or worktrees.
emulate -L zsh
setopt NO_UNSET PIPE_FAIL ERR_EXIT

typeset -r repository_root=${0:A:h:h}
typeset -a OFFICIAL_PATCHED_PACKAGES=()
typeset -A UPSTREAM_BRANCHES=()
typeset -A OFFICIAL_BASE_TAGS=()
typeset -A OFFICIAL_BASE_COMMITS=()
typeset package upstream_branch base_tag base_commit

# Import mutable copies so failure cases cannot change the real manifest.
while IFS='|' read -r package upstream_branch base_tag base_commit
do
  OFFICIAL_PATCHED_PACKAGES+=("$package")
  UPSTREAM_BRANCHES[$package]=$upstream_branch
  OFFICIAL_BASE_TAGS[$package]=$base_tag
  OFFICIAL_BASE_COMMITS[$package]=$base_commit
done < <(zsh -c '
  source "$1"
  for package in "${OFFICIAL_PATCHED_PACKAGES[@]}"
  do
    print -r -- "$package|${UPSTREAM_BRANCHES[$package]}|${OFFICIAL_BASE_TAGS[$package]}|${OFFICIAL_BASE_COMMITS[$package]}"
  done
' zsh "$repository_root/package-groups.zsh")

(( ${#OFFICIAL_PATCHED_PACKAGES} == 10 ))
source "$repository_root/package-bases.zsh"

typeset -i passed=0
typeset -r test_directory=$(mktemp -d)
trap 'rm -rf -- "$test_directory"' EXIT

expect_rejection()
{
  typeset description=$1
  shift
  if validate_package_base "$@" > "$test_directory/output" 2>&1
  then
    print -u2 -r -- "FAIL $description"
    return 1
  fi
  [[ -s "$test_directory/output" ]]
  print -r -- "PASS $description"
  (( passed += 1 ))
}

for package in "${OFFICIAL_PATCHED_PACKAGES[@]}"
do
  validate_package_base "$repository_root/$package" "$package" selinux
  [[ $PACKAGE_BASE_COMMIT == ${OFFICIAL_BASE_COMMITS[$package]} ]]
  [[ -n $PACKAGE_BASE_VERSION ]]
  print -r -- "PASS $package stable base $PACKAGE_BASE_VERSION"
  (( passed += 1 ))
done

typeset -r systemd_repository="$repository_root/systemd"
typeset -r selected_commit=${OFFICIAL_BASE_COMMITS[systemd]}
typeset -r selected_tag=${OFFICIAL_BASE_TAGS[systemd]}
typeset -r selected_version=$(
  git -C "$systemd_repository" show "$selected_commit:.SRCINFO" |
    package_srcinfo_version
)

validate_official_package_version "$systemd_repository" systemd "$selected_version"
print -r -- 'PASS recipe matches the selected Arch core package'
(( passed += 1 ))

for rejected_version in '' \
  "${selected_version%-*}-$(( ${selected_version##*-} + 1 ))" \
  "${selected_version%-*}.1-${selected_version##*-}"
do
  if validate_official_package_version "$systemd_repository" systemd \
    "$rejected_version" > "$test_directory/output" 2>&1
  then
    print -u2 -r -- "FAIL stale or missing Arch core version: $rejected_version"
    exit 1
  fi
  print -r -- "PASS reject stale or missing Arch core version: $rejected_version"
  (( passed += 1 ))
done

# Reuse local history with temporary metadata to test the package guards.
typeset -r recipe_fixture="$test_directory/recipe"
git clone --quiet --shared --no-checkout "$systemd_repository" "$recipe_fixture"
git -C "$recipe_fixture" branch main origin/main
git -C "$systemd_repository" show "$selected_commit:.SRCINFO" \
  > "$recipe_fixture/.SRCINFO"

if validate_official_package_version "$recipe_fixture" systemd \
  "$selected_version" > "$test_directory/output" 2>&1
then
  print -u2 -r -- 'FAIL recipe version equal to the official package'
  exit 1
fi
rg -q 'Package must exceed the official version' "$test_directory/output"
print -r -- 'PASS recipe version must exceed the official package'
(( passed += 1 ))

awk '/^[[:space:]]*pkgver = / {$0=$0 ".1"} {print}' \
  "$systemd_repository/.SRCINFO" > "$recipe_fixture/.SRCINFO"
if validate_official_package_version "$recipe_fixture" systemd \
  "$selected_version" > "$test_directory/output" 2>&1
then
  print -u2 -r -- 'FAIL recipe upstream version differs from Arch core'
  exit 1
fi
rg -q 'Upstream version differs' "$test_directory/output"
print -r -- 'PASS recipe upstream version must match Arch core'
(( passed += 1 ))

OFFICIAL_BASE_COMMITS[systemd]=0000000000000000000000000000000000000000
expect_rejection 'tag and commit mismatch' "$systemd_repository" systemd selinux

OFFICIAL_BASE_COMMITS[systemd]=$selected_commit
OFFICIAL_BASE_TAGS[systemd]=missing-package-base-tag
expect_rejection 'missing tag' "$systemd_repository" systemd selinux

OFFICIAL_BASE_TAGS[systemd]=$selected_tag
unset 'OFFICIAL_BASE_COMMITS[systemd]'
expect_rejection 'missing official pin' "$systemd_repository" systemd selinux

OFFICIAL_BASE_COMMITS[systemd]=main
expect_rejection 'unpinned symbolic commit' "$systemd_repository" systemd selinux

OFFICIAL_BASE_COMMITS[systemd]=$selected_commit
UPSTREAM_BRANCHES[systemd]=missing-upstream-branch
expect_rejection 'missing upstream branch' "$systemd_repository" systemd selinux
UPSTREAM_BRANCHES[systemd]=main

if [[ $(git -C "$systemd_repository" rev-parse main) != $selected_commit ]]
then
  expect_rejection 'testing commits beyond the selected stable base' \
    "$systemd_repository" systemd main
fi

UPSTREAM_BRANCHES[selinux-refpolicy-arch]=master
validate_package_base "$repository_root/selinux-refpolicy-arch" \
  selinux-refpolicy-arch custom
[[ $PACKAGE_BASE_COMMIT == $(git -C "$repository_root/selinux-refpolicy-arch" rev-parse master) ]]
print -r -- 'PASS custom AUR package still uses current master'
(( passed += 1 ))

print -r -- "Passed $passed package base checks"

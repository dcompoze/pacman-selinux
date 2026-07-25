#!/usr/bin/env zsh

emulate -L zsh
setopt NO_UNSET PIPE_FAIL

typeset -gr SCRIPT_DIR=${0:A:h}
source "$SCRIPT_DIR/release-common.zsh"

parse_prompt_option "$@" || exit $?

fail()
{
  print -u2 -r -- "ERROR $1"
  exit 1
}

for command in bsdtar gh git gpg jq sha256sum
do
  command -v "$command" >/dev/null 2>&1 ||
    fail "Required command is missing: $command"
done

require_secret_signing_key || exit 1
validate_build_manifest || exit 1

typeset release_version=${PACMAN_RELEASE_VERSION-}

if [[ -z $release_version ]]
then
  if (( ! PROMPT_ENABLED ))
  then
    fail "PACMAN_RELEASE_VERSION is required with --no-prompt"
  fi

  if ! read -r "release_version?Release version (MAJOR.MINOR): "
  then
    print -u2 -r -- ""
    fail "Input closed while waiting for the release version"
  fi
fi

if [[ ! $release_version =~ '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' ]]
then
  fail "Release version must use canonical MAJOR.MINOR format"
fi

typeset -gr release_tag="v$release_version"

typeset package_name
typeset package_file
typeset signed_file
typeset -a release_assets
typeset -a signed_assets
typeset -a metadata_assets=(
  "$REPOSITORY_DIR/build-manifest.json"
  "$REPOSITORY_DIR/selinux.db"
  "$REPOSITORY_DIR/selinux.db.sig"
  "$REPOSITORY_DIR/selinux.files"
  "$REPOSITORY_DIR/selinux.files.sig"
  "$REPOSITORY_DIR/SHA256SUMS"
  "$REPOSITORY_DIR/SHA256SUMS.sig"
)

for package_name in "${PUBLISHED_PACKAGE_NAMES[@]}"
do
  package_file=${ARTIFACT_BY_PACKAGE[$package_name]}
  release_assets+=("$package_file" "$package_file.sig")
  signed_assets+=("$package_file")
done

release_assets+=("${metadata_assets[@]}")
signed_assets+=(
  "$REPOSITORY_DIR/selinux.db"
  "$REPOSITORY_DIR/selinux.files"
  "$REPOSITORY_DIR/SHA256SUMS"
)

for signed_file in "${release_assets[@]}"
do
  [[ -f $signed_file ]] || fail "Release asset is missing: $signed_file"
done

for signed_file in "${signed_assets[@]}"
do
  verify_detached_signature "$signed_file" "$signed_file.sig" ||
    fail "Signature verification failed: ${signed_file:t}.sig"
done

if ! (
  cd "$REPOSITORY_DIR" || exit 1
  sha256sum -c --quiet SHA256SUMS
)
then
  fail "SHA256SUMS verification failed"
fi

typeset -A expected_asset_names

for signed_file in "${release_assets[@]}"
do
  expected_asset_names[${signed_file:t}]=1
done

typeset -a repository_files
repository_files=("$REPOSITORY_DIR"/*(N.))

if (( ${#repository_files} != ${#release_assets} ))
then
  fail "Repository directory contains an unexpected number of release assets"
fi

for signed_file in "${repository_files[@]}"
do
  if [[ -z ${expected_asset_names[${signed_file:t}]-} ]]
  then
    fail "Unexpected release asset: ${signed_file:t}"
  fi
done

typeset dirty_state
typeset current_commit
typeset superproject_commit
typeset manifest_commit
typeset origin_url
typeset package
typeset recorded_commit
typeset manifest_submodule_commit

dirty_state=$(
  git -C "$SCRIPT_DIR" status --porcelain \
    --untracked-files=all --ignore-submodules=none
)

if [[ -n $dirty_state ]]
then
  print -u2 -r -- "$dirty_state"
  fail "Superproject or submodule state is not clean"
fi

current_commit=$(git -C "$SCRIPT_DIR" rev-parse HEAD)
manifest_commit=$(
  jq -r '.superproject_commit' "$REPOSITORY_DIR/build-manifest.json"
)

if ! git -C "$SCRIPT_DIR" cat-file -e "${manifest_commit}^{commit}"
then
  fail "Build manifest superproject commit does not exist"
fi

superproject_commit=$manifest_commit

for package in "${ALL_PACKAGES[@]}"
do
  recorded_commit=$(
    git -C "$SCRIPT_DIR" rev-parse "$superproject_commit:$package"
  ) || fail "Could not read $package from the build manifest commit"

  manifest_submodule_commit=$(
    jq -r --arg name "$package" \
      '.submodules[] | select(.name == $name) | .commit' \
      "$REPOSITORY_DIR/build-manifest.json"
  )

  if [[ $manifest_submodule_commit != $recorded_commit ]]
  then
    fail "Build manifest does not match the recorded $package commit"
  fi
done

origin_url=$(git -C "$SCRIPT_DIR" remote get-url origin)

if [[ ${origin_url%.git} != $EXPECTED_SUPERPROJECT_ORIGIN ]]
then
  fail "origin must use $EXPECTED_SUPERPROJECT_ORIGIN"
fi

if ! git -C "$SCRIPT_DIR" fetch --prune origin
then
  fail "Could not fetch superproject origin"
fi

if ! git -C "$SCRIPT_DIR" show-ref --verify --quiet refs/remotes/origin/main
then
  fail "origin/main is missing"
fi

if [[ $current_commit != \
  $(git -C "$SCRIPT_DIR" rev-parse refs/remotes/origin/main) ]]
then
  fail "Local HEAD must exactly match origin/main"
fi

if git -C "$SCRIPT_DIR" show-ref --verify --quiet \
  "refs/tags/$release_tag"
then
  fail "Local tag already exists: $release_tag"
fi

typeset remote_tag

remote_tag=$(
  git -C "$SCRIPT_DIR" ls-remote --tags origin \
    "refs/tags/$release_tag"
) || fail "Could not query remote tags"

if [[ -n $remote_tag ]]
then
  fail "Remote tag already exists: $release_tag"
fi

if ! gh auth status --hostname github.com >/dev/null 2>&1
then
  fail "GitHub CLI is not authenticated"
fi

if [[ $(gh api user --jq .login) != dcompoze ]]
then
  fail "GitHub CLI must be authenticated as dcompoze"
fi

if ! gh repo view "$GITHUB_REPOSITORY" >/dev/null
then
  fail "Could not access $GITHUB_REPOSITORY"
fi

if gh release view "$release_tag" \
  --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1
then
  fail "GitHub release already exists: $release_tag"
fi

if (( PROMPT_ENABLED ))
then
  confirm_action \
    "Publish signed release $release_tag to $GITHUB_REPOSITORY?" ||
    exit $?
fi

typeset -i local_tag_created=0
typeset -i remote_tag_created=0

rollback_release()
{
  print -u2 -r -- "Rolling back release $release_tag"

  if gh release view "$release_tag" \
    --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1
  then
    gh release delete "$release_tag" \
      --repo "$GITHUB_REPOSITORY" --cleanup-tag --yes ||
      print -u2 -r -- "ERROR Could not delete partial GitHub release"
  elif (( remote_tag_created ))
  then
    git -C "$SCRIPT_DIR" push origin \
      ":refs/tags/$release_tag" ||
      print -u2 -r -- "ERROR Could not delete partial remote tag"
  fi

  if (( local_tag_created ))
  then
    git -C "$SCRIPT_DIR" tag --delete "$release_tag" >/dev/null ||
      print -u2 -r -- "ERROR Could not delete local tag"
  fi
}

if ! git -C "$SCRIPT_DIR" -c gpg.format=openpgp tag --sign \
  --local-user "$SIGNING_KEY" \
  --message "pacman-selinux $release_tag" \
  "$release_tag" "$superproject_commit"
then
  fail "Could not create signed release tag"
fi

local_tag_created=1

if ! git -C "$SCRIPT_DIR" tag --verify "$release_tag"
then
  rollback_release
  fail "Signed release tag failed verification"
fi

if ! git -C "$SCRIPT_DIR" push origin \
  "refs/tags/${release_tag}:refs/tags/${release_tag}"
then
  rollback_release
  fail "Could not push signed release tag"
fi

remote_tag_created=1

typeset release_notes

release_notes=$(
  print -r -- "pacman-selinux $release_tag"
  print -r -- ""
  print -r -- "Superproject commit: $superproject_commit"
  print -r -- "Architecture: x86_64"
  print -r -- "Packages: ${#PUBLISHED_PACKAGE_NAMES[@]}"
  print -r -- "Signing key: $SIGNING_KEY"
  print -r -- ""
  print -r -- "See build-manifest.json and SHA256SUMS for details."
)

if ! gh release create "$release_tag" \
  --repo "$GITHUB_REPOSITORY" \
  --verify-tag \
  --latest \
  --title "$release_tag" \
  --notes "$release_notes" \
  "${release_assets[@]}"
then
  rollback_release
  fail "Could not create GitHub release"
fi

typeset actual_assets_json
typeset expected_assets_json
typeset latest_tag

actual_assets_json=$(
  gh release view "$release_tag" \
    --repo "$GITHUB_REPOSITORY" \
    --json assets,isDraft,isPrerelease,tagName \
    --jq '
      if .isDraft or .isPrerelease then
        error("release is not final")
      else
        [.assets[].name] | sort
      end
    '
) || {
  rollback_release
  fail "Could not verify published release"
}

expected_assets_json=$(
  jq -cn --args '$ARGS.positional | sort' "${(@)release_assets:t}"
) || {
  rollback_release
  fail "Could not prepare expected release asset list"
}

if [[ $actual_assets_json != $expected_assets_json ]]
then
  rollback_release
  fail "Published release asset list differs from the local snapshot"
fi

latest_tag=$(
  gh release view --repo "$GITHUB_REPOSITORY" \
    --json tagName --jq .tagName
) || {
  rollback_release
  fail "Could not verify the latest release"
}

if [[ $latest_tag != $release_tag ]]
then
  rollback_release
  fail "Published release was not marked as latest"
fi

print -r -- "Published release $release_tag"
print -r -- \
  "Repository URL: https://github.com/$GITHUB_REPOSITORY/releases/latest/download"

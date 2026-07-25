#!/usr/bin/env zsh

# Shared package groups and branch mappings for repository maintenance scripts.

typeset -gra PATCHED_PACKAGES=(
  coreutils
  dbus-broker
  dbus
  openssh
  pam
  pambase
  shadow
  sudo
  systemd
  util-linux
  selinux-refpolicy-arch
)

typeset -gra AUR_PACKAGES=(
  checkpolicy
  libselinux
  libsemanage
  libsepol
  policycoreutils
  secilc
  selinux-alpm-hook
  selinux-python
  semodule-utils
  setools
)

typeset -gra ALL_PACKAGES=(
  "${PATCHED_PACKAGES[@]}"
  "${AUR_PACKAGES[@]}"
)

typeset -grA UPSTREAM_BRANCHES=(
  coreutils main
  dbus-broker main
  dbus main
  openssh main
  pam main
  pambase main
  shadow main
  sudo main
  systemd main
  util-linux main
  selinux-refpolicy-arch master
)

typeset -grA PATCHED_BRANCHES=(
  coreutils selinux
  dbus-broker selinux
  dbus selinux
  openssh selinux
  pam selinux
  pambase selinux
  shadow selinux
  sudo selinux
  systemd selinux
  util-linux selinux
  selinux-refpolicy-arch custom
)

typeset -grA ORIGIN_URLS=(
  coreutils https://gitlab.archlinux.org/archlinux/packaging/packages/coreutils
  dbus-broker https://gitlab.archlinux.org/archlinux/packaging/packages/dbus-broker
  dbus https://gitlab.archlinux.org/archlinux/packaging/packages/dbus
  openssh https://gitlab.archlinux.org/archlinux/packaging/packages/openssh
  pam https://gitlab.archlinux.org/archlinux/packaging/packages/pam
  pambase https://gitlab.archlinux.org/archlinux/packaging/packages/pambase
  shadow https://gitlab.archlinux.org/archlinux/packaging/packages/shadow
  sudo https://gitlab.archlinux.org/archlinux/packaging/packages/sudo
  systemd https://gitlab.archlinux.org/archlinux/packaging/packages/systemd
  util-linux https://gitlab.archlinux.org/archlinux/packaging/packages/util-linux
  selinux-refpolicy-arch https://aur.archlinux.org/selinux-refpolicy-arch
  checkpolicy https://aur.archlinux.org/checkpolicy.git
  libselinux https://aur.archlinux.org/libselinux.git
  libsemanage https://aur.archlinux.org/libsemanage.git
  libsepol https://aur.archlinux.org/libsepol.git
  policycoreutils https://aur.archlinux.org/policycoreutils.git
  secilc https://aur.archlinux.org/secilc
  selinux-alpm-hook https://aur.archlinux.org/selinux-alpm-hook
  selinux-python https://aur.archlinux.org/selinux-python.git
  semodule-utils https://aur.archlinux.org/semodule-utils
  setools https://aur.archlinux.org/setools.git
)

typeset -grA SUBMODULE_URLS=(
  coreutils https://github.com/dcompoze/coreutils
  dbus-broker https://github.com/dcompoze/dbus-broker
  dbus https://github.com/dcompoze/dbus
  openssh https://github.com/dcompoze/openssh
  pam https://github.com/dcompoze/pam
  pambase https://github.com/dcompoze/pambase
  shadow https://github.com/dcompoze/shadow
  sudo https://github.com/dcompoze/sudo
  systemd https://github.com/dcompoze/systemd
  util-linux https://github.com/dcompoze/util-linux
  selinux-refpolicy-arch https://github.com/dcompoze/selinux-refpolicy-arch
  checkpolicy https://aur.archlinux.org/checkpolicy.git
  libselinux https://aur.archlinux.org/libselinux.git
  libsemanage https://aur.archlinux.org/libsemanage.git
  libsepol https://aur.archlinux.org/libsepol.git
  policycoreutils https://aur.archlinux.org/policycoreutils.git
  secilc https://aur.archlinux.org/secilc
  selinux-alpm-hook https://aur.archlinux.org/selinux-alpm-hook
  selinux-python https://aur.archlinux.org/selinux-python.git
  semodule-utils https://aur.archlinux.org/semodule-utils
  setools https://aur.archlinux.org/setools.git
)

typeset -grA SUBMODULE_BRANCHES=(
  coreutils selinux
  dbus-broker selinux
  dbus selinux
  openssh selinux
  pam selinux
  pambase selinux
  shadow selinux
  sudo selinux
  systemd selinux
  util-linux selinux
  selinux-refpolicy-arch custom
  checkpolicy master
  libselinux master
  libsemanage master
  libsepol master
  policycoreutils master
  secilc master
  selinux-alpm-hook master
  selinux-python master
  semodule-utils master
  setools master
)

typeset -grA TRACKING_REMOTES=(
  coreutils github
  dbus-broker github
  dbus github
  openssh github
  pam github
  pambase github
  shadow github
  sudo github
  systemd github
  util-linux github
  selinux-refpolicy-arch github
  checkpolicy origin
  libselinux origin
  libsemanage origin
  libsepol origin
  policycoreutils origin
  secilc origin
  selinux-alpm-hook origin
  selinux-python origin
  semodule-utils origin
  setools origin
)

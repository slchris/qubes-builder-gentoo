#!/bin/bash

EMERGE_OPTS="-b -k -n"

if [ "0${IS_LEGACY_BUILDER}" -eq 1 ]; then
    TEMPLATE_SCRIPTS_DIR="$(readlink -f .)"
fi

prepareChroot() {
    CHROOT_DIR="$1"

    if [ ! -r "${CHROOT_DIR}/dev/zero" ]; then
        mkdir -p "${CHROOT_DIR}/dev"
        sudo mount --rbind /dev "${CHROOT_DIR}/dev"
    fi
    if [ "$(stat -f -c '%T' "${CHROOT_DIR}/dev/shm" 2>/dev/null)" != "tmpfs" ]; then
        mkdir -p "${CHROOT_DIR}/dev/shm"
        sudo mount -t tmpfs shm "${CHROOT_DIR}/dev/shm"
        sudo chmod 1777 "${CHROOT_DIR}/dev/shm"
    fi
    if [ ! -r "${CHROOT_DIR}/proc/cpuinfo" ]; then
        mkdir -p "${CHROOT_DIR}/proc"
        sudo mount -t proc proc "${CHROOT_DIR}/proc"
    fi
    if [ ! -d "${CHROOT_DIR}/sys/dev" ]; then\
        mkdir -p "${CHROOT_DIR}/sys"
        sudo mount --bind /sys "${CHROOT_DIR}/sys"
    fi
    cp /etc/resolv.conf "${CHROOT_DIR}/etc/resolv.conf"
}

chrootCmd() {
    CHROOT_DIR="$1"
    shift
    CMD="$*"

    /usr/sbin/chroot "${CHROOT_DIR}" env -i /bin/bash -l -c "env-update"
    /usr/sbin/chroot "${CHROOT_DIR}" env -i /bin/bash -l -c "source /etc/profile && $CMD"
}

updateChroot() {
    CHROOT_DIR="$1"
    chrootCmd "${CHROOT_DIR}" "emerge ${EMERGE_OPTS} --update --deep --newuse --changed-use --with-bdeps=y @world"
}

updatePortage() {
    CHROOT_DIR="$1"
    chrootCmd "${INSTALL_DIR}" 'emerge -b -k --update portage'
}

mountCache() {
    CACHE_DIR="$1"
    CHROOT_DIR="$2"

    mkdir -p "${CACHE_DIR}/distfiles"
    mkdir -p "${CACHE_DIR}/binpkgs"

    mount

    umount "${CHROOT_DIR}/var/cache/distfiles" || true
    umount "${CHROOT_DIR}/var/cache/binpkgs" || true

    mount --bind "${CACHE_DIR}/distfiles" "${CHROOT_DIR}/var/cache/distfiles"
    mount --bind "${CACHE_DIR}/binpkgs" "${CHROOT_DIR}/var/cache/binpkgs"

    chrootCmd "${CHROOT_DIR}" 'chmod 755 /var/cache/binpkgs'
    chrootCmd "${CHROOT_DIR}" 'chmod 755 /var/cache/distfiles'
    chrootCmd "${CHROOT_DIR}" 'chown -R portage:portage /var/cache/binpkgs'
    chrootCmd "${CHROOT_DIR}" 'chown -R portage:portage /var/cache/distfiles'
}

getFile() {
    BASEDIR="$1"
    PREFIX="$2"
    SUFFIX="$3"
    FLAVOR="$4"

    FILE="${BASEDIR}/${PREFIX}${FLAVOR}${SUFFIX}"

    echo "$FILE"
}

getPackagesList() {
    PREFIX="$1"
    FLAVOR="$2"

    # Strip comments, then convert newlines to single spaces
    FILE="$(getFile "${TEMPLATE_CONTENT_DIR}" "$PREFIX" ".list" "${FLAVOR}")"
    if [ ! -e "$FILE" ]; then
        echo "Cannot find '$FILE'!"
        exit 1
    fi
    PKGGROUPS="$(sed '/^ *#/d; s/  *#.*//' "$FILE" | sed ':a;N;$!ba; s/\n/ /g; s/  */ /g')"

    echo "${PKGGROUPS}"
}

getBasePackagesList() {
    FLAVOR="${1:-gnome}"
    getPackagesList packages_ "${FLAVOR}"
}

getQubesPackagesList() {
    FLAVOR="${1:-gnome}"
    getPackagesList packages_qubes_ "${FLAVOR}"
}

getBaseFlags() {
    FLAVOR="${1:-gnome}"
    FLAGS="$2"

    getFile "${TEMPLATE_CONTENT_DIR}/package.$FLAGS/" "" "" "${FLAVOR}"
}

getQubesFlags() {
    FLAVOR="${1:-gnome}"
    FLAGS="$2"

    getFile "${TEMPLATE_CONTENT_DIR}/package.$FLAGS/" "" "-qubes" "${FLAVOR}"
}

setupBaseFlags() {
    CHROOT_DIR="$1"
    FLAVOR="${2:-gnome}"
    for flag in use mask accept_keywords
    do
        if [ -e "$(getBaseFlags "$FLAVOR" "$flag")" ]; then
            mkdir -p "${CHROOT_DIR}/etc/portage/package.$flag"
            cp "$(getBaseFlags "$FLAVOR" "$flag")" "${CHROOT_DIR}/etc/portage/package.$flag/standard"
        fi
    done
}

setupQubesFlags() {
    CHROOT_DIR="$1"
    FLAVOR="${2:-gnome}"
    for flag in use mask accept_keywords
    do
        if [ -e "$(getQubesFlags "$FLAVOR" "$flag")" ]; then
            mkdir -p "${CHROOT_DIR}/etc/portage/package.$flag"
            cp "$(getQubesFlags "$FLAVOR" "$flag")" "${CHROOT_DIR}/etc/portage/package.$flag/qubes"
        fi
    done
}

setupQubesOverlay() {
    CHROOT_DIR="$1"
    RELEASE="$2"

    # Tunables come from config/build.conf (sourced by the top-level build script);
    # fall back to sane defaults so this function also works standalone.
    OVERLAY_SOURCE="${OVERLAY_SOURCE:-local}"
    # Default to the overlay tarball shipped INSIDE this component's sources, so
    # it rides along when builderv2 fetches builder-gentoo into the container
    # (the container can't see the builder host's /tmp). TEMPLATE_CONTENT_DIR is
    # the builder-gentoo scripts dir inside the container.
    OVERLAY_TARBALL="${OVERLAY_TARBALL:-${TEMPLATE_CONTENT_DIR}/../overlay/qubes-gentoo-overlay.tar.gz}"
    OVERLAY_GIT_URI="${OVERLAY_GIT_URI:-https://github.com/slchris/qubes-gentoo.git}"

    rm -rf "${CHROOT_DIR}/var/db/repos/qubes"
    mkdir -p "${CHROOT_DIR}/var/db/repos/qubes"

    if [ "${OVERLAY_SOURCE}" = "local" ]; then
        # The build machine can't reach GitHub, so the overlay is delivered as a
        # local tarball (packaged + commit-signature-verified on the dev box,
        # scp'd in — see scripts/deploy-to-builder.sh). We just unpack it; no
        # Portage git sync, no network. Commit-signature trust is established at
        # packaging time, not here.
        echo "  --> Installing Qubes overlay from local tarball ${OVERLAY_TARBALL}"
        [ -f "${OVERLAY_TARBALL}" ] || { echo "ERROR: overlay tarball not found: ${OVERLAY_TARBALL}"; exit 1; }
        tar -xzf "${OVERLAY_TARBALL}" -C "${CHROOT_DIR}/var/db/repos/qubes" --strip-components=1
        cat > "${CHROOT_DIR}/etc/portage/repos.conf/qubes.conf" <<EOF
[qubes]
location = /var/db/repos/qubes
auto-sync = no
EOF
        # Regenerate Manifests (the vendored ones were dropped). Without them
        # portage rejects the ebuilds as "masked by: corruption". Use portage's
        # OWN 'ebuild <ebuild> manifest' (always present; pkgdev may not be) on one
        # ebuild per package. layout.conf sets thin-manifests (these are git-r3
        # ebuilds with no DIST files), so this just writes the EBUILD hashes.
        chrootCmd "${CHROOT_DIR}" "export FEATURES=\"-getbinpkg\"; for e in /var/db/repos/qubes/*/*/*.ebuild; do ebuild \"\$e\" manifest 2>/dev/null || true; done; echo manifests-regenerated"
    else
        # git mode — for machines that DO have GitHub access.
        echo "  --> Syncing Qubes overlay from ${OVERLAY_GIT_URI}"
        cat > "${CHROOT_DIR}/etc/portage/repos.conf/qubes.conf" <<EOF
[qubes]
location = /var/db/repos/qubes
sync-uri = ${OVERLAY_GIT_URI}
sync-type = git
sync-git-verify-commit-signature = false
auto-sync = yes
EOF
        chrootCmd "${CHROOT_DIR}" "emaint sync -r qubes"
    fi
}

installBasePackages() {
    CHROOT_DIR="$1"
    FLAVOR="${2:-gnome}"

    PACKAGES="$(getBasePackagesList "$FLAVOR")"
    if [ -n "${PACKAGES}" ]; then
        echo "  --> Installing Gentoo packages..."
        echo "    --> Selected packages: ${PACKAGES}"
        chrootCmd "${CHROOT_DIR}" "emerge ${EMERGE_OPTS} ${PACKAGES}"
    fi
}

installQubesPackages() {
    CHROOT_DIR="$1"
    FLAVOR="${2:-gnome}"

    PACKAGES="$(getQubesPackagesList "$FLAVOR")"
    if [ -n "${PACKAGES}" ]; then
        echo "  --> Installing Qubes packages..."
        echo "    --> Selected packages: ${PACKAGES}"
        chrootCmd "${CHROOT_DIR}" "emerge ${EMERGE_OPTS} ${PACKAGES}"
    fi
}

setPortageProfile() {
    CHROOT_DIR="$1"
    FLAVOR="${2:-gnome}"
    # GENTOO_PROFILE (from config/build.conf) is the base/minimal profile. For a
    # desktop flavor we derive the matching desktop variant unless the caller has
    # overridden GENTOO_PROFILE explicitly.
    local base_profile="${GENTOO_PROFILE:-default/linux/amd64/23.0/systemd}"
    local profile="${base_profile}"
    if [ "$FLAVOR" == "xfce" ] || [ "$FLAVOR" == "gnome" ]; then
        # Only auto-derive when the profile is still the default minimal one.
        if [ "${base_profile}" == "default/linux/amd64/23.0/systemd" ]; then
            profile="default/linux/amd64/23.0/desktop/gnome/systemd"
        fi
    fi
    echo "  --> Selecting Portage profile: ${profile}"
    chrootCmd "${CHROOT_DIR}" "eselect profile set ${profile}"
}

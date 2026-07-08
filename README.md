# qubes-builder-gentoo

Build scripts for the Qubes OS **R4.3** Gentoo template, consumed by
[qubes-builderv2](https://github.com/slchris/qubes-builderv2) as the
`builder-gentoo` component.

A maintained fork of the upstream
[QubesOS/qubes-builder-gentoo](https://github.com/QubesOS/qubes-builder-gentoo)
(unmaintained since 2023, R4.2-pinned) with the community R4.3 fixes applied:

- **Fresh Gentoo release signing key** (`gentoo-release.asc.20250806`) replacing
  the expired `.20200704` — the upstream blocker (stage3 GPG verify failed).
- **23.0 Portage profile** (was the deprecated 17.1).
- **`setupQubesOverlay` reworked** to install the Qubes guest overlay from a
  LOCAL tarball (`OVERLAY_SOURCE=local`) — the build machine has no GitHub — with
  a `git` fallback; overlay = [slchris/qubes-gentoo](https://github.com/slchris/qubes-gentoo).
- **`setPortageProfile` driven by `GENTOO_PROFILE`** instead of a hard-coded one.

## Layout (matches upstream)

```
scripts/            00_prepare.sh, distribution.sh, per-flavor package lists,
                    package.use/*, package.accept_keywords/*, appmenus_*
keys/               gentoo-release.asc.20250806, overlay signing key
prepare-chroot-base / prepare-chroot-builder
Makefile.builder / Makefile.gentoo
```

## Used by

`qubes-builderv2`'s `example-configs/gentoo-r4.3-slchris.yml` references this repo
as the `builder-gentoo` component and verifies its signed git tag against the
maintainer key. See
[qubes-gentoo-template](https://github.com/slchris/qubes-gentoo-template) for the
overall build orchestration (China mirrors, deploy flow, config).

## License

MIT / GPL-2 (as inherited from upstream ebuild/build scripts).

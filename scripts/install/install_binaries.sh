#!/bin/bash
# install_binaries.sh — install untracked toolchain and binary artifacts on demand.
#
# Reads a manifest (target, kind, url, sha256, option), downloads each
# artifact once into a sha256-named cache (verified against the manifest),
# and installs it into the repo. Installed targets are skipped and cached
# downloads are reused, so a second run needs no network.
#
# Exit codes: 0 ok; 3 at least one target missing (downloads disabled);
# 1 any error (bad row, hash mismatch, failed download or extraction).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Settings (environment, with defaults)
ENV_DIR="${ENV_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
BINARIES_MANIFEST="${BINARIES_MANIFEST:-$ENV_DIR/config/binaries.tsv}"
BINARIES_CACHE="${BINARIES_CACHE:-$ENV_DIR/tmp/binaries-cache}"
BINARIES_CURL="${BINARIES_CURL:-curl -fsSL --retry 3}"

DRY_RUN=0
ONLY=""
MISSING_TARGETS=()
TMP_DIRS=()

# log helpers
info() { echo "install_binaries: $*"; }
warn() { echo "install_binaries: WARNING: $*" >&2; }
die() { echo "install_binaries: ERROR: $*" >&2; exit 1; }

# remove all temp dirs on exit (also on error)
cleanup() {
    local d
    for d in "${TMP_DIRS[@]}"; do
        rm -rf "$d"
    done
}
trap cleanup EXIT

# make a fresh temp dir tracked by cleanup
new_tmp_dir() {
    local d
    d=$(mktemp -d)
    TMP_DIRS+=("$d")
    printf '%s' "$d"
}

# create a relative symlink if the target file exists and the link path is free
create_link() {
    local link_rel="$1" target_rel="$2"
    local link_path="$ENV_DIR/$link_rel"
    local target_file="$ENV_DIR/$(dirname "$link_rel")/$target_rel"
    if [[ -e "$target_file" && ! -e "$link_path" && ! -L "$link_path" ]]; then
        ln -s "$target_rel" "$link_path" || die "could not create link '$link_rel'"
    fi
}

# handle one manifest row
install_row() {
    local target="$1" kind="$2" url="$3" sha="$4" option="$5"
    local installed_path cache_file part_file actual workdir entries extract_dir replaced

    if [[ -n "$ONLY" && "$target" != "$ONLY" && "$target" != "$ONLY/"* ]]; then
        return 0
    fi

    if [[ "$kind" == "sdk" ]]; then
        installed_path="$ENV_DIR/$target/bin/go"
    else
        installed_path="$ENV_DIR/$target"
    fi
    if [[ -x "$installed_path" ]]; then
        info "skip  $target"
        return 0
    fi

    cache_file="$BINARIES_CACHE/$sha"
    if [[ ! -f "$cache_file" ]]; then
        if [[ "$DRY_RUN" -eq 1 ]]; then
            info "would download $url"
            return 0
        fi
        if [[ -n "${BINARIES_NO_NETWORK:-}" ]]; then
            warn "missing $target (download disabled)"
            MISSING_TARGETS+=("$target")
            return 0
        fi
        mkdir -p "$BINARIES_CACHE"
        part_file="$BINARIES_CACHE/.part.$$"
        info "download $url"
        if ! $BINARIES_CURL "$url" -o "$part_file"; then
            rm -f "$part_file"
            die "download failed: $url"
        fi
        actual=$(sha256sum "$part_file" | awk '{print $1}')
        if [[ "$actual" != "$sha" ]]; then
            rm -f "$part_file"
            die "hash mismatch for $target: manifest $sha, actual $actual"
        fi
        mv "$part_file" "$cache_file"
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        info "would install $target"
        return 0
    fi

    mkdir -p "$(dirname "$ENV_DIR/$target")"
    case "$kind" in
        sdk)
            workdir=$(new_tmp_dir)
            tar -xzf "$cache_file" -C "$workdir" || die "extraction failed: $target"
            entries=$(find "$workdir" -mindepth 1 -maxdepth 1)
            if [[ -z "$entries" ]] || [[ $(printf '%s\n' "$entries" | wc -l) -ne 1 ]]; then
                die "sdk $target: archive does not hold exactly one top-level entry"
            fi
            if [[ -e "$ENV_DIR/$target" ]]; then
                replaced="$ENV_DIR/$target.replaced.$(date +%Y%m%d%H%M%S)"
                warn "replacing $ENV_DIR/$target with $replaced"
                mv "$ENV_DIR/$target" "$replaced"
            fi
            mv "$entries" "$ENV_DIR/$target"
            ;;
        tarball)
            workdir=$(new_tmp_dir)
            tar -xzf "$cache_file" -C "$workdir" "$option" \
                || die "extraction failed: $target"
            if [[ ! -f "$workdir/$option" ]]; then
                die "tarball $target: member '$option' not found in archive"
            fi
            install -m 0755 "$workdir/$option" "$ENV_DIR/$target"
            ;;
        file|appimage)
            install -m 0755 "$cache_file" "$ENV_DIR/$target"
            ;;
    esac

    if [[ "$kind" == "appimage" && "$option" == extract=* \
            && ! -e "$ENV_DIR/${option#extract=}" ]]; then
        extract_dir="${option#extract=}"
        workdir=$(new_tmp_dir)
        ( cd "$workdir" && "$ENV_DIR/$target" --appimage-extract ) >/dev/null \
            || die "appimage extraction failed: $target"
        if [[ ! -d "$workdir/squashfs-root" ]]; then
            die "appimage $target: --appimage-extract produced no squashfs-root"
        fi
        mv "$workdir/squashfs-root" "$ENV_DIR/$extract_dir"
    fi

    info "install $target"
}

# parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            --only)
                [[ $# -ge 2 ]] || die "--only requires a name"
                ONLY="$2"
                shift 2
                ;;
            *)
                die "unknown option: $1"
                ;;
        esac
    done
}

# reject a malformed manifest row, naming it
validate_row() {
    local line="$1" target="$2" kind="$3" sha="$4" option="$5"
    case "$kind" in
        sdk|tarball|appimage|file) ;;
        *) die "bad row: $line - unknown kind '$kind'" ;;
    esac
    if [[ ! "$sha" =~ ^[0-9a-f]{64}$ ]]; then
        die "bad row: $line - sha256 is not 64 hex characters"
    fi
    case "$kind" in
        tarball)
            if [[ -z "$option" || "$option" == "-" ]]; then
                die "bad row: $line - kind 'tarball' needs an option, not '-'"
            fi
            ;;
        sdk|file)
            if [[ "$option" != "-" ]]; then
                die "bad row: $line - kind '$kind' needs option '-'"
            fi
            ;;
        appimage)
            if [[ "$option" != "-" && ! "$option" =~ ^extract=.+$ ]]; then
                die "bad row: $line - kind 'appimage' option must be '-' or 'extract=<dir>'"
            fi
            ;;
    esac
}

main() {
    parse_args "$@"

    [[ -f "$BINARIES_MANIFEST" ]] || die "manifest not found: $BINARIES_MANIFEST"

    local line target kind url sha option
    local bin_dir="bin" bin_dir_set=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ -z "$line" || "$line" == \#* ]]; then
            continue
        fi
        if ! awk -F '\t' 'NF != 5 { exit 1 }' <<< "$line"; then
            die "bad row (expected 5 tab-separated columns): $line"
        fi
        IFS=$'\t' read -r target kind url sha option <<< "$line"
        validate_row "$line" "$target" "$kind" "$sha" "$option"
        if [[ "$bin_dir_set" -eq 0 && ( "$kind" == "tarball" || "$kind" == "file" ) ]]; then
            bin_dir="$(dirname "$target")"
            bin_dir_set=1
        fi
        install_row "$target" "$kind" "$url" "$sha" "$option"
    done < "$BINARIES_MANIFEST"

    # links live in the bin directory the manifest installs into
    if [[ "$DRY_RUN" -eq 0 && -z "$ONLY" ]]; then
        mkdir -p "$ENV_DIR/$bin_dir"
        create_link "$bin_dir/sysboard" "../scripts/tools/sysboard.sh"
        create_link "$bin_dir/wemux" "../local/wemux/wemux"
        local name
        for name in monitor-switch birch send_flashing tree zellij; do
            create_link "$bin_dir/$name" "../scripts/tools/$name"
        done
        create_link "$bin_dir/nvim" "nvim-appimage/usr/bin/nvim"
    fi

    if [[ "${#MISSING_TARGETS[@]}" -gt 0 ]]; then
        warn "not installed (download disabled): ${MISSING_TARGETS[*]}"
        exit 3
    fi
    info "done"
    exit 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi

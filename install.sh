#!/bin/bash

usage(){
    echo "usage: $0 --prefix /foo/bar" >&2
    exit 1
}

prefix=/usr/local
be_quiet=0
while [ $# -gt 0 ]; do
    if [ "$1" = "--quiet" ]; then
        be_quiet=1
        shift
    elif [ "$1" = "--prefix" ]; then
        shift
        if [ $# -gt 0 ]; then
            prefix="$1"
            shift
        else
            usage
        fi
    else
        case "$1" in
            --*=*)
                arg=${1%%=*}
                prefix=${1##*=}
                if [ "$arg" != "--prefix" ]; then
                    usage
                fi
                shift
                ;;
            *)
                usage ;;
        esac
    fi
done

if [ ! -e "$prefix" ]; then
    if ! mkdir -p "$prefix" ; then
        echo "$prefix doesn't exist and it can't be created" >&2
        exit 1
    fi
else
    if [ ! -d "$prefix" ]; then
        echo "$prefix does exist, but is not a directory" >&2
        exit 1
    fi
fi

prefix="$(readlink -f "$prefix")"
if [ -z "$prefix" ] || [ ! -d "$prefix" ]; then
    echo "$prefix doesn't exist or is not a directory" >&2
    exit 1
fi

prefix="$(cygpath "$prefix")"
if [ -z "$prefix" ] || [ ! -d "$prefix" ]; then
    usage
fi


dir="$(dirname "$0")"
cd "$dir"
dir="$(readlink -f .)"
if [ -z "$dir" ] || [ ! -d "$dir" ]; then
    echo "can't find script folder" >&2
    exit 1
fi


set -eu

if [ ! -x /usr/bin/cygcheck ] ; then
    echo "warning: your cygwin installation is probably corrupted" >&2
else
    xtmpf="$(mktemp)"
    trap "rm -f \"${xtmpf}\"" EXIT
    /usr/bin/cygcheck -dc >"${xtmpf}"
    for f in git unzip rsync patch diffutils make m4 ; do
        if ! grep -q "^${f} " "$xtmpf" ; then
            echo "warning: ${f} not installed. opam will not work without it!" >&2
        fi
    done
    if ! /usr/bin/grep -q "^curl " "$xtmpf" ; then
        if ! /usr/bin/grep -q "^wget " "$xtmpf" ; then
            echo "warning: neither curl nor wget are installed!" >&2
            echo "pleas install at least on of them" >&2
        fi
    fi
    if ! /usr/bin/grep -q "^mingw64-i686-gcc-core" "$xtmpf" ; then
        if ! /usr/bin/grep -q "^mingw64-x86_64-gcc-core " "$xtmpf" ; then
            echo "please install either mingw64-i686-gcc-core (32-bit) or mingw64-x86_64-gcc-core (64-bit)" >&2
            echo "you need a working C compiler to compile native ocaml programs" >&2
        fi
    fi
fi

orig_dir=$dir

failed=
add_failed(){
    if [ -z "$failed" ]; then
        failed="$1"
    else
        failed="$failed $1"
    fi
}
exit_failed(){
    if [ -n "$failed" ]; then
        echo "the following programs are not installed properly:" >&2
        echo " $failed" >&2
        echo "I can't proceed :(" >&2
        exit 2
    fi
}

set +e
for prog in bash cp curl cygpath diff git grep gzip m4 make mount mv patch rsync tar timeout xz ; do
    if ! "$prog" --version >/dev/null 2>&1 ; then
        add_failed "$prog"
    fi
done

if ! openssl help >/dev/null 2>&1 ; then
    add_failed "openssl"
fi


if ! unzip -h >/dev/null 2>&1 ; then
    add_failed "unzip"
fi

if ! dash -ec '/bin/true' >/dev/null 2>&1 ; then
    add_failed "dash"
fi
if ! /usr/bin/timeout -s SIGTERM -k 1s 30.0s curl --insecure --retry 2 --head "https://github.com" >/dev/null 2>&1 ; then
    add_failed "curl"
fi
exit_failed

tdir="$(mktemp -d)"
if [ -z "$tdir" ] || [ ! -d "$tdir" ]; then
    add_failed "mktemp"
    exit_failed
fi
tdir="$(readlink -f "$tdir")"
if [ -z "$tdir" ] || [ ! -d "$tdir" ]; then
    add_failed "readlink"
    exit_failed
fi

tdirclean(){
    rm -rf "$tdir"
}
trap tdirclean EXIT

set -e
cd "$tdir"
echo "test" >test
if ! tar -cf- test 2>/dev/null | xz >/dev/null 2>&1 ; then
    add_failed "tar / xz"
    exit_failed
fi
rm test

git_repo='github.com/fdopen/opam-repository-mingw.git'
git_test='github.com/fdopen/installer-test-repo.git'
mirror=
for proto in 'https://' 'git://' 'http://' ; do
    if /usr/bin/timeout -s SIGTERM -k 1s 30.0s git clone -q "${proto}${git_test}" >/dev/null 2>&1 ; then
        mirror="${proto}${git_repo}"
        break
    fi
    rm -rf installer-*  >/dev/null 2>&1 || true
done
if [ -z "$mirror" ]; then
    add_failed "git"
    exit_failed
fi
if [ ! -f "installer-test-repo/README.md" ]; then
    add_failed "git"
    exit_failed
fi

if [ "$proto" != 'https://' ]; then
    echo "warning: git doesn't seem to support https" >&2
    echo "$proto will be used instead" >&2
    echo "There is probably something wrong with your cygwin installation" >&2
fi

cd "$orig_dir"

if ! mkdir -p "${prefix}/bin" "${prefix}/include"  "${prefix}/etc" "${prefix}/lib/flexdll" ; then
    echo "No write access at ${prefix}. Please choose a different location: ${0} --prefix /folder/too" >&2
    exit 1
fi

cd bin
if ! /usr/bin/install -m 0755 ocaml-env.exe ocaml-env-win.exe aspcud.exe clasp.exe gringo.exe cudf2lp.exe opam.exe opam-installer.exe flexlink.exe "${prefix}/bin" ; then
    echo "No write access at ${prefix}/bin. Please choose a different location: ${0} --prefix /folder/too" >&2
    exit 1
fi

for d in * ; do
    [ ! -d "$d" ] && continue
    if ! mkdir -p "${prefix}/bin/${d}" ; then
        echo "No write access at ${prefix}. Please choose a different location: ${0} --prefix /folder/too" >&2
        exit 1
    fi
    cd "$d"
    for f in * ; do
        [ ! -f "$f" ] && continue
        case "$f" in
            *.dll)
                /usr/bin/install -m 0755 "$f" "${prefix}/bin/${d}"
                ;;
            *)
                /usr/bin/install -m 0644 "$f" "${prefix}/bin/${d}"
                ;;
        esac
    done
    cd ..
    break
done

/usr/bin/install -m 0644 misc2012.lp specification.lp "${prefix}/bin"
cd ..

if ! /usr/bin/install -m 0644 include/flexdll.h "${prefix}/include" ; then
    echo "No write access at ${prefix}/bin. Please choose a different location: ${0} --prefix /folder/too" >&2
    exit 1
fi
cd lib/flexdll
for f in * ; do
    if [ ! "$f" ]; then
        continue
    fi
    case "$f" in
        *mingw64test*)
            if ! /usr/bin/install -m 0755 "${f}" "${prefix}/lib/flexdll/${f}" ; then
                echo "No write access at ${prefix}/bin. Please choose a different location: ${0} --prefix /folder/lib/flexdll" >&2
                exit 1
            fi
            ;;
        *)
            if ! /usr/bin/install -m 0644 "${f}" "${prefix}/lib/flexdll/${f}" ; then
                echo "No write access at ${prefix}/bin. Please choose a different location: ${0} --prefix /folder/lib/flexdll" >&2
                exit 1
            fi
            ;;
    esac
done

if [ $be_quiet -eq 1 ]; then
    exit 0
fi

current_comp='4.11.1+mingw'
/usr/bin/cat - <<EOF
opam is now installed. In order to compile and install OCaml, proceed with either
\$ opam init default "${mirror}#opam2" -c "ocaml-variants.${current_comp}32" --disable-sandboxing
or
\$ opam init default "${mirror}#opam2" -c "ocaml-variants.${current_comp}64" --disable-sandboxing

Alternatively, you can download and use a pre-compiled version with: (note the 'c' suffix)
\$ opam init default "${mirror}#opam2" -c "ocaml-variants.${current_comp}32c" --disable-sandboxing
or
\$ opam init default "${mirror}#opam2" -c "ocaml-variants.${current_comp}64c" --disable-sandboxing
EOF

#!/usr/bin/env bash

set -Eeuo pipefail

cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source common/functions-build.sh

arg_flag FORCE f/force "force rebuild nginx source code"
arg_finish "$@"

info "starting..."

BUILDER=$(create_if_not nginx-build-worker fedora)
BUILDER_MNT=$(buildah mount $BUILDER)

info "init compile..."

buildah run $BUILDER dnf install --setopt=max_parallel_downloads=10 -y $(<requirements/build.lst)
info "dnf install complete..."

if [[ ! -e "$BUILDER_MNT/opt/dist/usr/sbin/nginx" ]] || [[ -n "$FORCE" ]] ; then
    buildah copy $BUILDER source "/opt/source"
    cat tools/build-nginx.sh | buildah run $BUILDER bash
    info "nginx build complete..."
else
    info "nginx already built, skip..."
fi

RESULT=$(new_container "nginx-result-worker" scratch)
RESULT_MNT=$(buildah mount $RESULT)
info "result image prepared..."

cp -r "$BUILDER_MNT/opt/dist/." "$RESULT_MNT"
cp    "tools/run-nginx.sh" "$RESULT_MNT/usr/sbin/nginx.sh"
chmod a+x "$RESULT_MNT/usr/sbin/nginx.sh"
info "built content moved..."

mkdir -p "$RESULT_MNT/etc/nginx"
cp -r config/* "$RESULT_MNT/etc/nginx"
info "config files created..."

buildah umount "$BUILDER" "$RESULT"

buildah config --entrypoint '["/bin/bash"]' --cmd '/usr/sbin/nginx.sh' --env PATH="/bin:/usr/bin:/usr/sbin" \
	--port 80 --port 443 --port 80/udp --port 443/udp "$RESULT"
buildah config --volume /config --volume /etc/letsencrypt "$RESULT"
buildah config --author "GongT <admin@gongt.me>" --created-by "GongT" --label name=gongt/nginx "$RESULT"
info "settings update..."

buildah commit "$RESULT" gongt/nginx
info "Done!"

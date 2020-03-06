#!/usr/bin/env bash

set -Eeuo pipefail

cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
source common/functions-install.sh

arg_string + USERNAME u/user "basic auth username (*)"
arg_string + PASSWORD p/pass "basic auth password (*)"
arg_flag     CENSORSHIP censorship "is http/s port unavailable"
arg_finish "$@"


ENV_PASS=$(
	safe_environment \
		"USERNAME=$USERNAME" \
		"PASSWORD=$PASSWORD" \
		"CENSORSHIP=$CENSORSHIP"
)

create_unit nginx
unit_unit Description nginx - high performance web server
unit_podman_network_publish
unit_podman_arguments "$ENV_PASS"
unit_fs_bind config/nginx /config
unit_fs_bind logs/nginx /var/log/nginx
unit_fs_tempfs 1M /run
unit_fs_tempfs 512M /tmp
unit_fs_bind share/nginx /config.auto
unit_fs_bind share/letsencrypt /etc/letsencrypt
unit_fs_bind share/sockets /run/sockets
unit_reload_command '/usr/bin/podman exec nginx nginx -s reload'
unit_finish

#!/bin/bash

set -Eeuo pipefail

if ! [[ -e "/etc/letsencrypt/nginx/load.conf" ]]; then
    mkdir -p /etc/letsencrypt/nginx
    echo > "/etc/letsencrypt/nginx/load.conf"
fi

erun () {
	echo " + $*" >&2
	"$@"
}
cd /etc/nginx/basic
if [[ -n "$CENSORSHIP" ]] ; then
	for i in *.conf ; do
		erun sed -i 's#$out_port_https#:59443#g' "$i"
	done
else
	for i in *.conf ; do
		erun sed -i 's#$out_port_https##g; s/listen 59/# listen 59/g' "$i"
	done
fi

if [[ -e "/config/htpasswd" ]]; then
    rm -f "/config/htpasswd"
fi
echo "create htpassword file..." >&2
htpasswd -bc "/config/htpasswd" "$USERNAME" "$PASSWORD"

for i in vhost.d stream.d rtmp.d ; do
    if ! [[ -e "/config/$i" ]]; then
        echo "create /config/$i folder..." >&2
        mkdir -p "/config/$i"
    fi
    if ! [[ -e "/config.auto/$i" ]]; then
        echo "create /config.auto/$i folder..." >&2
        mkdir -p "/config.auto/$i"
    fi
done

echo "[***] running nginx." >&2

rm -f /run/sockets/nginx.reload.sock
exec /usr/sbin/nginx

#!/usr/bin/env bash

set -Eeuo pipefail

DST=/opt/dist
rm -rf "$DST"
mkdir -p "$DST"

### TODO: 通过安装系统自带的nginx，运行nginx -V看原本的编译参数

cd "/opt/source/luajit2" && echo "=== install '$(basename "$(pwd)")'..."
export LUAJIT_LIB=/usr/lib64
export LUAJIT_INC=/usr/include/luajit-2.1
make clean
make MULTILIB=lib64 PREFIX=/usr -j
make MULTILIB=lib64 PREFIX=/usr "INSTALL_INC=$LUAJIT_INC" "INSTALL_JITLIB=$DST/usr/share/lua/5.1" install
if ! [[ -e /usr/bin/lua ]]; then
	ln -s luajit /usr/bin/lua
fi

cd "/opt/source/resty/lua-resty-core" && echo "=== install '$(basename "$(pwd)")'..."
make "DESTDIR=$DST" LUA_LIB_DIR=/usr/share/lua/5.1 PREFIX=/usr install
cd "/opt/source/resty/lua-resty-lrucache" && echo "=== install '$(basename "$(pwd)")'..."
make "DESTDIR=$DST" LUA_LIB_DIR=/usr/share/lua/5.1 PREFIX=/usr install

cd "/opt/source/lua/luaposix" && echo "=== install '$(basename "$(pwd)")'..."
# LUA_LIBDIR
./build-aux/luke "LUA_INCDIR=$LUAJIT_INC" "PREFIX=$DST/usr/local" LUAVERSION=5.1
./build-aux/luke "LUA_INCDIR=$LUAJIT_INC" "PREFIX=$DST/usr/local" LUAVERSION=5.1 install

cd "/opt/source/nginx" && echo "=== install '$(basename "$(pwd)")'..."

export CC_OPT='-O2 -g -pipe -Wall -Werror=format-security -Wp,-D_FORTIFY_SOURCE=2 -Wp,-D_GLIBCXX_ASSERTIONS -fexceptions -fstack-protector-strong -grecord-gcc-switches -m64 -mtune=generic -fasynchronous-unwind-tables -fstack-clash-protection -Wno-error'
export LD_OPT='-Wl,-z,defs -Wl,-z,now -Wl,-z,relro -Wl,-E'

MODULES=()
for REL_FOLDER in ../modules/*/
do
	MODULES+=("--add-module=$REL_FOLDER")
done

OTHER_MODULES=()
OTHER_MODULES+=("--add-module=../special-modules/njs/nginx")

./auto/configure \
	"${MODULES[@]}" \
	"${OTHER_MODULES[@]}" \
	'--prefix=/usr/' \
	'--sbin-path=/usr/sbin' \
	'--modules-path=/usr/nginx/modules' \
	'--conf-path=/etc/nginx/nginx.conf' \
	'--error-log-path=/var/log/error.log' \
	'--http-log-path=/var/log/access.log' \
	'--http-client-body-temp-path=/tmp/client_body' \
	'--http-proxy-temp-path=/tmp/proxy' \
	'--http-fastcgi-temp-path=/tmp/fastcgi' \
	'--http-uwsgi-temp-path=/tmp/uwsgi' \
	'--http-scgi-temp-path=/tmp/scgi' \
	'--pid-path=/run/nginx.pid' \
	'--lock-path=/run/lock/subsys/nginx' \
	'--user=nginx' \
	'--group=nginx' \
	'--with-compat' \
	'--without-select_module' \
	'--without-poll_module' \
	'--with-threads' \
	'--with-file-aio' \
	'--with-http_ssl_module' \
	'--with-http_v2_module' \
	'--with-http_realip_module' \
	'--with-http_addition_module' \
	'--with-http_xslt_module' \
	'--with-http_xslt_module' \
	'--with-http_image_filter_module' \
	'--with-http_geoip_module' \
	'--with-http_sub_module' \
	'--with-http_dav_module' \
	'--with-http_flv_module' \
	'--with-http_mp4_module' \
	'--with-http_gunzip_module' \
	'--with-http_gzip_static_module' \
	'--with-http_auth_request_module' \
	'--with-http_random_index_module' \
	'--with-http_secure_link_module' \
	'--with-http_degradation_module' \
	'--with-http_slice_module' \
	'--with-http_stub_status_module' \
	'--with-stream' \
	'--with-stream_ssl_module' \
	'--with-stream_realip_module' \
	'--with-stream_geoip_module' \
	'--with-stream_ssl_preread_module' \
	'--with-google_perftools_module' \
	'--with-pcre' \
	'--with-pcre-jit' \
	'--with-libatomic' \
	'--with-debug' \
	"--with-cc-opt=$CC_OPT" \
	"--with-ld-opt=$LD_OPT"

make BUILDTYPE=Debug -j

mkdir -p $DST/usr/sbin

make DESTDIR=$DST install

rm -rf $DST/etc
mkdir -p $DST/etc/nginx

#######
function copy_binary() {
	echo "copy binary $1"
	for i in $(ldd "$1" | grep '=>' | awk '{print $3}') ; do
		if [[ "$i" == not ]]; then
			ldd "$1"
			echo 'Failed to resolve some dependencies of nginx.' >&2 ; exit 1
		fi

		mkdir -p "$(dirname "$DST/$i")"
		cp -vu "$i" $(echo "$DST/$i" | sed 's#/lib/#/lib64/#g' )
	done

	for i in $(ldd "$1" | grep -v '=>' | awk '{print $1}') ; do
		if [[ "$i" =~ linux-vdso* ]]; then
			continue
		fi
		mkdir -p "$(dirname "$DST/$i")"
		cp -vu "$i" $(echo "$DST/$i" | sed 's#/lib/#/lib64/#g' )
	done
}

copy_binary /opt/dist/usr/sbin/nginx
copy_binary /usr/bin/htpasswd
copy_binary /bin/bash
copy_binary /bin/mkdir
copy_binary /usr/bin/sed

for i in /lib64/libnss_{compat*,dns*,files*,myhostname*,resolve*} ; do
	cp -uv "$i" "$DST/$i"
done

mkdir -p "$DST/bin" "$DST/usr/bin"

cp /bin/bash /bin/mkdir /bin/rm "$DST/bin"
cp /usr/bin/htpasswd /usr/bin/sed "$DST/usr/bin"

mkdir -p "$DST/etc"
echo "nameserver 8.8.8.8
nameserver 1.1.1.1
" > "$DST/etc/resolv.conf"

echo "create openssl cert..."
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -batch \
	-keyout "$DST/etc/nginx/selfsigned.key" \
	-out "$DST/etc/nginx/selfsigned.crt"

cp /etc/passwd /etc/group /etc/nsswitch.conf "$DST/etc"

echo "Done."

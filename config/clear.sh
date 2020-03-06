#!/bin/bash

cd /etc/nginx
rm -vf *.default *.rpmnew koi-* win-*
rm -vf scgi_params fastcgi.conf

reperm /etc/nginx
chmod a+x $BASH_SOURCE

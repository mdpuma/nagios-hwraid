#!/bin/bash

ver=0.3

# deb package
fpm -t deb -s dir -C deb -n nagios-hwraid \
	-d sudo -d nagios-nrpe-server \
	--post-install after_install -v $ver -e

# rpm package
fpm -t rpm -s dir -C rpm -n nagios-hwraid \
	-d sudo -d nrpe -d nagios-plugins \
	--post-install after_install -v $ver -e

#!/bin/bash

for i in deb rpm; do
    chmod +x $i/usr/*
done

# deb package
fpm -t deb -s dir -C deb -n nagios-hwraid -d sudo -v 0.1 -e

# rpm package
fpm -t rpm -s dir -C rpm -n nagios-hwraid -d sudo -v 0.1 -e

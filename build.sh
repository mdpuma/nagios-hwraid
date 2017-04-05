#!/bin/bash

# deb package
fpm -t deb -s dir -C root -n nagios-hwraid -v 0.1 -e

# rpm package
fpm -t rpm -s dir -C root -n nagios-hwraid -v 0.1 -e

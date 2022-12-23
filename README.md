# About 
NetApp Monitoring over REST-API (Nagios, Icinga, CheckMK, etc.)

New and improved Version of Nagios Checks via ZAPI (https://github.com/aleex42/netapp-cdot-nagios) because ZAPI support will end with ONTAP 9.13.1 and later.

# Plugins

Currently there are the following checks:

* check_aggr: Aggregate Space Usage (also supports performance data)

# Requirements (Debian / Ubuntu)

> apt install libio-socket-ssl-perl liblwp-protocol-https-perl libjson-xs-perl


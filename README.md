# About 
NetApp Monitoring over REST-API (Nagios, Icinga, CheckMK, etc.)

New and improved Version of Nagios Checks via ZAPI (https://github.com/aleex42/netapp-cdot-nagios) because ZAPI support will end with ONTAP 9.13.1 and later.

# ONTAP Version support

These scripts will only work with ONTAP 9.8 or later

# Plugins

Currently there are the following checks:

* check_aggr: Aggregate Space Usage (also supports performance data)

# Requirements (Debian / Ubuntu)

> apt install libio-socket-ssl-perl liblwp-protocol-https-perl libjson-xs-perl

# Contact / Author

Alexander Krogloth
<git at krogloth.de>

# License

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (GPL). If you
did not receive this file, see http://www.gnu.org/licenses/gpl.txt.

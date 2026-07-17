## About 
NetApp ONTAP Monitoring based on REST-API for Nagios, Icinga, CheckMK, etc.

New and improved Version of Nagios Checks via ZAPI (https://github.com/aleex42/netapp-cdot-nagios) because ZAPI support will end with ONTAP 9.13.1 and later.

## ONTAP Version support

These scripts will only work with ONTAP 9.6 or later

## Plugins

Currently there are the following checks:

* check_aggr: Aggregate Space Usage (also supports performance data)
* check_volume: Volume Space & Inode Usage (also supports performance data)
* check_lun: Lun Usage (also supports performance data)
* check_health_sensors: Check Basic Health Sensors of the system (no perf data)
* check_disks: Check disks status (no perf data)
* check_s3_bucket: Check S3 Bucket space usage (also supports performance data)

## Requirements (Debian / Ubuntu)

```
apt install libio-socket-ssl-perl liblwp-protocol-https-perl libjson-xs-perl
```

## Usage examples

```
./check_aggr.pl --hostname 192.168.178.56 --username USER --password PW --warning 80 --critical 90 --perf
```

```
OK: aggr1 (0%), aggr2 (0%)| aggr1=1159168B;76080644096;85590724608;0;95100805120 aggr2=1654784B;114131369984;128397791232;0;142664212480
```

```
./check_aggr.pl --hostname 192.168.178.56 --username USER --password PW --warning 80 --critical 90
```

```
OK: aggr1 (0%), aggr2 (0%)
```

```
./check_s3_bucket.pl --hostname 192.168.178.56 --username USER --password PW --warning 75 --critical 90 --perf
```
 
```
OK: svm1:backup-prod (45.00 GB/100.00 GB, 45.00%)|Bucket_count::check_s3_bucket_count::count=1;;;0;; ...
```


## Contact / Author

Alexander Krogloth (git at krogloth.de)

Daniel Heß (Daniel.Hess at roland-rechtsschutz.de)

Andraz Kopac

Manuel Sonder (Nemester)

# License

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (GPL). If you
did not receive this file, see http://www.gnu.org/licenses/gpl.txt.

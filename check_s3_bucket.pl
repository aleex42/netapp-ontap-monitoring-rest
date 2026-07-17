#!/usr/bin/perl
 
# nagios: -epn
# --
# check_s3_bucket - Check NetApp ONTAP S3 Bucket Space Usage
# --
# Companion script for https://github.com/aleex42/netapp-ontap-monitoring-rest
# Written in the same style as check_volume.pl from that repo, using the
# ONTAP REST endpoint /api/protocols/s3/buckets (size + logical_used_size).
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see http://www.gnu.org/licenses/gpl.txt.
# --
 
use strict;
use warnings;
use Getopt::Long;
use IO::Socket::SSL qw();
use LWP;
use JSON::XS;
use Try::Tiny;
use Data::Dumper;
 
sub json_from_call;
 
Getopt::Long::Configure('bundling');
 
GetOptions(
	'H|hostname=s'          => \my $Hostname,
	'u|username=s'          => \my $Username,
	'p|password=s'          => \my $Password,
	'w|warning=i'           => \my $Warning,
	'c|critical=i'          => \my $Critical,
	'P|perf'                => \my $perf,
	'B|bucket=s'            => \my $Bucket,
	'bucketlist=s'          => \my @bucketlistarray,
	'vserver=s'             => \my $Vserver,
	'exclude=s'             => \my @excludelistarray,
	'regexp'                => \my $regexp,
	'perfdatadir=s'         => \my $perfdatadir,
	'perfdataservicedesc=s' => \my $perfdataservicedesc,
	'hostdisplay=s'         => \my $hostdisplay,
	'h|help'                => sub { exec perldoc => -F => $0 or die "Cannot execute perldoc: $!\n"; },
) or Error("$0: Error in command line arguments\n");
 
my $ua = LWP::UserAgent->new(
	ssl_opts => {
		'verify_hostname' => 0,
		'SSL_verify_mode' => IO::Socket::SSL::SSL_VERIFY_NONE,
	},
);
 
my %Bucketlist;
@bucketlistarray = map { split /,/ } @bucketlistarray;
@Bucketlist{@bucketlistarray} = ();
my $bucketliststr = join "|", @bucketlistarray;
 
my %Excludelist;
@excludelistarray = map { split /,/ } @excludelistarray;
@Excludelist{@excludelistarray} = ();
my $excludeliststr = join "|", @excludelistarray;
 
sub Error {
	print "$0: " . $_[0] . "\n";
	exit 2;
}
 
Error('Option --hostname needed!') unless $Hostname;
Error('Option --username needed!') unless $Username;
Error('Option --password needed!') unless $Password;
 
use Time::HiRes qw();
my $STARTTIME_HR = Time::HiRes::time();
my $STARTTIME     = sprintf( "%.0f", $STARTTIME_HR );
 
$perf = 0 unless $perf;
 
# Set some conservative default thresholds
$Warning  = 75 unless $Warning;
$Critical = 90 unless $Critical;
 
sub perfdata_to_file {
	# write perfdata to a spoolfile in perfdatadir instead of in plugin output
	my ( $s_starttime, $s_perfdatadir, $s_hostdisplay, $s_perfdataservicedesc, $s_perfdata ) = @_;
 
	if ( !$s_perfdataservicedesc ) {
		if ( defined $ENV{'NAGIOS_SERVICEDESC'} and $ENV{'NAGIOS_SERVICEDESC'} ne "" ) {
			$s_perfdataservicedesc = $ENV{'NAGIOS_SERVICEDESC'};
		} elsif ( defined $ENV{'ICINGA_SERVICEDESC'} and $ENV{'ICINGA_SERVICEDESC'} ne "" ) {
			$s_perfdataservicedesc = $ENV{'ICINGA_SERVICEDESC'};
		} else {
			print "UNKNOWN: please specify --perfdataservicedesc when you want to use --perfdatadir to output perfdata.";
			exit 3;
		}
	}
 
	if ( !$s_hostdisplay ) {
		if ( defined $ENV{'NAGIOS_HOSTNAME'} and $ENV{'NAGIOS_HOSTNAME'} ne "" ) {
			$s_hostdisplay = $ENV{'NAGIOS_HOSTNAME'};
		} elsif ( defined $ENV{'ICINGA_HOSTDISPLAYNAME'} and $ENV{'ICINGA_HOSTDISPLAYNAME'} ne "" ) {
			$s_hostdisplay = $ENV{'ICINGA_HOSTDISPLAYNAME'};
		} else {
			print "UNKNOWN: please specify --hostdisplay when you want to use --perfdatadir to output perfdata.";
			exit 3;
		}
	}
 
	my $s_perfoutput;
	$s_perfoutput .= "DATATYPE::SERVICEPERFDATA\tTIMET::" . $s_starttime;
	$s_perfoutput .= "\tHOSTNAME::" . $s_hostdisplay;
	$s_perfoutput .= "\tSERVICEDESC::" . $s_perfdataservicedesc;
	$s_perfoutput .= "\tSERVICEPERFDATA::" . $s_perfdata;
	$s_perfoutput .= "\n";
 
	my $filename = $s_perfdatadir . "/check_s3_bucket.$s_starttime";
	umask "0000";
	open( OUT, ">>$filename" ) or die "cannot open $filename $!";
	flock( OUT, 2 ) or die "cannot flock $filename ($!)";
	print OUT $s_perfoutput;
	close(OUT);
}
 
my ( @crit_msg, @warn_msg, @ok_msg );
my %perfdata = ();
my $bucket_count = 0;
 
my $json;
if ($Bucket) {
	$json = json_from_call( "/protocols/s3/buckets?name=$Bucket&fields=svm,size,logical_used_size,volume" );
} else {
	$json = json_from_call( "/protocols/s3/buckets?fields=svm,size,logical_used_size,volume" );
}
 
my $buckets = $json->{'records'};
 
# --- Fallback handling for a bucket name that can't be found ------------
# Without this, a missing bucket would silently fall through to "no
# bucket found" further down and get reported as a generic WARNING.
# Report it explicitly and as UNKNOWN, since this is a config/lookup
# problem rather than a real threshold breach.
 
if ( $Bucket && !@$buckets ) {
	print "UNKNOWN: bucket '$Bucket' not found on $Hostname.\n";
	exit 3;
}
 
if ( @bucketlistarray && !$regexp ) {
	my %all_names_seen = map { $_->{'name'} => 1 } @$buckets;
	my @missing = grep { !exists $all_names_seen{$_} } @bucketlistarray;
 
	if (@missing) {
		print "UNKNOWN: requested bucket(s) not found: " . join( ", ", @missing ) . "\n";
		exit 3;
	}
}
# -------------------------------------------------------------------------
 
foreach my $bkt ( sort { $a->{name} cmp $b->{name} } @$buckets ) {
 
	my $svm_name    = $bkt->{'svm'}->{'name'};
	my $bucket_name = $bkt->{'name'};
 
	if ($Vserver) {
		next if ( $svm_name ne $Vserver );
	}
 
	if (@bucketlistarray) {
		if ($regexp) {
			next unless ( $bucket_name =~ m/$bucketliststr/ );
		} else {
			next unless exists $Bucketlist{$bucket_name};
		}
	}
 
	next if exists $Excludelist{$bucket_name};
 
	if ( $regexp and $excludeliststr ) {
		next if ( $bucket_name =~ m/$excludeliststr/ );
	}
 
	my $size = $bkt->{'size'};
	my $used = $bkt->{'logical_used_size'};
 
	# Skip buckets without a usable quota (avoid div by zero)
	next unless $size;
 
	my $percent = sprintf( "%.2f", $used / $size * 100 );
 
	$perfdata{$bucket_name}{'byte_used'}  = $used;
	$perfdata{$bucket_name}{'byte_total'} = $size;
	$perfdata{$bucket_name}{'svm'}        = $svm_name;
 
	my $space_used  = $used / 1073741824;
	my $space_total = $size / 1073741824;
 
	if ( $space_total > 1024 ) {
		$space_used  /= 1024;
		$space_total /= 1024;
		$space_used  = sprintf( "%.2f TB", $space_used );
		$space_total = sprintf( "%.2f TB", $space_total );
	} else {
		$space_used  = sprintf( "%.2f GB", $space_used );
		$space_total = sprintf( "%.2f GB", $space_total );
	}
 
	my $label = "$svm_name:$bucket_name";
 
	if ( $percent >= $Critical ) {
		push( @crit_msg, "$label ($space_used/$space_total, $percent%[>=$Critical%])" );
	} elsif ( $percent >= $Warning ) {
		push( @warn_msg, "$label ($space_used/$space_total, $percent%[>=$Warning%])" );
	} else {
		push( @ok_msg, "$label ($space_used/$space_total, $percent%)" );
	}
 
	$bucket_count++;
}
 
my $perfdataglobalstr = @bucketlistarray
	? sprintf( "Bucket_count::check_s3_bucket_count::count=%d;;;0;;", $bucket_count )
	: "";
my $perfdatabucketstr = "";
 
foreach my $bkt ( keys(%perfdata) ) {
	$perfdatabucketstr .= sprintf(
		" Bucket_%s::check_s3_bucket_usage::space_used=%dB;%d;%d;%d;%d",
		$bkt,
		$perfdata{$bkt}{'byte_used'},
		$Warning * $perfdata{$bkt}{'byte_total'} / 100,
		$Critical * $perfdata{$bkt}{'byte_total'} / 100,
		0,
		$perfdata{$bkt}{'byte_total'}
	);
	$perfdatabucketstr .= sprintf( " data_total=%dB", $perfdata{$bkt}{'byte_total'} );
}
$perfdatabucketstr =~ s/^\s+//;
 
my $perfdataallstr = join( " ", grep { length $_ } ( $perfdataglobalstr, $perfdatabucketstr ) );
 
if ( scalar(@crit_msg) ) {
	print "CRITICAL: ";
	print join( " ", @crit_msg, @warn_msg );
	if ($perf) {
		if ($perfdatadir) {
			perfdata_to_file( $STARTTIME, $perfdatadir, $hostdisplay, $perfdataservicedesc, $perfdataallstr );
			print "|$perfdataglobalstr\n";
		} else {
			print "|$perfdataallstr\n";
		}
	} else {
		print "|\n";
	}
	exit 2;
} elsif ( scalar(@warn_msg) ) {
	print "WARNING: ";
	print join( " ", @warn_msg );
	if ($perf) {
		if ($perfdatadir) {
			perfdata_to_file( $STARTTIME, $perfdatadir, $hostdisplay, $perfdataservicedesc, $perfdataallstr );
			print "|$perfdataglobalstr\n";
		} else {
			print "|$perfdataallstr\n";
		}
	} else {
		print "|\n";
	}
	exit 1;
} elsif ( scalar(@ok_msg) ) {
	print "OK: ";
	print join( " ", @ok_msg );
	if ($perf) {
		if ($perfdatadir) {
			perfdata_to_file( $STARTTIME, $perfdatadir, $hostdisplay, $perfdataservicedesc, $perfdataallstr );
			print "|$perfdataglobalstr\n";
		} else {
			print "|$perfdataallstr\n";
		}
	} else {
		print "|\n";
	}
	exit 0;
} else {
	print "UNKNOWN: no S3 bucket matched the given filters (hostname/vserver/exclude/bucketlist) - check for typos or overly narrow filters\n";
	exit 3;
}
 
sub json_from_call($) {
	my $url = shift;
	my $req = HTTP::Request->new( GET => "https://$Hostname/api$url" );
	$req->content_type("application/json");
	$req->authorization_basic( $Username, $Password );
	my $res = $ua->request($req);
	die $res->status_line unless $res->is_success;
 
	my $result_decoded;
	my $decode_error = 0;
	try {
		$result_decoded = JSON::XS::decode_json( $res->content );
	}
	catch {
		$decode_error = 1;
	};
	die "Could not decode JSON" if $decode_error;
 
	return $result_decoded;
}
 
__END__
 
=encoding utf8
 
=head1 NAME
 
check_s3_bucket - Check NetApp ONTAP S3 Bucket Space Usage
 
=head1 SYNOPSIS
 
check_s3_bucket.pl -H HOSTNAME -u USERNAME -p PASSWORD \
	-w PERCENT_WARNING -c PERCENT_CRITICAL \
	[--perfdatadir DIR] [--perfdataservicedesc SERVICE-DESC] \
	[--hostdisplay HOSTDISPLAY] [--vserver VSERVER-NAME] \
	[--bucketlist bucket1,bucket2] [--exclude BUCKET] [--regexp] \
	[-B BUCKET] [-P]
 
=head1 DESCRIPTION
 
Checks the space usage of NetApp ONTAP S3 buckets via the REST API
endpoint /protocols/s3/buckets (fields: size, logical_used_size) and
warns if warning or critical thresholds are reached. Written to slot
in alongside the other checks in
https://github.com/aleex42/netapp-ontap-monitoring-rest
 
=head1 OPTIONS
 
=over 4
 
=item -H | --hostname FQDN
 
The Hostname of the NetApp to monitor (Cluster or Node MGMT)
 
=item -u | --username USERNAME
 
The Login Username of the NetApp to monitor
 
=item -p | --password PASSWORD
 
The Login Password of the NetApp to monitor
 
=item -w | --warning PERCENT_WARNING
 
The Warning threshold for bucket space usage. Defaults to 75%.
 
=item -c | --critical PERCENT_CRITICAL
 
The Critical threshold for bucket space usage. Defaults to 90%.
 
=item -B | --bucket BUCKET
 
Optional: The name of a single bucket to check
 
=item --bucketlist bucket1,bucket2
 
Optional: list of buckets to check (checks ONLY these buckets). If --regexp is set,
this is treated as a single regular expression instead of an exact-name list (so it
acts as an include-pattern, the counterpart to --exclude).
 
=item --vserver VSERVER-NAME
 
Name of the destination vserver to be checked. If not specified, all vservers are checked.
 
=item --exclude BUCKET
 
Optional: name of a bucket to exclude from the checks (repeatable for multiple buckets)
 
=item --regexp
 
Optional: treat --bucketlist and/or --exclude as regular expressions instead of exact-name lists
 
=item -P | --perf
 
Flag for performance data output
 
=item --perfdatadir DIR
 
Optional: When specified, the performance data are written directly to a file in the specified location instead of
transmitted to Icinga/Nagios. Please use the same hostname as in Icinga/Nagios for --hostdisplay. Perfdata format is
for pnp4nagios currently.
 
=item --perfdataservicedesc SERVICE-DESC
 
(only used when using --perfdatadir). Service description to use in the generated performance data.
Should match what is used in the Nagios/Icinga configuration. Optional if environment macros are enabled in
nagios.cfg/icinga.cfg (enable_environment_macros=1).
 
=item --hostdisplay HOSTDISPLAY
 
(only used when using --perfdatadir). Specifies the host name to use for the perfdata. Optional if environment
macros are enabled in nagios.cfg/icinga.cfg (enable_environment_macros=1).
 
=item -help
 
=item -?
 
to see this Documentation
 
=back
 
=head1 EXIT CODE
 
3 on Unknown Error
 
2 if Critical Threshold has been reached
 
1 if Warning Threshold has been reached or any problem occurred
 
0 if everything is ok
 
=head1 AUTHORS
 
Manuel Sonder [https://github.com/Nemester]

Written to complement https://github.com/aleex42/netapp-ontap-monitoring-rest

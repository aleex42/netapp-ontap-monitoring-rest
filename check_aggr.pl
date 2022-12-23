#!/usr/bin/perl

# nagios: -epn
# --
# check_aggr - Check Aggregate real Space Usage
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
        'H|hostname=s'   => \my $Hostname,
    	'u|username=s' => \my $Username,
    	'p|password=s' => \my $Password,
    	'w|warning=i'  => \my $Warning,
    	'c|critical=i' => \my $Critical,
    	'A|aggr=s'     => \my $Aggr,
    	'P|perf'       => \my $perf,
    	'exclude=s'    =>  \my @excludelistarray,
    	'regexp'       => \my $regexp,
    	'h|help'       => sub { exec perldoc => -F => $0 or die "Cannot execute perldoc: $!\n"; },
) or Error("$0: Error in command line arguments\n");

my $ua = LWP::UserAgent->new(
    ssl_opts => {
        'verify_hostname' => 0,
        'SSL_verify_mode' => IO::Socket::SSL::SSL_VERIFY_NONE,
    },
);

my %Excludelist;
@Excludelist{@excludelistarray} = ();
my $excludeliststr = join "|", @excludelistarray;

sub Error {
    print "$0: ".$_[0]."\n";
    exit 2;
}
Error( 'Option --hostname needed!' ) unless $Hostname;
Error( 'Option --username needed!' ) unless $Username;
Error( 'Option --password needed!' ) unless $Password;
Error( 'Option --warning needed!' ) unless $Warning;
Error( 'Option --critical needed!' ) unless $Critical;

my $perfmsg = '';
my $critical = 0;
my $warning = 0;
my $ok = 0;
my $crit_msg;
my $warn_msg;
my $ok_msg;

my $json;

if($Aggr){
	$json = json_from_call( "/storage/aggregates?name=$Aggr&fields=space.block_storage.used,space.block_storage.size,space.block_storage.available,space.block_storage.physical_used_percent" );
} else {
	$json = json_from_call( "/storage/aggregates?fields=space.block_storage.used,space.block_storage.size,space.block_storage.available,space.block_storage.physical_used_percent" );
}

my $aggrs = $json->{'records'};

foreach my $aggr (sort { $a->{name} cmp $b->{name} } @$aggrs){

        my $aggr_name = $aggr->{'name'};

        # exclude root aggregates
        unless($aggr_name =~ m/^aggr0_/) {

            next if exists $Excludelist{$aggr_name};

            if ($regexp and $excludeliststr) {
                if ($aggr_name =~ m/.$excludeliststr/) {
                    next;
                }
            }

            my $space = $aggr->{'space'}->{'block_storage'};
            my $bytesused = $space->{'used'};
            my $bytesavail = $space->{'available'};
            my $bytestotal = $space->{'size'};
            my $percent = $space->{'physical_used_percent'};

            if($percent >= $Critical) {

                $critical++;

                if($crit_msg) {
                    $crit_msg .= ", " . $aggr_name . " (" . $percent . "%)";
                } else {
                    $crit_msg .= $aggr_name . " (" . $percent . "%)";
                }

            } elsif ($percent >= $Warning) {

                $warning++;

                if ($warn_msg) {
                    $warn_msg .= ", " . $aggr_name . " (" . $percent . "%)";
                } else {
                    $warn_msg .= $aggr_name . " (" . $percent . "%)";
                }
            } else {

                $ok++;

                if ($ok_msg) {
                    $ok_msg .= ", " . $aggr_name . " (" . $percent . "%)";
                } else {
                    $ok_msg .= $aggr_name . " (" . $percent . "%)";
                }
            }

            if ($perf) {

                my $warn_bytes = $Warning*$bytestotal/100;
                my $crit_bytes = $Critical*$bytestotal/100;

                $perfmsg .= " $aggr_name=${bytesused}B;$warn_bytes;$crit_bytes;0;$bytestotal";
            }
        }
}

if($critical > 0) {
    print "CRITICAL: $crit_msg\n\n";
    if($warning > 0) {
        print "WARNING: $warn_msg\n\n";
    }
    if($ok > 0) {
        print "OK: $ok_msg";
    }
    if($perf) {print"|" . $perfmsg;}
    print  "\n";
    exit 2;
} elsif($warning > 0) {
    print "WARNING: $warn_msg\n\n";
    if($ok > 0) {
        print "OK: $ok_msg";
    }
    if($perf) {print"|" . $perfmsg;}
    print  "\n";    
    exit 1;
} else {
    if($ok > 0) {
        print "OK: $ok_msg";
    } else {
        print "OK - but no output\n";
    }
    if($perf) {print"|" . $perfmsg;}    
    print  "\n";    
    exit 0;
}

sub json_from_call($) {

        # Parameter: z. B. "/cluster"
        my $url = shift;

        my $req = HTTP::Request->new( GET => "https://$Hostname/api$url" );
        $req->content_type( "application/json" );
        $req->authorization_basic( $Username, $Password );

        my $res = $ua->request( $req );
        die $res->status_line unless $res->is_success;

        my $result_decoded;
        my $decode_error = 0;
        try {
                $result_decoded = JSON::XS::decode_json( $res->content );
        }
        catch {
                $decode_error = 1;
        };

        die "Konnte JSON nicht dekodieren"  if  $decode_error;

        return $result_decoded;
}

__END__

=encoding utf8

=head1 NAME

check_cdot_aggr - Check Aggregate real Space Usage

=head1 SYNOPSIS

check_cdot_aggr.pl -H HOSTNAME -u USERNAME \
           -p PASSWORD -w PERCENT_WARNING \
           -c PERCENT_CRITICAL [--perf|-P] [--aggr AGGR]

=head1 DESCRIPTION

Checks the Aggregate real Space Usage of the NetApp System and warns
if warning or critical Thresholds are reached

=head1 OPTIONS

=over 4

=item -H | --hostname FQDN

The Hostname of the NetApp to monitor (Cluster or Node MGMT)

=item -u | --username USERNAME

The Login Username of the NetApp to monitor

=item -p | --password PASSWORD

The Login Password of the NetApp to monitor

=item -w | --warning PERCENT_WARNING

The Warning threshold

=item -c | --critical PERCENT_CRITICAL

The Critical threshold

=item -P | --perf

Flag for performance data output

=item -A | --aggr

Check only specific aggregate

=item --exclude

Optional: The name of an aggregate that has to be excluded from the checks (multiple exclude item for multiple aggregates)

=item -help

=item -?

to see this Documentation

=back

=head1 EXIT CODE

3 on Unknown Error
2 if Critical Threshold has been reached
1 if Warning Threshold has been reached
0 if everything is ok

=head1 AUTHORS

 Alexander Krogloth <git at krogloth.de>



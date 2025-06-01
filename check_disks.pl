#!/usr/bin/perl

# nagios: -epn
# --
# check_disks - Check disks status
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
#use Data::Dumper;
#use Data::Dump qw(dump);

sub json_from_call;

Getopt::Long::Configure('bundling');

GetOptions(
        'H|hostname=s'   => \my $Hostname,
    	'u|username=s' => \my $Username,
    	'p|password=s' => \my $Password,
    	'v|verbose'  => \my $Verbose,
    	'h|help'       => sub { exec perldoc => -F => $0 or die "Cannot execute perldoc: $!\n"; },
) or Error("$0: Error in command line arguments\n");

my $ua = LWP::UserAgent->new(
    ssl_opts => {
        'verify_hostname' => 0,
        'SSL_verify_mode' => IO::Socket::SSL::SSL_VERIFY_NONE,
    },
);

sub Error {
    print "$0: ".$_[0]."\n";
    exit 2;
}
Error( 'Option --hostname needed!' ) unless $Hostname;
Error( 'Option --username needed!' ) unless $Username;
Error( 'Option --password needed!' ) unless $Password;

my $critical = 0;
my $warning = 0;
my $ok = 0;
my $crit_msg = '';
my $warn_msg = '';
my $ok_msg = '';

my $json;

$json = json_from_call( "/storage/shelves?fields=uid,id" );
my $shelvesreq = $json->{'records'};
my %shelves = ();
foreach my $shelf (@$shelvesreq){
	$shelves{$shelf->{'uid'}} = $shelf->{'id'};
}

$json = json_from_call( "/storage/disks?fields=node,name,serial_number,model,usable_size,rpm,type,pool,state,bay,physical_size,shelf" );

my $sensors = $json->{'records'};

my @sorted_sensors = sort {
  $a->{'node'}->{'name'} cmp $b->{'node'}->{'name'} ||
  length($a->{'name'}) <=> length($b->{'name'}) ||
  $a->{'name'} cmp $b->{'name'}
} @$sensors;

foreach my $sensor (@sorted_sensors){

	my $name = $sensor->{'name'};

	my $node = $sensor->{'node'}->{'name'};
	my $serial = $sensor->{'serial_number'};
	my $physical_size = $sensor->{'physical_size'};
	my $rpm = $sensor->{'rpm'} || 0;
	my $type = $sensor->{'type'};
	my $model = $sensor->{'model'};
	my $bay = $sensor->{'bay'};
	my $pool = $sensor->{'pool'};
	my $shelf = $shelves{$sensor->{'shelf'}->{uid}};

	my $state = $sensor->{'state'};

	if( $state eq "present" || $state eq "spare" ) {
		$ok++;
		if( $Verbose ) {
			$ok_msg .= "Disk " . $name . " on node " . $node 
			. " (shelf: " . $shelf .", bay: " . $bay .", pool: " . $pool . ") is in state: " . $state 
			. " (" . $model .", ". $type . "/" . $rpm . ", " 
			. int(int($physical_size)/1000/1000/1000) . "GB, SN: " . $serial . ")\r\n";
 		}
	} else {
		$crit_msg .= "Disk " . $name . " on node " . $node
		. " (shelf: " . $shelf .", bay: " . $bay .", pool: " . $pool . ") is in state: " . $state
		. " (" . $model .", ". $type . "/" . $rpm . ", "
		. int(int($physical_size)/1000/1000/1000) . "GB, SN: " . $serial . ")\r\n";
		$critical++;
	}
}
if( $ok > 0 && $critical == 0 && $warning == 0 ) {
	$ok_msg = "All disks (".$ok.") are in Present/Spare state.\r\n" . $ok_msg;
}

if($critical > 0) {
    print "CRITICAL: $crit_msg\n\n";
    if($warning > 0) {
        print "WARNING: $warn_msg\n\n";
    }
    if($Verbose && $ok > 0) {
        print "OK: $ok_msg";
    }
    print  "\n";
    exit 2;
} elsif($warning > 0) {
    print "WARNING: $warn_msg\n\n";
    if($Verbose && $ok > 0) {
        print "OK: $ok_msg";
    }
    print  "\n";    
    exit 1;
} else {
    if($ok > 0) {
        print "OK: $ok_msg";
    } else {
        print "OK - but no output\n";
    }
    print  "\n";    
    exit 0;
}

sub json_from_call($) {

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

Alexander Krogloth <git at krogloth.de>
Andraz Kopac

#!/usr/bin/perl
# must be installed as: /usr/lib/nagios/plugins/refreshEmailDate.pl

use strict;
use warnings;
use Getopt::Long;
use LWP::UserAgent;
use Data::Dumper;
use DBI;
use Date::Parse;
use DateTime::Format::Strptime;
use DateTime;

use lib "/usr/lib/nagios/plugins/";
use utils qw(%ERRORS $TIMEOUT);
use nagiosDatabase;

$ENV{PATH} = "";

# 2012-09-10 11:40:18
my $strp = DateTime::Format::Strptime->new(
   pattern => '%Y-%m-%d %T',
   time_zone => 'local',
);

my $status="OK";
my @output;
my $debug=0;
my $noweb=0; # if not 0, dont get the data from the web site, use STDIN
my $verbose=0;
my $check =0; # if not 0, do not store the result in the mysql database

my $nagiosStatesID = "3"; # this is the id from checks table (maps to the name of the check, usually... hardcoded here)
my $host = "exch2-fe"; # since this is a check on a remote, one off system, the host in the nagiosStates db is set to itself

my $now = DateTime->now(time_zone  => 'local')->epoch;

# called via the postfix system: 

#Getopt::Long::Configure ("bundling");
#GetOptions(
#'v'     => \$verbose,
#'verbose'       => \$verbose,
#'debug' => \$debug,
#'noweb' => \$noweb,
#'check' => \$check
#);

if ($debug) {
	print "DEBUG SET!!\n";
}

my $dbh = DBI->connect( Nagios::Database::dsn() );

if (!$dbh) {
	$status = "CRITICAL";
	push(@output," Unable to query state database");
	print "EmailDelayCheck:$status ";
	print join("",@output);
	exit;
}


my $nsGetQuery = "SELECT `key`,`value`,`modified` FROM `states` WHERE check_id=$nagiosStatesID and `host`=\"$host\"";
my $sth = $dbh->prepare ( $nsGetQuery );
my $nsUpdateQuery = "update `states` set `value`=?,`modified`=now() where check_id=$nagiosStatesID and `host`=\"$host\" and `key`=?";
my $sthUpdate = $dbh->prepare ( $nsUpdateQuery);

my @lines;

if (!$sth->execute()) {
	$status = "CRITICAL";
	push(@output," Unable to query state database");
	print "EmailDelayCheck:$status ";
	print join("",@output);
	exit ;
}

my ($key,$value,$modified);
my $nsData = $sth->fetchall_hashref('key');
if (!$sth->finish()) {
	$status = "CRITICAL";
	push(@output," Unable to query state database");
	print "EmailDelayCheck:$status ";
	print join("",@output);
	exit;
}

print Dumper $nsData if $debug;

#look at the datetime stamp in the database
# look for sent date
# look for recv date

# use the query to update the mysql database ONLY if check has not been asked for (prevents updating if differences found)
#if (!$check) {
#	$sthUpdate->execute($data->{$max}->{'version'},'maxVersion');
#	$sthUpdate->execute($data->{$max}->{'date'},'maxDate');
#}

my $foundSend = 1; 
my $foundRecp = 1; 
my $foundSubject =0;
my $id = 0;

while (<STDIN>) {
	if (m/^From:.*eriemg.com\n/i) {
		$foundSend = 1;
	}
	if (m/^To:.*emailDelayCheck\n/i) {
		$foundRecp = 1;
	}
	if (m/^Subject:\s+Email Check ID:(\d+)\n/i) {
		$id = $1;
		$foundSubject = 1;
	}

	#if ($foundSend && $foundRecp && $foundSubject) {
	#	# no more to look for...
	#	break;
	#}
	# really want to consume the whole email...
}

if ($foundSend && $foundRecp && $foundSubject) {
	print "DEBUG: Found all items\n" if $debug;
	if (!$check) {
		print "DEBUG: pushing $id to database\n" if $debug;
		$sthUpdate->execute($id,'recvDate');
	} else {
		print "Would have set recvDate as $id\n";
	}
}

exit 0;

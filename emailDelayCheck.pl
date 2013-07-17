#!/usr/bin/perl -T
use strict;
use warnings;
use Getopt::Long;
use LWP::UserAgent;
use Data::Dumper;
use DBI;
use Date::Parse;
use DateTime::Format::Strptime;
use DateTime;

$ENV{PATH} = "";

# 2012-09-10 11:40:18
my $strp = DateTime::Format::Strptime->new(
   pattern => '%Y-%m-%d %T',
   time_zone => 'local',
);


## Nagios specific

use lib "/usr/lib/nagios/plugins/";
use utils qw(%ERRORS $TIMEOUT);
use nagiosDatabase;

my $status="OK";
my @output;
my $debug=0;
my $noweb=0; # if not 0, dont get the data from the web site, use STDIN
my $verbose=0;
my $check =0; # if not 0, do not store the result in the mysql database

my $nagiosStatesID = "3"; # this is the id from checks table (maps to the name of the check, usually... hardcoded here)
my $host = "exch2-fe"; # since this is a check on a remote, one off system, the host in the nagiosStates db is set to itself

my $now = DateTime->now(time_zone  => 'local')->epoch;

Getopt::Long::Configure ("bundling");
GetOptions(
'v'     => \$verbose,
'verbose'       => \$verbose,
'debug' => \$debug,
'noweb' => \$noweb,
'check' => \$check
);

if ($debug) {
	print "DEBUG SET!!\n";
}

my $dbh = DBI->connect( Nagios::Database::dsn() );

if (!$dbh) {
	$status = "CRITICAL";
	push(@output," Unable to query state database");
	print "EmailDelayCheck:$status ";
	print join("",@output);
	exit $ERRORS{$status};
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
	exit $ERRORS{$status};
}

my ($key,$value,$modified);
my $nsData = $sth->fetchall_hashref('key');
if (!$sth->finish()) {
	$status = "CRITICAL";
	push(@output," Unable to query state database");
	print "EmailDelayCheck:$status ";
	print join("",@output);
	exit $ERRORS{$status};
}

$nsData->{'recvDate'}->{'modifiedTS'} = $strp->parse_datetime($nsData->{'recvDate'}->{'modified'}, time_zone=>'local')->epoch;
$nsData->{'sentDate'}->{'modifiedTS'} = $strp->parse_datetime($nsData->{'sentDate'}->{'modified'}, time_zone=>'local')->epoch;

print Dumper $nsData if $debug;


#look at the datetime stamp in the database
# look for sent date
# look for recv date

my $data =();

push(@output,
	sprintf("sentVer:%s, recvVer:%s",
		$nsData->{'sentDate'}->{'value'},
		$nsData->{'recvDate'}->{'value'}
	)
);

if ( $nsData->{'sentDate'}->{'value'} ne $nsData->{'recvDate'}->{'value'} ) {
	# this should only be sent value being higher than recv value (I would hope more sent than recived...)
	if ( $nsData->{'sentDate'}->{'value'} < $nsData->{'recvDate'}->{'value'} ) {
		push (@output," Inconsistant Recv Value!");
		$status = "CRITICAL";
	}
	if ( $nsData->{'sentDate'}->{'value'} > $nsData->{'recvDate'}->{'value'} ) {
		push (@output," Email not yet recieved.");
		# no status change, let the delay checks force a status change
	}
	
	if ( ($now - $nsData->{'sentDate'}->{'modifiedTS'}) > 300) {
		push (@output," Large Delay!");
		$status = "CRITICAL";
	}

} else {
	# versions are the same...

	if ($nsData->{'recvDate'}->{'modifiedTS'} < $nsData->{'sentDate'}->{'modifiedTS'} ) {
		push (@output," Recv before Sent.");
		$status = "WARNING";
	}
	if ( ($nsData->{'recvDate'}->{'modifiedTS'} - $nsData->{'sentDate'}->{'modifiedTS'}) > 300) {
		push (@output," Large Delay once recieved.");
		$status = "WARNING";
	}
	if ( ($now - $nsData->{'sentDate'}->{'modifiedTS'}) > (1*60*60)) {
		push (@output," New Mail not sent");
		$status = "WARNING";
	}

}


# use the query to update the mysql database ONLY if check has not been asked for (prevents updating if differences found)
#if (!$check) {
#	$sthUpdate->execute($data->{$max}->{'version'},'maxVersion');
#	$sthUpdate->execute($data->{$max}->{'date'},'maxDate');
#}

#perf data
push(@output,
	sprintf("|sent v=%d,%s, recv v=%d,%s diff=%d secs,last sent=%.2f mins ago \n",
		$nsData->{'sentDate'}->{'value'},
		$nsData->{'sentDate'}->{'modified'},
		$nsData->{'recvDate'}->{'value'},
		$nsData->{'recvDate'}->{'modified'},
		$nsData->{'recvDate'}->{'modifiedTS'} - $nsData->{'sentDate'}->{'modifiedTS'},
		($now - $nsData->{'sentDate'}->{'modifiedTS'})/60.0
	)
);

print "EmailDelayCheck:$status ";
print join("",@output);

exit $ERRORS{$status};


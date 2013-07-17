#!/usr/bin/perl -T
# must be installed as: /home/monitor/bin/sendEmailDelayCheck.pl

use strict;
use warnings;
use Getopt::Long;
use LWP::UserAgent;
use Data::Dumper;
use DBI;
use Date::Parse;
use DateTime::Format::Strptime;
use DateTime;
use Net::SMTP;

use lib "/usr/lib/nagios/plugins/";
use utils qw(%ERRORS $TIMEOUT);
use nagiosDatabase;

$ENV{PATH} = "";

# 2012-09-10 11:40:18
my $strp = DateTime::Format::Strptime->new(
   pattern => '%Y-%m-%d %T',
   time_zone => 'local',
);

my $debug=0;
my $verbose=0;
my $check =0; # if not 0, do not store the result in the mysql database

my $nagiosStatesID = "3"; # this is the id from checks table (maps to the name of the check, usually... hardcoded here)
my $host = "exch2-fe"; # since this is a check on a remote, one off system, the host in the nagiosStates db is set to itself

my $now = DateTime->now(time_zone  => 'local')->epoch;

Getopt::Long::Configure ("bundling");
GetOptions(
'debug' => \$debug,
'check' => \$check
);

if ($debug) {
	print "DEBUG SET!!\n";
}

my $dbh = DBI->connect( Nagios::Database::dsn() );
if (!$dbh) {
	exit;
}

my $nsGetQuery = "SELECT `key`,`value`,`modified` FROM `states` WHERE check_id=$nagiosStatesID and `host`=\"$host\"";
my $sth = $dbh->prepare ( $nsGetQuery );
my $nsUpdateQuery = "update `states` set `value`=?,`modified`=now() where check_id=$nagiosStatesID and `host`=\"$host\" and `key`=?";
my $sthUpdate = $dbh->prepare ( $nsUpdateQuery);

my @lines;

if (!$sth->execute()) {
	exit ;
}

my ($key,$value,$modified);
my $nsData = $sth->fetchall_hashref('key');
if (!$sth->finish()) {
	exit;
}

print Dumper $nsData if $debug;

my $id = $nsData->{'sentDate'}->{'value'}+1;

my $smtp = Net::SMTP->new('ms1.eriemg.com', Timeout => 60, Hello => 'monitor3.eriemg.com', Debug => 1);
$smtp->mail('support@eriemg.com');
$smtp->to('emailDelayCheck@monitor.eriemg.com');
$smtp->data();
$smtp->datasend("To: emailDelayCheck\@monitor.eriemg.com\n");
$smtp->datasend("From: support\@eriemg.com\n");
$smtp->datasend("Subject: Email Check ID:$id\n");
$smtp->datasend("\n");
$smtp->datasend("This is a test email message from the Monitoring Server: monitor3\n");
$smtp->datasend("See the wiki.eriemg.com page on Nagios and email monitoring for details\n");
$smtp->datasend("Usually, a user account should never see this email - This email can be ignored.\n");
$smtp->datasend(" - support\@eriemg.com\n");
$smtp->dataend();
$smtp->quit;

if (!$check) {
	print "DEBUG: pushing $id to database\n" if $debug;
	$sthUpdate->execute($id,'sentDate');
}

exit 0;


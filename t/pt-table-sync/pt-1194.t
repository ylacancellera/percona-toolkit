#!/usr/bin/env perl

BEGIN {
   die "The PERCONA_TOOLKIT_BRANCH environment variable is not set.\n"
      unless $ENV{PERCONA_TOOLKIT_BRANCH} && -d $ENV{PERCONA_TOOLKIT_BRANCH};
   unshift @INC, "$ENV{PERCONA_TOOLKIT_BRANCH}/lib";
};

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Test::More;

use PerconaTest;
use Sandbox;
require "$trunk/bin/pt-table-sync";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave1_dbh = $sb->get_dbh_for('slave1');
my $slave2_dbh = $sb->get_dbh_for('slave2');
my $have_ncat = `which ncat 2>/dev/null`;

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave1';
}
elsif ( !$slave1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave2';
}
elsif (!$have_ncat) {
   plan skip_all => 'ncat, required for this test, is not installed or not in PATH';
}
else {
   plan tests => 3;
}

$sb->load_file('master', "t/pt-table-sync/samples/pt-1205.sql");
$sb->wait_for_slaves();

# Setting up tunnels
my $pid1 = fork();

if ( !$pid1 ) {
   setpgrp;
   system('ncat -k -l localhost 3333 --sh-exec "ncat 127.0.0.1 12345"');
   exit;
}

my $pid2 = fork();

if ( !$pid2 ) {
   setpgrp;
   system('ncat -k -l localhost 3334 --sh-exec "ncat 127.0.0.1 12346"');
   exit;
}

my $o = new OptionParser();
my $q = new Quoter();
my $ms = new MasterSlave(
               OptionParser=>$o,
               DSNParser=>$dp,
               Quoter=>$q,
            );
my $ss = $ms->get_slave_status($slave1_dbh);

$slave1_dbh->do('STOP SLAVE');
$slave1_dbh->do("CHANGE MASTER TO MASTER_PORT=3333, MASTER_LOG_POS=$ss->{exec_master_log_pos}");
$slave1_dbh->do('START SLAVE');

my $output = `$trunk/bin/pt-table-sync h=127.0.0.1,P=3334,u=msandbox,p=msandbox --database=test --table=t1 --sync-to-master --execute --verbose 2>&1`;

unlike(
   $output,
   qr/The slave is connected to \d+ but the master's port is/,
   'No error for redirected replica'
) or diag($output);

kill -1, getpgrp($pid1);
kill -1, getpgrp($pid2);

$slave1_dbh->do('STOP SLAVE');
$ss = $ms->get_slave_status($slave1_dbh);
$slave1_dbh->do("CHANGE MASTER TO MASTER_PORT=12347, MASTER_LOG_POS=$ss->{exec_master_log_pos}");
$slave1_dbh->do('START SLAVE SQL_THREAD');

$output = `$trunk/bin/pt-table-sync h=127.0.0.1,P=12346,u=msandbox,p=msandbox --database=test --table=t1 --sync-to-master --execute --verbose 2>&1`;

like(
   $output,
   qr/The server specified as a master has no connected slaves/,
   'Error printed for the wrong master'
) or diag($output);

$slave1_dbh->do('STOP SLAVE');
$slave1_dbh->do("CHANGE MASTER TO MASTER_PORT=12345, MASTER_LOG_POS=$ss->{exec_master_log_pos}");
$slave1_dbh->do('START SLAVE');
# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;

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
require "$trunk/bin/pt-online-schema-change";

my $dp = new DSNParser(opts=>$dsn_opts);
my $sb = new Sandbox(basedir => '/tmp', DSNParser => $dp);
my $master_dbh = $sb->get_dbh_for('master');
my $slave1_dbh = $sb->get_dbh_for('slave1'); 
my $slave2_dbh = $sb->get_dbh_for('slave2'); 

if ( !$master_dbh ) {
   plan skip_all => 'Cannot connect to sandbox master';
}
elsif ( !$slave1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave1';
}
elsif ( !$slave1_dbh ) {
   plan skip_all => 'Cannot connect to sandbox slave2';
}
else {
   plan tests => 2;
}

$sb->load_file('master', "t/pt-online-schema-change/samples/basic_no_fks.sql");

$sb->wait_for_slaves();

# Save original PTDEBUG env because we modify it below.
my $dbg = $ENV{PTDEBUG};

$ENV{PTDEBUG} = 1;

my $output = `$trunk/bin/pt-online-schema-change h=localhost,S=/tmp/12345/mysql_sandbox12345.sock,D=pt_osc,t=t --user=msandbox --password=msandbox --slave-user=msandbox --slave-password=msandbox --alter "FORCE" --recursion-method=processlist --no-check-replication-filters --no-check-alter --no-check-plan --chunk-index=PRIMARY --no-version-check --execute 2>&1`;

unlike(
   $output,
   qr/Use of uninitialized value in concatenation (.) or string/,
   'No error with PTDEBUG output'
) or diag($output);

# Restore PTDEBUG env.
delete $ENV{PTDEBUG};
$ENV{PTDEBUG} = $dbg || 0;

# #############################################################################
# Done.
# #############################################################################
$sb->wipe_clean($master_dbh);
ok($sb->ok(), "Sandbox servers") or BAIL_OUT(__FILE__ . " broke the sandbox");
exit;

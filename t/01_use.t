#!/usr/bin/env perl
use strict;
use warnings;

use Test::More;

my $module = 'BlastoutAnalyze';
my @subs = qw( 
  run
  init_logging
  get_parameters_from_cmd
  _capture_output
  _exec_cmd
  _dbi_connect
  _create_table
  create_db
  blastout_analyze
  import_blastout
  import_map
  import_blastdb_stats
  import_names
  analyze_blastout
  report_per_ps
  report_per_ps_unique
  exclude_ti_from_blastout
  import_blastout_full
  import_blastdb
  import_reports
  top_hits
);

use_ok( $module, @subs);

foreach my $sub (@subs) {
    can_ok( $module, $sub);
}

done_testing();

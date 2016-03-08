#!/usr/bin/env perl
use strict;
use warnings;
use 5.010;

use Test::More;
use Capture::Tiny qw/capture/;

# testing -h (help)
my $cmd_help = qq|perl lib/BlastoutAnalyze.pm -h|;
my ( $stdout, $stderr, $exit ) = capture {
    system($cmd_help);
};
#END {say 'STDOUT  is: ', "$stdout", "\n", 'STDERR   is: ', "$stderr", "\n", 'EXIT    is: ', "$exit";}
like ($stdout, qr/Usage:/, 'stdout calling module with help -h');

# testing -m (man)
my $cmd_man = qq|perl lib/BlastoutAnalyze.pm -m|;
my ( $stdout_man, $stderr_man, $exit_man ) = capture {
    system($cmd_man);
};
#END {say 'STDOUT  is: ', "$stdout_man", "\n", 'STDERR   is: ', "$stderr_man", "\n", 'EXIT    is: ', "$exit_man";}
like ($stdout_man, qr/SYNOPSIS/, 'stdout calling module with man -m');

## testing create_db
#my $cmd_mode = qq|perl lib/BlastoutAnalyze.pm --mode=create_db|;
#my ( $stdout_m, $stderr_m, $exit_m ) = capture {
#    system($cmd_mode);
#};
##END {say 'STDOUT  is: ', "$stdout_m", "\n", 'STDERR   is: ', "$stderr_m", "\n", 'EXIT    is: ', "$exit_m";}
#like ($stdout_m, qr//, 'stdout empty when calling module with --mode=create_db');
#like ($stderr_m, qr/RUNNING ACTION for mode: create_db/, 'stderr calling module with --mode=create_db');

done_testing();

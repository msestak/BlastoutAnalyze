#!/usr/bin/env perl
package BlastoutAnalyze;
use 5.010001;
use strict;
use warnings;
use Exporter 'import';
use File::Spec::Functions qw(:ALL);
use Path::Tiny;
use Carp;
use Getopt::Long;
use Pod::Usage;
use Capture::Tiny qw/capture/;
use Data::Dumper;
use Data::Printer;
#use Regexp::Debugger;
use Log::Log4perl;
use File::Find::Rule;
use Config::Std { def_sep => '=' };   #MySQL uses =
use DBI qw(:sql_types);   # for bind_param()
use DBD::mysql;
use DBD::SQLite;
use DateTime::Tiny;
use POSIX qw(mkfifo);
use Parallel::ForkManager;

our $VERSION = "0.01";

our @EXPORT_OK = qw{
  run
  init_logging
  get_parameters_from_cmd
  create_db
  _capture_output
  _exec_cmd
  _dbi_connect
  _create_table
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
  reduce_blastout
  export_to_ff
};

#MODULINO - works with debugger too
run() if !caller() or (caller)[0] eq 'DB';

### INTERFACE SUB starting all others ###
# Usage      : main();
# Purpose    : it starts all other subs and entire modulino
# Returns    : nothing
# Parameters : none (argument handling by Getopt::Long)
# Throws     : lots of exceptions from logging
# Comments   : start of entire module
# See Also   : n/a
sub run {
    croak 'main() does not need parameters' unless @_ == 0;

    #first capture parameters to enable verbose flag for logging
    my ($param_href) = get_parameters_from_cmd();

    #preparation of parameters
    my $verbose  = $param_href->{verbose};
    my $quiet    = $param_href->{quiet};
    my @mode     = @{ $param_href->{mode} };

    #start logging for the rest of program (without capturing of parameters)
    init_logging( $verbose, $param_href->{argv} );
    ##########################
    # ... in some function ...
    ##########################
    my $log = Log::Log4perl::get_logger("main");

    # Logs both to Screen and File appender
	#$log->info("This is start of logging for $0");
	#$log->trace("This is example of trace logging for $0");

    #get dump of param_href if -v (verbose) flag is on (for debugging)
    my $param_print = sprintf( p($param_href) ) if $verbose;
    $log->debug( '$param_href = '."$param_print" ) if $verbose;

    #call write modes (different subs that print different jobs)
    my %dispatch = (
        create_db            => \&create_db,              # drop and recreate database in MySQL
        blastout_analyze     => \&blastout_analyze,       # analyze BLAST output and extract prot_id => ti information
        import_blastout      => \&import_blastout,        # import BLAST output
        import_map           => \&import_map,             # import Phylostratigraphic map with header
		import_blastdb_stats => \&import_blastdb_stats,   # import BLAST database stats file
		import_names         => \&import_names,           # import names file
		analyze_blastout     => \&analyze_blastout,       # analyzes BLAST output file using mapn names and blastout tables
		report_per_ps        => \&report_per_ps,          # make a report of previous analysis (BLAST hits per phylostratum)
		report_per_ps_unique => \&report_per_ps_unique,   # add unique BLAST hits per species
		exclude_ti_from_blastout => \&exclude_ti_from_blastout,   # excludes specific tax_id from BLAST output file
        import_blastout_full => \&import_blastout_full,   # import BLAST output with all columns
        import_blastdb       => \&import_blastdb,         # import BLAST database with all columns
        import_reports       => \&import_reports,         # import expanded reports
        top_hits             => \&top_hits,               # create top N hits based on number of genes per domain
        reduce_blastout      => \&reduce_blastout,        # reduce blastout based on cutoff
        export_to_ff         => \&export_to_ff,           # export proteomes fron blast database to .ff files

    );

    foreach my $mode (@mode) {
        if ( exists $dispatch{$mode} ) {
            $log->info("RUNNING ACTION for mode: ", $mode);

            $dispatch{$mode}->( $param_href );

            $log->info("TIME when finished for: $mode");
        }
        else {
            #complain if mode misspelled or just plain wrong
            $log->logcroak( "Unrecognized mode --mode={$mode} on command line thus aborting");
        }
    }

    return;
}

### INTERNAL UTILITY ###
# Usage      : my ($param_href) = get_parameters_from_cmd();
# Purpose    : processes parameters from command line
# Returns    : $param_href --> hash ref of all command line arguments and files
# Parameters : none -> works by argument handling by Getopt::Long
# Throws     : lots of exceptions from die
# Comments   : works without logger
# See Also   : run()
sub get_parameters_from_cmd {

    #no logger here
    # setup config file location
    my ( $volume, $dir_out, $perl_script ) = splitpath($0);
    $dir_out = rel2abs($dir_out);
    my ($app_name) = $perl_script =~ m{\A(.+)\.(?:.+)\z};
    $app_name = lc $app_name;
    my $config_file = catfile( $volume, $dir_out, $app_name . '.cnf' );
    $config_file = canonpath($config_file);

    #read config to setup defaults
    read_config( $config_file => my %config );

    #p(%config);
    my $config_ps_href = $config{PS};

    #p($config_ps_href);
    my $config_ti_href = $config{TI};

    #p($config_ti_href);
    my $config_psname_href = $config{PSNAME};

    #push all options into one hash no matter the section
    my %opts;
    foreach my $key ( keys %config ) {

        # don't expand PS, TI or PSNAME
        next if ( ( $key eq 'PS' ) or ( $key eq 'TI' ) or ( $key eq 'PSNAME' ) );

        # expand all other options
        %opts = ( %opts, %{ $config{$key} } );
    }

    # put config location to %opts
    $opts{config} = $config_file;

    # put PS and TI section to %opts
    $opts{ps}     = $config_ps_href;
    $opts{ti}     = $config_ti_href;
    $opts{psname} = $config_psname_href;

    #cli part
    my @arg_copy = @ARGV;
    my ( %cli, @mode );
    $cli{quiet}   = 0;
    $cli{verbose} = 0;
    $cli{argv}    = \@arg_copy;

    #mode, quiet and verbose can only be set on command line
    GetOptions(
        'help|h'       => \$cli{help},
        'man|m'        => \$cli{man},
        'config|cnf=s' => \$cli{config},
        'in|i=s'       => \$cli{in},
        'infile|if=s'  => \$cli{infile},
        'out|o=s'      => \$cli{out},
        'outfile|of=s' => \$cli{outfile},

        'nodes|no=s'          => \$cli{nodes},
        'names|na=s'          => \$cli{names},
        'names_tbl=s'         => \$cli{names_tbl},
        'blastout=s'          => \$cli{blastout},
        'stats=s'             => \$cli{stats},
        'blastout_analysis=s' => \$cli{blastout_analysis},
        'map=s'               => \$cli{map},
        'analyze_ps=s'        => \$cli{analyze_ps},
        'analyze_genomes=s'   => \$cli{analyze_genomes},
        'report_per_ps=s'     => \$cli{report_per_ps},
        'tax_id|ti=i'         => \$cli{tax_id},
        'max_processes=i'     => \$cli{max_processes},
        'cutoff=i'            => \$cli{cutoff},
        'cutoff_ps1=i'        => \$cli{cutoff_ps1},
        'table_name=s'        => \$cli{table_name},

        # top hits
        'top_hits=i' => \$cli{top_hits},

        # database parameters
        'host|ho=s'    => \$cli{host},
        'database|d=s' => \$cli{database},
        'user|u=s'     => \$cli{user},
        'password|p=s' => \$cli{password},
        'port|po=i'    => \$cli{port},
        'socket|s=s'   => \$cli{socket},

        'mode|mo=s{1,}' => \$cli{mode},       #accepts 1 or more arguments
        'quiet|q'       => \$cli{quiet},      #flag
        'verbose+'      => \$cli{verbose},    #flag
    ) or pod2usage( -verbose => 1 );

    # help and man
    pod2usage( -verbose => 1 ) if $cli{help};
    pod2usage( -verbose => 2 ) if $cli{man};

    #you can specify multiple modes at the same time
    @mode = split( /,/, $cli{mode} );
    $cli{mode} = \@mode;
    die 'No mode specified on command line' unless $cli{mode};    #DIES here if without mode

    #if not -q or --quiet print all this (else be quiet)
    if ( $cli{quiet} == 0 ) {

        #print STDERR 'My @ARGV: {', join( "} {", @arg_copy ), '}', "\n";
        #no warnings 'uninitialized';
        #print STDERR "Extra options from config:", Dumper(\%opts);

        if ( $cli{in} ) {
            say 'My input path: ', canonpath( $cli{in} );
            $cli{in} = rel2abs( $cli{in} );
            $cli{in} = canonpath( $cli{in} );
            say "My absolute input path: $cli{in}";
        }
        if ( $cli{infile} ) {
            say 'My input file: ', canonpath( $cli{infile} );
            $cli{infile} = rel2abs( $cli{infile} );
            $cli{infile} = canonpath( $cli{infile} );
            say "My absolute input file: $cli{infile}";
        }
        if ( $cli{out} ) {
            say 'My output path: ', canonpath( $cli{out} );
            $cli{out} = rel2abs( $cli{out} );
            $cli{out} = canonpath( $cli{out} );
            say "My absolute output path: $cli{out}";
        }
        if ( $cli{outfile} ) {
            say 'My outfile: ', canonpath( $cli{outfile} );
            $cli{outfile} = rel2abs( $cli{outfile} );
            $cli{outfile} = canonpath( $cli{outfile} );
            say "My absolute outfile: $cli{outfile}";
        }
    }
    else {
        $cli{verbose} = -1;    #and logging is OFF

        if ( $cli{in} ) {
            $cli{in} = rel2abs( $cli{in} );
            $cli{in} = canonpath( $cli{in} );
        }
        if ( $cli{infile} ) {
            $cli{infile} = rel2abs( $cli{infile} );
            $cli{infile} = canonpath( $cli{infile} );
        }
        if ( $cli{out} ) {
            $cli{out} = rel2abs( $cli{out} );
            $cli{out} = canonpath( $cli{out} );
        }
        if ( $cli{outfile} ) {
            $cli{outfile} = rel2abs( $cli{outfile} );
            $cli{outfile} = canonpath( $cli{outfile} );
        }
    }

    #copy all config opts
    my %all_opts = %opts;

    #update with cli options
    foreach my $key ( keys %cli ) {
        if ( defined $cli{$key} ) {
            $all_opts{$key} = $cli{$key};
        }
    }

    return ( \%all_opts );
}

### INTERNAL UTILITY ###
# Usage      : init_logging();
# Purpose    : enables Log::Log4perl log() to Screen and File
# Returns    : nothing
# Parameters : verbose flag + copy of parameters from command line
# Throws     : croaks if it receives parameters
# Comments   : used to setup a logging framework
#            : logfile is in same directory and same name as script -pl +log
# See Also   : Log::Log4perl at https://metacpan.org/pod/Log::Log4perl
sub init_logging {
    croak 'init_logging() needs verbose parameter' unless @_ == 2;
    my ( $verbose, $argv_copy ) = @_;

    #create log file in same dir where script is running
	#removes perl script and takes absolute path from rest of path
	my ($volume,$dir_out,$perl_script) = splitpath( $0 );
	#say '$dir_out:', $dir_out;
	$dir_out = rel2abs($dir_out);
	#say '$dir_out:', $dir_out;

    my ($app_name) = $perl_script =~ m{\A(.+)\.(?:.+)\z};   #takes name of the script and removes .pl or .pm or .t
    #say '$app_name:', $app_name;
    my $logfile = catfile( $volume, $dir_out, $app_name . '.log' );    #combines all of above with .log
	#say '$logfile:', $logfile;
	$logfile = canonpath($logfile);
	#say '$logfile:', $logfile;

    #colored output on windows
    my $osname = $^O;
    if ( $osname eq 'MSWin32' ) {
        require Win32::Console::ANSI;                                 #require needs import
        Win32::Console::ANSI->import();
    }

    #enable different levels based on verbose flag
    my $log_level;
    if    ($verbose == 0)  { $log_level = 'INFO';  }
    elsif ($verbose == 1)  { $log_level = 'DEBUG'; }
    elsif ($verbose == 2)  { $log_level = 'TRACE'; }
    elsif ($verbose == -1) { $log_level = 'OFF';   }
	else                   { $log_level = 'INFO';  }

    #levels:
    #TRACE, DEBUG, INFO, WARN, ERROR, FATAL
    ###############################################################################
    #                              Log::Log4perl Conf                             #
    ###############################################################################
    # Configuration in a string ...
    my $conf = qq(
      log4perl.category.main                   = TRACE, Logfile, Screen

	  # Filter range from TRACE up
	  log4perl.filter.MatchTraceUp               = Log::Log4perl::Filter::LevelRange
      log4perl.filter.MatchTraceUp.LevelMin      = TRACE
      log4perl.filter.MatchTraceUp.LevelMax      = FATAL
      log4perl.filter.MatchTraceUp.AcceptOnMatch = true

      # Filter range from $log_level up
      log4perl.filter.MatchLevelUp               = Log::Log4perl::Filter::LevelRange
      log4perl.filter.MatchLevelUp.LevelMin      = $log_level
      log4perl.filter.MatchLevelUp.LevelMax      = FATAL
      log4perl.filter.MatchLevelUp.AcceptOnMatch = true
      
	  # setup of file log
      log4perl.appender.Logfile           = Log::Log4perl::Appender::File
      log4perl.appender.Logfile.filename  = $logfile
      log4perl.appender.Logfile.mode      = append
      log4perl.appender.Logfile.autoflush = 1
      log4perl.appender.Logfile.umask     = 0022
      log4perl.appender.Logfile.header_text = INVOCATION:$0 @$argv_copy
      log4perl.appender.Logfile.layout    = Log::Log4perl::Layout::PatternLayout
      log4perl.appender.Logfile.layout.ConversionPattern = [%d{yyyy/MM/dd HH:mm:ss,SSS}]%5p> %M line:%L==>%m%n
	  log4perl.appender.Logfile.Filter    = MatchTraceUp
      
	  # setup of screen log
      log4perl.appender.Screen            = Log::Log4perl::Appender::ScreenColoredLevels
      log4perl.appender.Screen.stderr     = 1
      log4perl.appender.Screen.layout     = Log::Log4perl::Layout::PatternLayout
      log4perl.appender.Screen.layout.ConversionPattern  = [%d{yyyy/MM/dd HH:mm:ss,SSS}]%5p> %M line:%L==>%m%n
	  log4perl.appender.Screen.Filter     = MatchLevelUp
    );

    # ... passed as a reference to init()
    Log::Log4perl::init( \$conf );

    return;
}


### INTERNAL UTILITY ###
# Usage      : my ($stdout, $stderr, $exit) = _capture_output( $cmd, $param_href );
# Purpose    : accepts command, executes it, captures output and returns it in vars
# Returns    : STDOUT, STDERR and EXIT as vars
# Parameters : ($cmd_to_execute,  $param_href)
# Throws     : nothing
# Comments   : second param is verbose flag (default off)
# See Also   :
sub _capture_output {
    my $log = Log::Log4perl::get_logger("main");
    $log->logdie( '_capture_output() needs a $cmd' ) unless (@_ ==  2 or 1);
    my ($cmd, $param_href) = @_;

    my $verbose = $param_href->{verbose};
    $log->debug(qq|Report: COMMAND is: $cmd|);

    my ( $stdout, $stderr, $exit ) = capture {
        system($cmd );
    };

    if ($verbose == 2) {
        $log->trace( 'STDOUT is: ', "$stdout", "\n", 'STDERR  is: ', "$stderr", "\n", 'EXIT   is: ', "$exit" );
    }

    return  $stdout, $stderr, $exit;
}

### INTERNAL UTILITY ###
# Usage      : _exec_cmd($cmd_git, $param_href, $cmd_info);
# Purpose    : accepts command, executes it and checks for success
# Returns    : prints info
# Parameters : ($cmd_to_execute, $param_href)
# Throws     : 
# Comments   : second param is verbose flag (default off)
# See Also   :
sub _exec_cmd {
    my $log = Log::Log4perl::get_logger("main");
    $log->logdie( '_exec_cmd() needs a $cmd, $param_href and info' ) unless (@_ ==  2 or 3);
	croak( '_exec_cmd() needs a $cmd' ) unless (@_ == 2 or 3);
    my ($cmd, $param_href, $cmd_info) = @_;
	if (!defined $cmd_info) {
		($cmd_info)  = $cmd =~ m/\A(\w+)/;
	}
    my $verbose = $param_href->{verbose};

    my ($stdout, $stderr, $exit) = _capture_output( $cmd, $param_href );
    if ($exit == 0 and $verbose > 1) {
        $log->trace( "$cmd_info success!" );
    }
	else {
        $log->trace( "$cmd_info failed!" );
	}
	return $exit;
}


## INTERNAL UTILITY ###
# Usage      : my $dbh = _dbi_connect( $param_href );
# Purpose    : creates a connection to database
# Returns    : database handle
# Parameters : ( $param_href )
# Throws     : DBI errors and warnings
# Comments   : first part of database chain
# See Also   : DBI and DBD::mysql modules
sub _dbi_connect {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak( '_dbi_connect() needs a hash_ref' ) unless @_ == 1;
    my ($param_href) = @_;
	
	#split logic for operating system
	my $osname = $^O;
	my $data_source;
    my $user     = defined $param_href->{user}     ? $param_href->{user}     : 'msandbox';
    my $password = defined $param_href->{password} ? $param_href->{password} : 'msandbox';
	
	if( $osname eq 'MSWin32' ) {	  
		my $host     = defined $param_href->{host}     ? $param_href->{host}     : 'localhost';
    	my $database = defined $param_href->{database} ? $param_href->{database} : 'blastdb';
    	my $port     = defined $param_href->{port}     ? $param_href->{port}     : 3306;
    	my $prepare  = 1;   #server side prepare is ON
		my $use_res  = 0;   #1 doesn't work with selectall_aref (O means it catches in application)

    	$data_source = "DBI:mysql:database=$database;host=$host;port=$port;mysql_server_prepare=$prepare;mysql_use_result=$use_res";
	}
	elsif ( $osname eq 'linux' ) {
		my $host     = defined $param_href->{host}     ? $param_href->{host}     : 'localhost';
    	my $database = defined $param_href->{database} ? $param_href->{database} : 'blastdb';
    	my $port     = defined $param_href->{port}     ? $param_href->{port}     : 3306;
    	my $socket   = defined $param_href->{socket}   ? $param_href->{socket}   : '/var/lib/mysql/mysql.sock';
    	my $prepare  = 1;   #server side prepare is ON
		my $use_res  = 0;   #1 doesn't work with selectall_aref (O means it catches in application)

    	$data_source = "DBI:mysql:database=$database;host=$host;port=$port;mysql_socket=$socket;mysql_server_prepare=$prepare;mysql_use_result=$use_res";
	}
	else {
		$log->error( "Running on unsupported system" );
	}

	my %conn_attrs  = (
        RaiseError         => 1,
        PrintError         => 0,
        AutoCommit         => 1,
        ShowErrorStatement => 1,
    );
    my $dbh = DBI->connect( $data_source, $user, $password, \%conn_attrs );

    $log->trace( 'Report: connected to ', $data_source, ' by dbh ', $dbh );

    return $dbh;
}


### INTERNAL UTILITY ###
# Usage      : _create_table( { table_name => $table_info, dbh => $dbh, query => $create_query } );
# Purpose    : it drops and recreates table
# Returns    : nothing
# Parameters : hash_ref of table_name, dbh and query
# Throws     : errors if it fails
# Comments   : 
# See Also   : 
sub _create_table {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_create_table() needs a $param_href') unless @_ == 1;
    my ($param_href) = @_;

    my $table_name   = $param_href->{table_name} or $log->logcroak('no $table_name sent to _create_table()!');
    my $dbh          = $param_href->{dbh}        or $log->logcroak('no $dbh sent to _create_table()!');
    my $create_query = $param_href->{query}      or $log->logcroak('no $query sent to _create_table()!');

	#create table in database specified in connection
    my $drop_query = sprintf( qq{
    DROP TABLE IF EXISTS %s
    }, $dbh->quote_identifier($table_name) );
    eval { $dbh->do($drop_query) };
    $log->error("Action: dropping $table_name failed: $@") if $@;
    $log->trace("Action: $table_name dropped successfully!") unless $@;

    eval { $dbh->do($create_query) };
    $log->error( "Action: creating $table_name failed: $@" ) if $@;
    $log->trace( "Action: $table_name created successfully!" ) unless $@;

    return;
}


### INTERNAL UTILITY ###
# Usage      : _load_table_into($tbl_name, $infile, $dbh, $column_list);
# Purpose    : LOAD DATA INFILE of $infile into $tbl_name
# Returns    : nothing
# Parameters : ($tbl_name, $infile, $dbh)
# Throws     : croaks if wrong number of parameters
# Comments   : $column_list can be empty
# See Also   : 
sub _load_table_into {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_load_table_into() needs {$tbl_name, $infile, $dbh + opt. $column_list}') unless @_ == 3 or 4;
    my ($tbl_name, $infile, $dbh, $column_list) = @_;
	$column_list //= '';

	# load query
    my $load_query = qq{
    LOAD DATA INFILE '$infile'
    INTO TABLE $tbl_name } . q{ FIELDS TERMINATED BY '\t'
    LINES TERMINATED BY '\n' }
	. '(' . $column_list . ')';
	$log->trace("Report: $load_query");

	# report number of rows inserted
	my $rows;
    eval { $rows = $dbh->do( $load_query ) };
	$log->error( "Action: loading into table $tbl_name failed: $@" ) if $@;
	$log->debug( "Action: table $tbl_name inserted $rows rows!" ) unless $@;

    return;
}


### INTERFACE SUB ###
# Usage      : --mode=create_db
# Purpose    : creates database in MySQL
# Returns    : nothing
# Parameters : ( $param_href ) -> params from command line to connect to MySQL
#            : plus default charset for database
# Throws     : croaks if wrong number of parameters
# Comments   : run only once at start (it drops database)
# See Also   :
sub create_db {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak ('create_db() needs a hash_ref' ) unless @_ == 1;
    my ( $param_href ) = @_;

    my $charset  = defined $param_href->{charset} ? $param_href->{charset} : 'ascii';
	#repackage parameters to connect to MySQL to default mysql database and create $database
    my $database = $param_href->{database};   #pull out to use here
    $param_href->{database} = 'mysql';        #insert into $param_href for dbi_connect()

    my $dbh = _dbi_connect( $param_href );

    #first report what are you doing
    $log->info( "---------->{$database} database creation with CHARSET $charset" );

    #use $database from command line
    my $drop_db_query = qq{
    DROP database IF EXISTS $database
    };
    eval { $dbh->do($drop_db_query) };
    $log->debug( "Action: dropping $database failed: $@" ) if $@;
    $log->debug( "Action: database $database dropped successfully!" ) unless $@;

    my $create_db_query = qq{
    CREATE DATABASE IF NOT EXISTS $database DEFAULT CHARSET $charset
    };
    eval { $dbh->do($create_db_query) };
    $log->debug( "Action: creating $database failed: $@" ) if $@;
    $log->debug( "Action: database $database created successfully!" ) unless $@;

    return;
}


### INTERFACE SUB ###
# Usage      : --mode=blastout_analyze
# Purpose    : to analyze BLAST output and find tax_id hits per gene
# Returns    : nothing
# Parameters : $param_href
# Throws     : croaks if wrong number of parameters
# Comments   : 
# See Also   : 
sub blastout_analyze {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('blastout_analyze() needs a $param_href') unless @_ == 1;
    my ($param_href) = @_;

    my $infile = $param_href->{infile} or $log->logcroak('no $infile specified on command line!');
    my $out    = $param_href->{out}      or $log->logcroak('no $out specified on command line!');

	# open fh for BLAST output
	open (my $in_fh, "< :encoding(ASCII)", $infile) or $log->logdie("Error: can't open $infile for reading:$!");

	# create hash that will hold prot_id => ti results
	my %prot_ti_hash;
	while (<$in_fh>) {
		chomp;
		
		my ($prot_id, $hit, undef, undef, undef, undef, undef, undef, undef, undef, undef, undef) = split "\t", $_;
		my ($pgi, $ti, undef) = $hit =~ m{pgi\|(\d+)\|ti\|(\d+)\|pi\|(\d+)\|};

		$prot_ti_hash{$prot_id}->{$ti}++;   # increments the value
	

	}   # end while reading file

	p(%prot_ti_hash);

	
	

    return;
}


### INTERFACE SUB ###
# Usage      : --mode=import_blastout
# Purpose    : loads BLAST output to MySQL database
# Returns    : nothing
# Parameters : ( $param_href )
# Throws     : croaks for parameters
# Comments   : it removes duplicates (same tax_id) per gene
# See Also   : utility sub _extract_blastout()
sub import_blastout {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak( 'import_blastout() needs a hash_ref' ) unless @_ == 1;
    my ($param_href) = @_;

    my $infile = $param_href->{infile} or $log->logcroak('no $infile specified on command line!');
    my $table           = path($infile)->basename;
    $table =~ s/\./_/g;    #for files that have dots in name
    my $blastout_import = path($infile . "_formated");

    #first shorten the blastout file and extract useful columns
    _extract_blastout( { infile => $infile, blastout_import => $blastout_import } );

    #get new handle
    my $dbh = _dbi_connect($param_href);

    #create table
    my $create_query = qq{
    CREATE TABLE IF NOT EXISTS $table (
	id INT UNSIGNED AUTO_INCREMENT NOT NULL,
    prot_id VARCHAR(40) NOT NULL,
    ti INT UNSIGNED NOT NULL,
    pgi CHAR(19) NOT NULL,
    PRIMARY KEY(id)
    )};
    _create_table( { table_name => $table, dbh => $dbh, query => $create_query } );

    #import table
    my $load_query = qq{
    LOAD DATA INFILE '$blastout_import'
    INTO TABLE $table } . q{ FIELDS TERMINATED BY '\t'
    LINES TERMINATED BY '\n' 
    (prot_id, ti, pgi)
    };
	$log->trace("$load_query");
    eval { $dbh->do( $load_query, { async => 1 } ) };

    # check status while running
    my $dbh_check             = _dbi_connect($param_href);
    until ( $dbh->mysql_async_ready ) {
        my $processlist_query = qq{
        SELECT TIME_MS, STATE FROM INFORMATION_SCHEMA.PROCESSLIST
        WHERE DB = ? AND INFO LIKE 'LOAD DATA INFILE%';
        };
        my ( $time_ms, $state );
        my $sth = $dbh_check->prepare($processlist_query);
        $sth->execute($param_href->{database});
        $sth->bind_columns( \( $time_ms, $state ) );
        while ( $sth->fetchrow_arrayref ) {
            $time_ms = $time_ms / 1000;
            my $print = sprintf( "Time running:%0.3f sec\tSTATE:%s\n", $time_ms, $state );
            $log->trace( $print );
            sleep 10;
        }
    }
    my $rows;
	eval { $rows = $dbh->mysql_async_result; };
    $log->info( "Action: import inserted $rows rows!" ) unless $@;
    $log->error( "Error: loading $table failed: $@" ) if $@;

    # add index
    my $alter_query = qq{
    ALTER TABLE $table ADD INDEX protx(prot_id), ADD INDEX tix(ti)
    };
    eval { $dbh->do( $alter_query, { async => 1 } ) };

    # check status while running
    my $dbh_check2            = _dbi_connect($param_href);
    until ( $dbh->mysql_async_ready ) {
        my $processlist_query = qq{
        SELECT TIME_MS, STATE FROM INFORMATION_SCHEMA.PROCESSLIST
        WHERE DB = ? AND INFO LIKE 'ALTER%';
        };
        my ( $time_ms, $state );
        my $sth = $dbh_check2->prepare($processlist_query);
        $sth->execute($param_href->{database});
        $sth->bind_columns( \( $time_ms, $state ) );
        while ( $sth->fetchrow_arrayref ) {
            $time_ms = $time_ms / 1000;
            my $print = sprintf( "Time running:%0.3f sec\tSTATE:%s\n", $time_ms, $state );
            $log->trace( $print );
            sleep 10;
        }
    }

    #report success or failure
    $log->error( "Error: adding index tix on $table failed: $@" ) if $@;
    $log->info( "Action: Indices protx and tix on $table added successfully!" ) unless $@;
	
	#delete file used to import so it doesn't use disk space
	unlink $blastout_import and $log->warn("File $blastout_import unlinked!");

    return;
}

### INTERNAL UTILITY ###
# Usage      : _extract_blastout( { infile => $infile, blastout_import => $blastout_import } );
# Purpose    : extracts useful columns from blastout file and saves them into file
# Returns    : nothing
# Parameters : ($param_href)
# Throws     : croaks for parameters
# Comments   : needed for --mode=import_blastout()
# See Also   : import_blastout()
sub _extract_blastout {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak( 'extract_blastout() needs {hash_ref}' ) unless @_ == 1;
    my ($extract_href) = @_;

    open( my $blastout_fh, "< :encoding(ASCII)", $extract_href->{infile} ) or $log->logdie( "Error: BLASTout file not found:$!" );
    open( my $blastout_fmt_fh, "> :encoding(ASCII)", $extract_href->{blastout_import} ) or $log->logdie( "Error: BLASTout file can't be created:$!" );

    # needed for filtering duplicates
    # idea is that duplicates come one after another
    my $prot_prev    = '';
    my $pgi_prev     = 0;
    my $ti_prev      = 0;
	my $formated_cnt = 0;

    # in blastout
    #ENSG00000151914|ENSP00000354508    pgi|34252924|ti|9606|pi|0|  100.00  7461    0   0   1   7461    1   7461    0.0 1.437e+04
    
	$log->debug( "Report: started processing of $extract_href->{infile}" );
    local $.;
    while ( <$blastout_fh> ) {
        chomp;

		my ($prot_id, $hit, undef, undef, undef, undef, undef, undef, undef, undef, undef, undef) = split "\t", $_;
		my ($pgi, $ti) = $hit =~ m{pgi\|(\d+)\|ti\|(\d+)\|pi\|(?:\d+)\|};

        # check for duplicates for same gene_id with same tax_id and pgi that differ only in e_value
        if (  "$prot_prev" . "$pgi_prev" . "$ti_prev" ne "$prot_id" . "$pgi" . "$ti" ) {
            say {$blastout_fmt_fh} $prot_id, "\t", $ti, "\t", $pgi;
			$formated_cnt++;
        }

        # set found values for next line to check duplicates
        $prot_prev = $prot_id;
        $pgi_prev  = $pgi;
        $ti_prev   = $ti;

		# show progress
        if ($. % 1000000 == 0) {
            $log->trace( "$. lines processed!" );
        }

    }   # end while reading blastout

    $log->info( "Report: file $extract_href->{blastout_import} printed successfully with $formated_cnt lines (from $. original lines)" );

    return;
}


### INTERNAL UTILITY ###
# Usage      : --mode=import_map on command name
# Purpose    : imports map with header format and psname (.phmap_names)
# Returns    : nothing
# Parameters : full path to map file and database connection parameters
# Throws     : croaks if wrong number of parameters
# Comments   : creates temp files without header for LOAD data infile
# See Also   : 
sub import_map {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_import_map() needs {$map_href}') unless @_ == 1;
    my ($map_href) = @_;

	# check required parameters
    if ( ! exists $map_href->{infile} ) {$log->logcroak('no $infile specified on command line!');}

	# get name of map table
	my $map_tbl = path($map_href->{infile})->basename;
	($map_tbl) = $map_tbl =~ m/\A([^\.]+)\.phmap_names\z/;
	$map_tbl   .= '_map';

	my $dbh = _dbi_connect($map_href);

    # create map table
    my $create_query = sprintf( qq{
	CREATE TABLE IF NOT EXISTS %s (
	prot_id VARCHAR(40) NOT NULL,
	phylostrata TINYINT UNSIGNED NOT NULL,
	ti INT UNSIGNED NOT NULL,
	psname VARCHAR(200) NULL,
	PRIMARY KEY(prot_id),
	KEY(phylostrata),
	KEY(ti),
	KEY(psname)
    ) }, $dbh->quote_identifier($map_tbl) );
	_create_table( { table_name => $map_tbl, dbh => $dbh, query => $create_query } );
	$log->trace("Report: $create_query");

	# create tmp filename in same dir as input map with header
	my $temp_map = path(path($map_href->{infile})->parent, $map_tbl);
	open (my $tmp_fh, ">", $temp_map) or $log->logdie("Error: can't open map $temp_map for writing:$!");

	# need to skip header
	open (my $map_fh, "<", $map_href->{infile}) or $log->logdie("Error: can't open map $map_href->{infile} for reading:$!");
	while (<$map_fh>) {
		chomp;
	
		# check if record (ignore header)
		next if !/\A(?:[^\t]+)\t(?:[^\t]+)\t(?:[^\t]+)\t(?:[^\t]+)\z/;
	
		my ($prot_id, $ps, $ti, $ps_name) = split "\t", $_;

		# this is needed because psname can be short without {cellular_organisms : Eukaryota}
		my $psname_short;
		if ($ps_name =~ /:/) {   # {cellular_organisms : Eukaryota}
			(undef, $psname_short) = split ' : ', $ps_name;
		}
		else {   #{Eukaryota}
			$psname_short = $ps_name;
		}

		# update map with new phylostrata (shorter phylogeny)
		my $ps_new;
		if ( exists $map_href->{ps}->{$ps} ) {
			$ps_new = $map_href->{ps}->{$ps};
			#say "LINE:$.\tPS_INFILE:$ps\tPS_NEW:$ps_new";
			$ps = $ps_new;
		}

		# update map with new tax_id (shorter phylogeny)
		my $ti_new;
		if ( exists $map_href->{ti}->{$ti} ) {
			$ti_new = $map_href->{ti}->{$ti};
			#say "LINE:$.\tTI_INFILE:$ti\tTI_NEW:$ti_new";
			$ti = $ti_new;
		}

		# update map with new phylostrata name (shorter phylogeny)
		my $psname_new;
		if ( exists $map_href->{psname}->{$psname_short} ) {
			$psname_new = $map_href->{psname}->{$psname_short};
			#say "LINE:$.\tPS_REAL_NAME:$psname_short\tPSNAME_NEW:$psname_new";
			$psname_short = $psname_new;
		}

		# print to tmp map file
		say {$tmp_fh} "$prot_id\t$ps\t$ti\t$psname_short";

	}   # end while

	# explicit close needed else it can break
	close $tmp_fh;

	# load tmp map file without header
    my $load_query = qq{
    LOAD DATA INFILE '$temp_map'
    INTO TABLE $map_tbl } . q{ FIELDS TERMINATED BY '\t'
    LINES TERMINATED BY '\n'
    };
	$log->trace("Report: $load_query");
	my $rows;
    eval { $rows = $dbh->do( $load_query ) };
	$log->error( "Action: loading into table $map_tbl failed: $@" ) if $@;
	$log->debug( "Action: table $map_tbl inserted $rows rows!" ) unless $@;

	# unlink tmp map file
	unlink $temp_map and $log->warn("Action: $temp_map unlinked");

    return;
}


### INTERFACE SUB ###
# Usage      : --mode=import_blastdb_stats
# Purpose    : import BLAST db stats created by AnalyzePhyloDb
# Returns    : nothing
# Parameters : infile and connection paramaters
# Throws     : croaks if wrong number of parameters
# Comments   : 
# See Also   : 
sub import_blastdb_stats {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('import_blastdb_stats() needs a $param_href') unless @_ == 1;
    my ($param_href) = @_;

    my $infile    = $param_href->{infile}    or $log->logcroak('no $infile specified on command line!');
    my $names_tbl = $param_href->{names_tbl} or $log->logcroak('no $names_tbl specified on command line!');
    my $stats_ps_tbl = path($infile)->basename;
    $stats_ps_tbl =~ s/\./_/g;         #for files that have dots in name
    $stats_ps_tbl .= '_stats_ps';
    my $stats_genomes_tbl = path($infile)->basename;
    $stats_genomes_tbl =~ s/\./_/g;    #for files that have dots in name
    $stats_genomes_tbl .= '_stats_genomes';

    my $dbh = _dbi_connect($param_href);

    # create ps summary table
    my $ps_summary = sprintf(
        qq{
	CREATE TABLE %s (
	phylostrata TINYINT UNSIGNED NOT NULL,
	num_of_genomes INT UNSIGNED NOT NULL,
	ti INT UNSIGNED NOT NULL,
	PRIMARY KEY(phylostrata),
	KEY(ti),
	KEY(num_of_genomes)
    ) }, $dbh->quote_identifier($stats_ps_tbl)
    );
    _create_table( { table_name => $stats_ps_tbl, dbh => $dbh, query => $ps_summary } );
    $log->trace("Report: $ps_summary");

    # create genomes per phylostrata table
    my $genomes_per_ps = sprintf(
        qq{
	CREATE TABLE %s (
	phylostrata TINYINT UNSIGNED NOT NULL,
	psti INT UNSIGNED NOT NULL,
	num_of_genes INT UNSIGNED NOT NULL,
	ti INT UNSIGNED NOT NULL,
	PRIMARY KEY(ti),
	KEY(phylostrata),
	KEY(num_of_genes)
    ) }, $dbh->quote_identifier($stats_genomes_tbl)
    );
    _create_table( { table_name => $stats_genomes_tbl, dbh => $dbh, query => $genomes_per_ps } );
    $log->trace("Report: $genomes_per_ps");

    # create tmp file for genomes part of stats file
    my $temp_stats = path( path($infile)->parent, $stats_genomes_tbl );
    open( my $tmp_fh, ">", $temp_stats ) or $log->logdie("Error: can't open map $temp_stats for writing:$!");

    # read and import stats file into MySQL
    _read_stats_file( { ps_tbl => $stats_ps_tbl, dbh => $dbh, %{$param_href}, tmp_fh => $tmp_fh } );

    # load genomes per phylostrata
    my $load_query = qq{
    LOAD DATA INFILE '$temp_stats'
    INTO TABLE $stats_genomes_tbl } . q{ FIELDS TERMINATED BY '\t'
    LINES TERMINATED BY '\n'
    };
    $log->trace("Report: $load_query");
    my $rows;
    eval { $rows = $dbh->do($load_query) };
    $log->error("Action: loading into table $stats_genomes_tbl failed: $@") if $@;
    $log->debug("Action: table $stats_genomes_tbl inserted $rows rows!") unless $@;

    # unlink tmp map file
    unlink $temp_stats and $log->warn("Action: $temp_stats unlinked");

    # modify stats tables to be more useful
    _modify_stats_tables( { %$param_href, stats_genomes_tbl => $stats_genomes_tbl, stats_ps_tbl => $stats_ps_tbl } );

    $dbh->disconnect;

    return;
}


### INTERNAL UTILITY ###
# Usage      : _read_stats_file( { ps_tbl => $stats_ps_tbl, dbh => $dbh, %{$param_href}, tmp_fh => $tmp_fh } );
# Purpose    : to read stats file and import it to database
# Returns    : nothing
# Parameters : 
# Throws     : croaks if wrong number of parameters
# Comments   : part of --mode=import_blastdb_stats
# See Also   : --mode=import_blastdb_stats
sub _read_stats_file {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_read_stats_file() needs a $param_href') unless @_ == 1;
    my ($p_href) = @_;

	# prepare statement handle to insert ps lines
	my $insert_ps = sprintf( qq{
	INSERT INTO %s (phylostrata, num_of_genomes, ti)
	VALUES (?, ?, ?)
	}, $p_href->{dbh}->quote_identifier($p_href->{ps_tbl}) );
	my $sth = $p_href->{dbh}->prepare($insert_ps);
	$log->trace("Report: $insert_ps");

	# prepare statement handle to update ps lines
	my $update_ps = sprintf( qq{
	UPDATE %s 
	SET num_of_genomes = num_of_genomes + ?
	WHERE phylostrata = ?
	}, $p_href->{dbh}->quote_identifier($p_href->{ps_tbl}) );
	my $sth_up = $p_href->{dbh}->prepare($update_ps);
	$log->trace("Report: $update_ps");

	# read and import ps_table
	open (my $stats_fh, "<", $p_href->{infile}) or $log->logdie("Error: can't open map $p_href->{infile} for reading:$!");
	while (<$stats_fh>) {
		chomp;

		# if ps then summary line
		if (m/ps/) {
			#import to stats_ps_tbl
			my (undef, $ps, $num_of_genomes, $ti, ) = split "\t", $_;

			# update phylostrata with new phylostrata (shorter phylogeny)
			my $ps_new;
			if ( exists $p_href->{ps}->{$ps} ) {
				$ps_new = $p_href->{ps}->{$ps};
				#say "LINE:$.\tPS_INFILE:$ps\tPS_NEW:$ps_new";
				$ps = $ps_new;
			}

			# update psti with new tax_id (shorter phylogeny)
			my $ti_new;
			if ( exists $p_href->{ti}->{$ti} ) {
				$ti_new = $p_href->{ti}->{$ti};
				#say "LINE:$.\tTI_INFILE:$ti\tTI_NEW:$ti_new";
				$ti = $ti_new;
			}
			
			# if it fails (ps already exists) update num_of_genomes
			eval {$sth->execute($ps, $num_of_genomes, $ti); };
			if ($@) {
				$sth_up->execute($num_of_genomes, $ps);
			}
		}
		# else normal genome in phylostrata line
		else {
			my ($ps2, $psti, $num_of_genes, $ti2) = split "\t", $_;

			# update phylostrata with new phylostrata (shorter phylogeny)
			my $ps_new2;
			if ( exists $p_href->{ps}->{$ps2} ) {
				$ps_new2 = $p_href->{ps}->{$ps2};
				#say "LINE:$.\tPS_INFILE:$ps2\tPS_NEW:$ps_new2";
				$ps2 = $ps_new2;
			}

			# update psti with new tax_id (shorter phylogeny)
			my $psti_new;
			if ( exists $p_href->{ti}->{$psti} ) {
				$psti_new = $p_href->{ti}->{$psti};
				#say "LINE:$.\tTI_INFILE:$psti\tTI_NEW:$psti_new";
				$psti = $psti_new;
			}

			# print to file
			say { $p_href->{tmp_fh} } "$ps2\t$psti\t$num_of_genes\t$ti2";
		}
	}   # end while reading stats file

	# explicit close needed else it can break
	close $p_href->{tmp_fh};
	$sth->finish;
	$sth_up->finish;

    return;
}


### INTERNAL UTILITY ###
# Usage      : _modify_stats_tables( { %$param_href, stats_genomes_tbl => $stats_genomes_tbl, stats_ps_tbl => $stats_ps_tbl } );
# Purpose    : 
# Returns    : nothing
# Parameters : 
# Throws     : croaks if wrong number of parameters
# Comments   : 
# See Also   : 
sub _modify_stats_tables {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_modify_stats_tables() needs a $param_href') unless @_ == 1;
    my ($param_href) = @_;

    my $dbh = _dbi_connect($param_href);

    # drop and recreate stats_ps_tbl
    my $ps_summary = sprintf( qq{
    CREATE TABLE %s (
    phylostrata TINYINT UNSIGNED NOT NULL,
    psti INT UNSIGNED NOT NULL,
    num_of_genomes INT UNSIGNED NOT NULL,
    num_of_genes INT UNSIGNED NOT NULL,
    PRIMARY KEY(phylostrata)
    )
    SELECT phylostrata, psti, COUNT(num_of_genes) AS num_of_genomes, SUM(num_of_genes) AS num_of_genes
    FROM %s
    GROUP BY phylostrata
    }, $dbh->quote_identifier( $param_href->{stats_ps_tbl} ), $dbh->quote_identifier( $param_href->{stats_genomes_tbl} )
    );
    _create_table( { table_name => $param_href->{stats_ps_tbl}, dbh => $dbh, query => $ps_summary } );
    $log->trace("Report: $ps_summary");

	# add species_name to stats_genomes_tbl
	my $alter_stats_q = sprintf( qq{
	ALTER TABLE %s ADD COLUMN species_name VARCHAR(200)
	}, $dbh->quote_identifier( $param_href->{stats_genomes_tbl} ) );
    eval { $dbh->do( $alter_stats_q ) };
	$log->error( "Action: alter table {$param_href->{stats_genomes_tbl}} failed: $@" ) if $@;
	$log->debug( "Action: table {$param_href->{stats_genomes_tbl}} altered!" ) unless $@;

	my $update_stats_q = sprintf( qq{
    UPDATE %s AS st
    INNER JOIN %s AS na ON na.ti = st.ti
    SET st.species_name = na.species_name
	}, $dbh->quote_identifier( $param_href->{stats_genomes_tbl} ), $dbh->quote_identifier( $param_href->{names_tbl} ) );

	my $rows;
    eval { $rows = $dbh->do( $update_stats_q ) };
	$log->error( "Action: updating table {$param_href->{stats_genomes_tbl}} failed: $@" ) if $@;
	$log->debug( "Action: table {$param_href->{stats_genomes_tbl}} updated $rows rows!" ) unless $@;
    return;
}

### INTERFACE SUB ###
# Usage      : --mode=import_names
# Purpose    : loads names file to MySQL
# Returns    : nothing
# Parameters : ( $param_href )
# Throws     : croaks for parameters
# Comments   : new format
# See Also   :
sub import_names {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak ('import_names() needs a hash_ref' ) unless @_ == 1;
    my ($param_href) = @_;

    my $infile = $param_href->{infile} or $log->logcroak('no $infile specified on command line!');
    my $names_tbl = path($infile)->basename;
    $names_tbl =~ s/\./_/g;    #for files that have dots in name)

    # get new handle
    my $dbh = _dbi_connect($param_href);

    # create names table
    my $create_names = sprintf( qq{
    CREATE TABLE %s (
    id INT UNSIGNED AUTO_INCREMENT NOT NULL,
    ti INT UNSIGNED NOT NULL,
    species_name VARCHAR(200) NOT NULL,
    PRIMARY KEY(id),
    KEY(ti),
    KEY(species_name)
    )}, $dbh->quote_identifier($names_tbl) );
	_create_table( { table_name => $names_tbl, dbh => $dbh, query => $create_names } );
	$log->trace("Report: $create_names");

    #import table
	my $column_list = 'ti, species_name, @dummy, @dummy';
	_load_table_into($names_tbl, $infile, $dbh, $column_list);

    return;
}


### INTERFACE SUB ###
# Usage      : --mode=analyze_blastout
# Purpose    : is to create expanded table per phylostrata with ps, prot_id, ti, species_name
# Returns    : nothing
# Parameters : 
# Throws     : croaks if wrong number of parameters
# Comments   : 
# See Also   : 
sub analyze_blastout {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('analyze_blastout() needs a $param_href') unless @_ == 1;
    my ($p_href) = @_;

    # get new handle
    my $dbh = _dbi_connect($p_href);

    # create blastout_analysis table
    my $blastout_analysis = sprintf( qq{
    CREATE TABLE %s (
	id INT UNSIGNED AUTO_INCREMENT NOT NULL,
	ps TINYINT UNSIGNED NOT NULL,
	prot_id VARCHAR(40) NOT NULL,
	ti INT UNSIGNED NOT NULL,
	species_name VARCHAR(200) NULL,
	PRIMARY KEY(id),
	KEY(ti),
	KEY(prot_id)
	)}, $dbh->quote_identifier($p_href->{blastout_analysis}) );
	_create_table( { table_name => $p_href->{blastout_analysis}, dbh => $dbh, query => $blastout_analysis } );
	$log->trace("Report: $blastout_analysis");

#	# create blastout_analysis_all table
#    my $blastout_analysis_all = sprintf( qq{
#    CREATE TABLE %s (
#	id INT UNSIGNED AUTO_INCREMENT NOT NULL,
#	ps TINYINT UNSIGNED NOT NULL,
#	prot_id VARCHAR(40) NOT NULL,
#	ti INT UNSIGNED NOT NULL,
#	species_name VARCHAR(200) NULL,
#	PRIMARY KEY(id),
#	KEY(ti),
#	KEY(prot_id)
#	)}, $dbh->quote_identifier("$p_href->{blastout_analysis}_all") );
#	_create_table( { table_name => "$p_href->{blastout_analysis}_all", dbh => $dbh, query => $blastout_analysis_all } );
#	$log->trace("Report: $blastout_analysis_all");

    # get columns from MAP table to iterate on phylostrata
	my $select_ps_from_map = sprintf( qq{
	SELECT DISTINCT phylostrata FROM %s ORDER BY phylostrata
	}, $dbh->quote_identifier($p_href->{map}) );
	
	# get column phylostrata to array to iterate insert query on them
	my @ps = map { $_->[0] } @{ $dbh->selectall_arrayref($select_ps_from_map) };
	$log->trace( 'Returned phylostrata: {', join('}{', @ps), '}' );
	
	# to insert blastout_analysis and blastout_analysis_all table
	_insert_blastout_analysis( { dbh => $dbh, phylostrata => \@ps, %{$p_href} } );
	
    $dbh->disconnect;
    return;
}


### INTERNAL UTILITY ###
# Usage      : _insert_blastout_analysis( { dbh => $dbh, pphylostrata => \@ps, %{$p_href} } );
# Purpose    : to insert blastout_analysis and blastout_analysis_all table
# Returns    : nothing
# Parameters : 
# Throws     : croaks if wrong number of parameters
# Comments   : part of --mode=blastout_analyze
# See Also   : 
sub _insert_blastout_analysis {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_insert_blastout_analysis() needs a $param_href') unless @_ == 1;
    my ($p_href) = @_;

#	# create insert query for each phylostratum (blastout_analysis_all table)
#	my $insert_ps_query_all = qq{
#	INSERT INTO $p_href->{blastout_analysis}_all (ps, prot_id, ti, species_name)
#		SELECT DISTINCT map.phylostrata, map.prot_id, blout.ti, na.species_name
#		FROM $p_href->{blastout} AS blout
#		INNER JOIN $p_href->{map} AS map ON blout.prot_id = map.prot_id
#		INNER JOIN $p_href->{names} AS na ON blout.ti = na.ti
#		WHERE map.phylostrata = ?
#	};
#	my $sth_all = $p_href->{dbh}->prepare($insert_ps_query_all);
#	$log->trace("Report: $insert_ps_query_all");
#	
#	#iterate for each phylostratum and insert into blastout_analysis_all
#	foreach my $ps (@{ $p_href->{phylostrata} }) {
#	    eval { $sth_all->execute($ps) };
#		my $rows = $sth_all->rows;
#	    $log->error( qq{Error: inserting into "$p_href->{blastout_analysis}_all" failed for ps:$ps: $@} ) if $@;
#	    $log->debug( qq{Action: table "$p_href->{blastout_analysis}_all" for ps:$ps inserted $rows rows} ) unless $@;
#	}

	# create insert query for each phylostratum (blastout_analysis table)
	my $insert_ps_query = qq{
	INSERT INTO $p_href->{blastout_analysis} (ps, prot_id, ti, species_name)
		SELECT DISTINCT map.phylostrata, map.prot_id, blout.ti, na.species_name
		FROM $p_href->{blastout} AS blout
		INNER JOIN $p_href->{map} AS map ON blout.prot_id = map.prot_id
		INNER JOIN $p_href->{names} AS na ON blout.ti = na.ti
		INNER JOIN $p_href->{analyze_genomes} AS an ON blout.ti = an.ti
		WHERE map.phylostrata = ? AND an.phylostrata = ?
	};
	my $sth = $p_href->{dbh}->prepare($insert_ps_query);
	$log->trace("Report: $insert_ps_query");
	
	#iterate for each phylostratum and insert into blastout_analysis
	foreach my $ps (@{ $p_href->{phylostrata} }) {
	    eval { $sth->execute($ps, $ps) };
	    my $rows = $sth->rows;
	    $log->error( qq{Error: inserting into $p_href->{blastout_analysis} failed for ps:$ps: $@} ) if $@;
	    $log->debug( qq{Action: table $p_href->{blastout_analysis} for ps:$ps inserted $rows rows} ) unless $@;
	}

    return;
}


### INTERFACE SUB ###
# Usage      : --mode=report_per_ps
# Purpose    : reports blast output analysis per species (ti) per phylostrata
# Returns    : nothing
# Parameters : 
# Throws     : croaks if wrong number of parameters
# Comments   : 
# See Also   : 
sub report_per_ps {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('report_per_ps() needs a $p_href') unless @_ == 1;
    my ($p_href) = @_;

    my $dbh = _dbi_connect($p_href);

	# name the report_per_ps table
	my $report_per_ps_tbl = "$p_href->{report_per_ps}";

	# create summary per phylostrata per species
    my $report_per_ps = sprintf( qq{
    CREATE TABLE %s (
	id INT UNSIGNED AUTO_INCREMENT NOT NULL,
	ps TINYINT UNSIGNED NOT NULL,
	ti INT UNSIGNED NOT NULL,
	species_name VARCHAR(200) NULL,
	gene_hits_per_species INT UNSIGNED NOT NULL,
	gene_list MEDIUMTEXT NOT NULL,
	PRIMARY KEY(id),
	KEY(species_name)
	)}, $dbh->quote_identifier($report_per_ps_tbl) );
	_create_table( { table_name => $report_per_ps_tbl, dbh => $dbh, query => $report_per_ps } );
	$log->trace("Report: $report_per_ps");

	#for large GROUP_CONCAT selects
	my $value = 16_777_215;
	my $variables_query = qq{
	SET SESSION group_concat_max_len = $value
	};
	eval { $dbh->do($variables_query) };
    $log->error( "Error: changing SESSION group_concat_max_len=$value failed: $@" ) if $@;
    $log->debug( "Report: changing SESSION group_concat_max_len=$value succeeded" ) unless $@;

	# create insert query
	my $insert_report_per_ps = sprintf( qq{
		INSERT INTO %s (ps, ti, species_name, gene_hits_per_species, gene_list)
		SELECT ps, ti, species_name, COUNT(species_name) AS gene_hits_per_species, 
		GROUP_CONCAT(prot_id ORDER BY prot_id) AS gene_list
		FROM %s
		GROUP BY species_name
		ORDER BY ps, gene_hits_per_species, species_name
	}, $dbh->quote_identifier($report_per_ps_tbl), $dbh->quote_identifier($p_href->{blastout_analysis}) );
	my $rows;
	eval { $rows = $dbh->do($insert_report_per_ps) };
    $log->error( "Error: inserting into $report_per_ps_tbl failed: $@" ) if $@;
    $log->debug( "Action: table $report_per_ps_tbl inserted $rows rows" ) unless $@;
	$log->trace("$insert_report_per_ps");

    $dbh->disconnect;

    return;
}

### INTERFACE SUB ###
# Usage      : --mode=exclude_ti_from_blastout();
# Purpose    : excludes tax_id from blastout file and saves new file to disk
# Returns    : nothing
# Parameters : ($param_href)
# Throws     : croaks for parameters
# Comments   : 
# See Also   : 
sub exclude_ti_from_blastout {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak( 'exclude_ti_from_blastout() needs a hash_ref' ) unless @_ == 1;
    my ($param_href) = @_;

    my $infile   = $param_href->{infile} or $log->logcroak( 'no $infile specified on command line!' );
    my $tax_id   = $param_href->{tax_id} or $log->logcroak( 'no $tax_id specified on command line!' );
    my $blastout = path($infile)->basename;
    my $blastout_good = path(path($infile)->parent, $blastout . "_good");
	my $blastout_bad  = path(path($infile)->parent, $blastout . "_bad");
    
    open( my $blastout_fh,      "< :encoding(ASCII)", $infile )        or $log->logdie( "Blastout file $infile not found:$!" );
    open( my $blastout_good_fh, "> :encoding(ASCII)", $blastout_good ) or $log->logdie( "good output $blastout_good:$!" );
    open( my $blastout_bad_fh,  "> :encoding(ASCII)", $blastout_bad )  or $log->logdie( "bad output $blastout_bad:$!" );


    #in blastout
    #ENSG00000151914|ENSP00000354508    pgi|34252924|ti|9606|pi|0|  100.00  7461    0   0   1   7461    1   7461    0.0 1.437e+04
    
    local $.;
	my $i_good = 0;
	my $i_bad  = 0;
    while ( <$blastout_fh> ) {
        chomp;
        my (undef, $id, undef, undef, undef, undef, undef, undef, undef, undef, undef, undef) = split "\t", $_;
		my (undef, undef, undef, $ti, undef, undef) = split(/\|/, $id);   #pgi|0000000000042857453|ti|428574|pi|0|
		# any string that is not a single space (chr(32)) will implicitly be used as a regex, so split '|' will still be split /|/ and thus equal split //

		#progress tracker
        if ($. % 1000000 == 0) {
            $log->trace( "$. lines processed!" );
        }
		
		#if found bad id exclude from blastout
		if ($ti == $tax_id) {
			$i_bad++;
			say {$blastout_bad_fh} $_;
		}
		else {
			$i_good++;
			say {$blastout_good_fh} $_;
		}
			
    }
	#give info about what you did
    $log->info( "Report: file $blastout read successfully with $. lines" );
    $log->info( "Report: file $blastout_good printed successfully with $i_good lines" );
    $log->info( "Report: file $blastout_bad printed successfully with $i_bad lines" );

	close $blastout_fh;
	close $blastout_good_fh;
	close $blastout_bad_fh;

    return;
}


### INTERFACE SUB ###
# Usage      : --mode=report_per_ps_unique
# Purpose    : reports blast output analysis per species (ti) per phylostrata and unique hits
# Returns    : nothing
# Parameters : 
# Throws     : croaks if wrong number of parameters
# Comments   : 
# See Also   : 
sub report_per_ps_unique {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('report_per_ps_unique() needs a $p_href') unless @_ == 1;
    my ($p_href) = @_;

    my $out = $p_href->{out} or $log->logcroak('no $out specified on command line!');
    my $dbh = _dbi_connect($p_href);

	# name the report_per_ps table
	my $report_per_ps_tbl = "$p_href->{report_per_ps}";

	# create summary per phylostrata per species
    my $report_per_ps_alter = sprintf( qq{
    ALTER TABLE %s ADD COLUMN hits1 INT, ADD COLUMN hits2 INT, ADD COLUMN hits3 INT, ADD COLUMN hits4 INT, ADD COLUMN hits5 INT, 
	ADD COLUMN hits6 INT, ADD COLUMN hits7 INT, ADD COLUMN hits8 INT, ADD COLUMN hits9 INT, ADD COLUMN hits10 INT, 
	ADD COLUMN list1 MEDIUMTEXT, ADD COLUMN list2 MEDIUMTEXT, ADD COLUMN list3 MEDIUMTEXT, ADD COLUMN list4 MEDIUMTEXT, ADD COLUMN list5 MEDIUMTEXT,
	ADD COLUMN list6 MEDIUMTEXT, ADD COLUMN list7 MEDIUMTEXT, ADD COLUMN list8 MEDIUMTEXT, ADD COLUMN list9 MEDIUMTEXT, ADD COLUMN list10 MEDIUMTEXT
	}, $dbh->quote_identifier($report_per_ps_tbl) );
	$log->trace("Report: $report_per_ps_alter");
	eval { $dbh->do($report_per_ps_alter) };
    $log->error( "Error: table $report_per_ps_tbl failed to alter: $@" ) if $@;
    $log->debug( "Report: table $report_per_ps_tbl alter succeeded" ) unless $@;

	#for large GROUP_CONCAT selects
	my $value = 16_777_215;
	my $variables_query = qq{
	SET SESSION group_concat_max_len = $value
	};
	eval { $dbh->do($variables_query) };
    $log->error( "Error: changing SESSION group_concat_max_len=$value failed: $@" ) if $@;
    $log->debug( "Report: changing SESSION group_concat_max_len=$value succeeded" ) unless $@;

    # get columns from REPORT_PER_PS table to iterate on phylostrata
	my $select_ps = sprintf( qq{
	SELECT DISTINCT ps FROM %s ORDER BY ps
	}, $dbh->quote_identifier($report_per_ps_tbl) );
	
	# get column phylostrata to array to iterate insert query on them
	my @ps = map { $_->[0] } @{ $dbh->selectall_arrayref($select_ps) };
	$log->trace( 'Returned phylostrata: {', join('}{', @ps), '}' );

	# prepare insert query
	my $ins_hits = sprintf( qq{
	UPDATE %s
	SET hits1 = ?, hits2 = ?, hits3 = ?, hits4 = ?, hits5 = ?, hits6 = ?, hits7 = ?, hits8 = ?, hits9 = ?, hits10 = ?, 
	list1 = ?, list2 = ?, list3 = ?, list4 = ?, list5 = ?, list6 = ?, list7 = ?, list8 = ?, list9 = ?, list10 = ?
	WHERE ti = ?
	}, $dbh->quote_identifier($report_per_ps_tbl) );
	my $sth = $dbh->prepare($ins_hits);

	# insert hits and genelists into database
	foreach my $ps (@ps) {

		#get gene_list from db
		my $select_gene_list_from_report = sprintf( qq{
	    SELECT DISTINCT ti, gene_list
		FROM %s
		WHERE ps = $ps
		ORDER BY gene_hits_per_species
	    }, $dbh->quote_identifier($report_per_ps_tbl) );
	    my %ti_genelist_h = map { $_->[0], $_->[1]} @{$dbh->selectall_arrayref($select_gene_list_from_report)};

		# get ti list sorted by gene_hits_per_species
		my @ti = map { $_->[0] } @{ $dbh->selectall_arrayref($select_gene_list_from_report) };

		# transform gene_list to array and push all arrays into single array
		my @full_genelist;
		foreach my $ti (@ti) {
			my @gene_list_a = split ",", $ti_genelist_h{$ti};
			$ti_genelist_h{$ti} = \@gene_list_a;
			push @full_genelist, @gene_list_a;
		}

		# get count of each prot_id
		my %gene_count;
		foreach my $prot_id (@full_genelist) {
			$gene_count{$prot_id}++;
		}

		# get unique count per tax_id
		foreach my $ti (@ti) {
			my @ti_genelist = @{ $ti_genelist_h{$ti} };
			my ($ti_unique, $ti2, $ti3, $ti4, $ti5, $ti6, $ti7, $ti8, $ti9, $ti10) = (0) x 11;
			my ($ti_uniq_genes, $ti2g, $ti3g, $ti4g, $ti5g, $ti6g, $ti7g, $ti8g, $ti9g, $ti10g) = ('') x 11;

			# do the calculation here (tabulated ternary) 10 and 10+hits go to hits10
			foreach my $prot_id (@ti_genelist) {
				$gene_count{$prot_id} == 1 ? do {$ti_unique++; $ti_uniq_genes .= ',' . $prot_id;} : 
				$gene_count{$prot_id} == 2 ? do {$ti2++; $ti2g .= ',' . $prot_id;}                : 
				$gene_count{$prot_id} == 3 ? do {$ti3++; $ti3g .= ',' . $prot_id;}                : 
				$gene_count{$prot_id} == 4 ? do {$ti4++; $ti4g .= ',' . $prot_id;}                : 
				$gene_count{$prot_id} == 5 ? do {$ti5++; $ti5g .= ',' . $prot_id;}                : 
				$gene_count{$prot_id} == 6 ? do {$ti6++; $ti6g .= ',' . $prot_id;}                : 
				$gene_count{$prot_id} == 7 ? do {$ti7++; $ti7g .= ',' . $prot_id;}                : 
				$gene_count{$prot_id} == 8 ? do {$ti8++; $ti8g .= ',' . $prot_id;}                : 
				$gene_count{$prot_id} == 9 ? do {$ti9++; $ti9g .= ',' . $prot_id;}                : 
				                                                                                    do {$ti10++; $ti10g .= ',' . $prot_id;};
			}

			# remove comma at start
			foreach my $genelist ($ti_uniq_genes, $ti2g, $ti3g, $ti4g, $ti5g, $ti6g, $ti7g, $ti8g, $ti9g, $ti10g) {
				$genelist =~ s/\A,(.+)\z/$1/;
			}

			# insert into db
			$sth->execute($ti_unique, $ti2, $ti3, $ti4, $ti5, $ti6, $ti7, $ti8, $ti9, $ti10, $ti_uniq_genes, $ti2g, $ti3g, $ti4g, $ti5g, $ti6g, $ti7g, $ti8g, $ti9g, $ti10g, $ti);
			#say "TI:$ti\tuniq:$ti_unique\tti2:$ti2\tti3:$ti3\tti4:$ti4\tti5:$ti5";
			#say "TI:$ti\tuniq:$ti_uniq_genes\tti2:$ti2g\tti3:$ti3g\tti4:$ti4g\tti5:$ti5g";
		}

		$log->debug("Report: inserted ps $ps");
	}   # end foreach ps
	
	#export to tsv file
	my $out_report_per_ps = path($out, $report_per_ps_tbl);
	if (-f $out_report_per_ps ) {
		unlink $out_report_per_ps and $log->warn( "Warn: file $out_report_per_ps found and unlinked" );
	}
	else {
		$log->trace( "Action: file $out_report_per_ps will be created by SELECT INTO OUTFILE" );
	}
	my $export_report_per_ps = qq{
		SELECT * FROM $report_per_ps_tbl
		INTO OUTFILE '$out_report_per_ps' } 
		. q{
		FIELDS TERMINATED BY '\t'
		LINES TERMINATED BY '\n';
	};

	my $r_ex;
    eval { $r_ex = $dbh->do($export_report_per_ps) };
    $log->error( "Error: exporting $report_per_ps_tbl to $out_report_per_ps failed: $@" ) if $@;
    $log->debug( "Action: table $report_per_ps_tbl exported $r_ex rows to $out_report_per_ps" ) unless $@;

	$sth->finish;
    $dbh->disconnect;

    return;
}



### INTERFACE SUB ###
# Usage      : --mode=import_blastout_full
# Purpose    : loads full BLAST output to MySQL database (no duplicates)
# Returns    : nothing
# Parameters : ( $param_href )
# Throws     : croaks for parameters
# Comments   : it removes duplicates (same tax_id) per gene
# See Also   : utility sub _extract_blastout()
sub import_blastout_full {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak( 'import_blastout_full() needs a hash_ref' ) unless @_ == 1;
    my ($param_href) = @_;

    my $infile = $param_href->{infile} or $log->logcroak('no $infile specified on command line!');
    my $table           = path($infile)->basename;
    $table =~ s/\./_/g;    #for files that have dots in name
    my $blastout_import = path($infile . "_formated");

    #first shorten the blastout file and extract useful columns
    _extract_blastout_full( { infile => $infile, blastout_import => $blastout_import } );

    #get new handle
    my $dbh = _dbi_connect($param_href);

    #create table
    my $create_query = qq{
    CREATE TABLE IF NOT EXISTS $table (
	id INT UNSIGNED AUTO_INCREMENT NOT NULL,
    prot_id VARCHAR(40) NOT NULL,
    ti INT UNSIGNED NOT NULL,
    pgi CHAR(19) NOT NULL,
    hit VARCHAR(40) NOT NULL,
    col3 FLOAT NOT NULL,
    col4 INT UNSIGNED NOT NULL,
    col5 INT UNSIGNED NOT NULL,
    col6 INT UNSIGNED NOT NULL,
    col7 INT UNSIGNED NOT NULL,
    col8 INT UNSIGNED NOT NULL,
    col9 INT UNSIGNED NOT NULL,
    col10 INT UNSIGNED NOT NULL,
    evalue REAL NOT NULL,
	bitscore FLOAT NOT NULL,
	PRIMARY KEY(id)
    )};
    _create_table( { table_name => $table, dbh => $dbh, query => $create_query } );

    #import table
    my $load_query = qq{
    LOAD DATA INFILE '$blastout_import'
    INTO TABLE $table } . q{ FIELDS TERMINATED BY '\t'
    LINES TERMINATED BY '\n' 
    (prot_id, ti, pgi, hit, col3, col4, col5, col6, col7, col8, col9, col10, evalue, bitscore)
    };
	$log->trace("$load_query");
    eval { $dbh->do( $load_query, { async => 1 } ) };

    # check status while running
    my $dbh_check             = _dbi_connect($param_href);
    until ( $dbh->mysql_async_ready ) {
        my $processlist_query = qq{
        SELECT TIME, STATE FROM INFORMATION_SCHEMA.PROCESSLIST
        WHERE DB = ? AND INFO LIKE 'LOAD DATA INFILE%';
        };
        my ( $time, $state );
        my $sth = $dbh_check->prepare($processlist_query);
        $sth->execute($param_href->{database});
        $sth->bind_columns( \( $time, $state ) );
        while ( $sth->fetchrow_arrayref ) {
            my $print = sprintf( "Time running:%d sec\tSTATE:%s\n", $time, $state );
            $log->trace( $print );
            sleep 10;
        }
    }
    my $rows;
	eval { $rows = $dbh->mysql_async_result; };
    $log->info( "Action: import inserted $rows rows!" ) unless $@;
    $log->error( "Error: loading $table failed: $@" ) if $@;

    # add index
    my $alter_query = qq{
    ALTER TABLE $table ADD INDEX protx(prot_id), ADD INDEX tix(ti)
    };
    eval { $dbh->do( $alter_query, { async => 1 } ) };

    # check status while running
    my $dbh_check2            = _dbi_connect($param_href);
    until ( $dbh->mysql_async_ready ) {
        my $processlist_query = qq{
        SELECT TIME, STATE FROM INFORMATION_SCHEMA.PROCESSLIST
        WHERE DB = ? AND INFO LIKE 'ALTER%';
        };
        my ( $time, $state );
        my $sth = $dbh_check2->prepare($processlist_query);
        $sth->execute($param_href->{database});
        $sth->bind_columns( \( $time, $state ) );
        while ( $sth->fetchrow_arrayref ) {
            my $print = sprintf( "Time running:%d sec\tSTATE:%s\n", $time, $state );
            $log->trace( $print );
            sleep 10;
        }
    }

    #report success or failure
    $log->error( "Error: adding index tix on $table failed: $@" ) if $@;
    $log->info( "Action: Indices protx and tix on $table added successfully!" ) unless $@;
	
	#delete file used to import so it doesn't use disk space
	#unlink $blastout_import and $log->warn("File $blastout_import unlinked!");

    return;
}

### INTERNAL UTILITY ###
# Usage      : _extract_blastout_full( { infile => $infile, blastout_import => $blastout_import } );
# Purpose    : removes duplicates per tax_id from blastout file and saves blastout into file
# Returns    : nothing
# Parameters : ($param_href)
# Throws     : croaks for parameters
# Comments   : needed for --mode=import_blastout_full()
# See Also   : import_blastout_full()
sub _extract_blastout_full {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak( 'extract_blastout_full() needs {hash_ref}' ) unless @_ == 1;
    my ($extract_href) = @_;

    open( my $blastout_fh, "< :encoding(ASCII)", $extract_href->{infile} ) or $log->logdie( "Error: BLASTout file not found:$!" );
    open( my $blastout_fmt_fh, "> :encoding(ASCII)", $extract_href->{blastout_import} ) or $log->logdie( "Error: BLASTout file can't be created:$!" );

    # needed for filtering duplicates
    # idea is that duplicates come one after another
    my $prot_prev    = '';
    my $pgi_prev     = 0;
    my $ti_prev      = 0;
	my $formated_cnt = 0;

    # in blastout
    #ENSG00000151914|ENSP00000354508    pgi|34252924|ti|9606|pi|0|  100.00  7461    0   0   1   7461    1   7461    0.0 1.437e+04
    
	$log->debug( "Report: started processing of $extract_href->{infile}" );
    local $.;
    while ( <$blastout_fh> ) {
        chomp;

		my ($prot_id, $hit, $col3, $col4, $col5, $col6, $col7, $col8, $col9, $col10, $evalue, $bitscore) = split "\t", $_;
		my ($pgi, $ti) = $hit =~ m{pgi\|(\d+)\|ti\|(\d+)\|pi\|(?:\d+)\|};

        # check for duplicates for same gene_id with same tax_id and pgi that differ only in e_value
        if (  "$prot_prev" . "$pgi_prev" . "$ti_prev" ne "$prot_id" . "$pgi" . "$ti" ) {
            say {$blastout_fmt_fh} $prot_id, "\t", $ti, "\t", $pgi,  "\t$hit\t$col3\t$col4\t$col5\t$col6\t$col7\t$col8\t$col9\t$col10\t$evalue\t$bitscore";
			$formated_cnt++;
        }

        # set found values for next line to check duplicates
        $prot_prev = $prot_id;
        $pgi_prev  = $pgi;
        $ti_prev   = $ti;

		# show progress
        if ($. % 1000000 == 0) {
            $log->trace( "$. lines processed!" );
        }

    }   # end while reading blastout

    $log->info( "Report: file $extract_href->{blastout_import} printed successfully with $formated_cnt lines (from $. original lines)" );

    return;
}


### INTERFACE SUB ###
# Usage      : --mode=import_blastdb
# Purpose    : loads BLAST database to MySQL database from compressed file using named pipe
# Returns    : nothing
# Parameters : ( $param_href )
# Throws     : croaks for parameters
# Comments   : works on compressed file
# See Also   : 
sub import_blastdb {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('import_blastdb() needs a hash_ref') unless @_ == 1;
    my ($param_href) = @_;

    my $infile = $param_href->{infile} or $log->logcroak('no $infile specified on command line!');
    my $table = path($infile)->basename;
    ($table) = $table =~ m/\A(.+)\.gz\z/;
    $table =~ s/\./_/g;    #for files that have dots in name
    my $out = path($infile)->parent;

    # get date for named pipe file naming
    my $now = DateTime::Tiny->now;
    my $date
      = $now->year . '_' . $now->month . '_' . $now->day . '_' . $now->hour . '_' . $now->minute . '_' . $now->second;

    # delete pipe if it exists
    my $load_file = path( $out, "blastdb_named_pipe_${date}" );    #file for LOAD DATA INFILE
    if ( -p $load_file ) {
        unlink $load_file and $log->trace("Action: named pipe $load_file removed!");
    }

    #make named pipe
    mkfifo( $load_file, 0666 ) or $log->logdie("Error: mkfifo $load_file failed: $!");

    # open blastdb compressed file for reading
    open my $blastdb_fh, "<:gzip", $infile or $log->logdie("Can't open gzipped file $infile: $!");

    #start 2 processes (one for Perl-child and MySQL-parent)
    my $pid = fork;

    if ( !defined $pid ) {
        $log->logdie("Error: cannot fork: $!");
    }

    elsif ( $pid == 0 ) {

        # Child-client process
        $log->warn("Action: Perl-child-client starting...");

        # open named pipe for writing (gziped file --> named pipe)
        open my $blastdb_pipe_fh, "+<:encoding(ASCII)", $load_file or die $!;    #+< mode=read and write

        # define new block for reading blocks of fasta
        {
            local $/ = ">pgi";    #look in larger chunks between >gi (solo > found in header so can't use)
            local $.;             #gzip count
            my $out_cnt = 0;      #named pipe count

            # print to named pipe
          PIPE:
            while (<$blastdb_fh>) {
                chomp;

                #print $blastdb_pipe_fh "$_";
                #say '{', $_, '}';
                next PIPE if $_ eq '';    #first iteration is empty?

                # extract pgi, prot_name and fasta + fasta
                my ( $prot_id, $prot_name, $fasta ) = $_ =~ m{\A([^\t]+)\t([^\n]+)\n(.+)\z}smx;

                # check for missing $prot_name in file
                my $header;
                if ( !$prot_id ) {
                    print "UNDEFINED:$_\n";
                    ( $header, $fasta ) = $_ =~ m{\A([^\n]+)\n(.+)\z}smx;
                    next PIPE if !$fasta;   # skip if there are is no sequence

                    #print "HEADER:$header\tFASTA:$fasta\n";
                    eval { ( $prot_id, $prot_name ) = split /\t/, $header; };
                    if ($@) {
                        $prot_id   = $header;
                        $prot_name = '';
                    }
                    print "PROT_ID:$prot_id\tPROT_NAME:$prot_name\n";
                }

                #pgi removed as record separator (return it back)
                $prot_id = 'pgi' . $prot_id;
                my ( $pgi, $ti ) = $prot_id =~ m{pgi\|(\d+)\|ti\|(\d+)\|pi\|(?:\d+)\|};

                # remove illegal chars from fasta and upercase it
                $fasta =~ s/\R//g;        #delete multiple newlines (all vertical and horizontal space)
                $fasta = uc $fasta;       #uppercase fasta
                $fasta =~ tr{A-Z}{}dc;    #delete all special characters (all not in A-Z)

                # print to pipe
                print {$blastdb_pipe_fh} "$prot_id\t$pgi\t$ti\t$prot_name\t$fasta\n";
                $out_cnt++;

                #progress tracker for blastdb file
                if ( $. % 1000000 == 0 ) {
                    $log->trace("$. lines processed!");
                }
            }
            my $blastdb_file_line_cnt = $. - 1;    #first line read empty (don't know why)
            $log->warn("Report: file $infile has $blastdb_file_line_cnt fasta records!");
            $log->warn("Action: file $load_file written with $out_cnt lines/fasta records!");
        }    #END block writing to pipe

        $log->warn("Action: Perl-child-client terminating :)");
        exit 0;
    }
    else {
        # MySQL-parent process
        $log->warn("Action: MySQL-parent process, waiting for child...");

        # SECOND PART: loading named pipe into db
        my $database = $param_href->{database} or $log->logcroak('no $database specified on command line!');

        # get new handle
        my $dbh = _dbi_connect($param_href);

        # create a table to load into
        my $create_query = sprintf(
            qq{
        CREATE TABLE %s (
        id INT UNSIGNED AUTO_INCREMENT NOT NULL,
        prot_id VARCHAR(40) NOT NULL,
        pgi CHAR(19) NOT NULL,
        ti INT UNSIGNED NOT NULL,
        prot_name VARCHAR(200) NOT NULL,
        fasta MEDIUMTEXT NOT NULL,
        PRIMARY KEY(ti, id),
        KEY id (id)
        )}, $dbh->quote_identifier($table)
        );
        _create_table( { table_name => $table, dbh => $dbh, query => $create_query, %{$param_href} } );
        $log->trace("Report: $create_query");

        #import table
        my $load_query = qq{
        LOAD DATA INFILE '$load_file'
        INTO TABLE $table } . q{ FIELDS TERMINATED BY '\t'
        LINES TERMINATED BY '\n'
        (prot_id, pgi, ti, prot_name, fasta)
        };
        eval { $dbh->do( $load_query, { async => 1 } ) };

        #check status while running LOAD DATA INFILE
        {
            my $dbh_check = _dbi_connect($param_href);
            until ( $dbh->mysql_async_ready ) {
                my $processlist_query = qq{
                SELECT TIME, STATE FROM INFORMATION_SCHEMA.PROCESSLIST
                WHERE DB = ? AND INFO LIKE 'LOAD DATA INFILE%';
                };
                my $sth = $dbh_check->prepare($processlist_query);
                $sth->execute($database);
                my ( $time, $state );
                $sth->bind_columns( \( $time, $state ) );
                while ( $sth->fetchrow_arrayref ) {
                    my $process = sprintf( "Time running:%d sec\tSTATE:%s\n", $time, $state );
                    $log->trace($process);
                    sleep 10;
                }
            }
        }    #end check LOAD DATA INFILE
        my $rows = $dbh->mysql_async_result;
        $log->info("Report: import inserted $rows rows!");
        $log->error("Report: loading $table failed: $@") if $@;

        # add index
        my $alter_query = qq{
        ALTER TABLE $table ADD INDEX prot_namex(prot_name)
        };
        eval { $dbh->do( $alter_query, { async => 1 } ) };

        # check status while running
        my $dbh_check2 = _dbi_connect($param_href);
        until ( $dbh->mysql_async_ready ) {
            my $processlist_query = qq{
            SELECT TIME, STATE FROM INFORMATION_SCHEMA.PROCESSLIST
            WHERE DB = ? AND INFO LIKE 'ALTER%';
            };
            my ( $time, $state );
            my $sth = $dbh_check2->prepare($processlist_query);
            $sth->execute( $param_href->{database} );
            $sth->bind_columns( \( $time, $state ) );
            while ( $sth->fetchrow_arrayref ) {
                my $print = sprintf( "Time running:%d sec\tSTATE:%s\n", $time, $state );
                $log->trace($print);
                sleep 10;
            }
        }

        #report success or failure
        $log->error("Error: adding indices prot_namex on {$table} failed: $@") if $@;
        $log->info("Action: indices prot_namex on {$table} added successfully!") unless $@;

        $dbh->disconnect;

        # communicate with child process
        waitpid $pid, 0;
    }
    $log->warn("MySQL-parent process end after child has finished");
    unlink $load_file and $log->warn("Action: named pipe $load_file removed!");

    return;
}


### INTERFACE SUB ###
# Usage      : import_reports( $param_href );
# Purpose    : to import expanded reports per species into MySQL database
# Returns    : nothing
# Parameters : 
# Throws     : croaks if wrong number of parameters
# Comments   : files are exported from ClickHouse and in gzip format
# See Also   : 
sub import_reports {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('import_reports() needs a $param_href') unless @_ == 1;
    my ($param_href) = @_;

    my $in = $param_href->{in} or $log->logcroak('no $in specified on command line!');
    my $max_processes = defined $param_href->{max_processes} ? $param_href->{max_processes} : 1;

    # collect expanded files
    my @exp_files = File::Find::Rule->file()->name('*report_per_species_expanded.TabSeparated.gz')->in($in);
    @exp_files = sort { $a cmp $b } @exp_files;
	my $found_exp = @exp_files;
    my $exp_files_print = sprintf( Data::Dumper->Dump( [ \@exp_files ], ["found $found_exp expanded reports"] ) );
    $log->debug("$exp_files_print");

    # helping hash to remember tis
    my %name_ti_pair = (
        ac  => 1257118,
        ag  => 936046,
        am  => 7460,
        an  => 28377,
        aq  => 400682,
        at  => 13333,
        ath => 3702,
        bd  => 684364,
        bm  => 7091,
        ce  => 6239,
        cg  => 29159,
        ci  => 7719,
        co  => 595528,
        dd  => 352472,
        dm  => 7227,
        dp  => 6669,
        dr  => 7955,
        ec  => 284813,
        eh  => 280463,
        gg  => 9031,
        gl  => 184922,
        gt  => 905079,
        hs  => 9606,
        lc  => 7897,
        lm  => 347515,
        mb  => 431895,
        ml  => 27923,
        mm  => 10090,
        mo  => 242507,
        nv  => 45351,
        os  => 39947,
        pf  => 36329,
        pi  => 403677,
        pm  => 7757,
        pop => 3694,
        pp  => 3218,
        pt  => 5888,
        sc  => 4932,
        sl  => 4081,
        sm  => 88036,
        sp  => 7668,
        spo => 284812,
        str => 126957,
        tv  => 412133,
        vv  => 29760,
        xt  => 8364,
        zm  => 4577,
    );

    $log->info("Report: parent PID $$ forking $max_processes processes");
    my $pm = Parallel::ForkManager->new($max_processes);

  LOOP:
    foreach my $exp (@exp_files) {
        my $exp_name = path($exp)->basename;
        ( my $organism ) = $exp_name =~ m/\A.+?\.(.+?)\_.+\z/;

        #make the fork
        my $pid = $pm->start and next LOOP;

        my $start = time;

        # create named pipe and extract into it (save space)
        my $load_pipe = path( $in, "${organism}_pipe" );
        unlink $load_pipe if -e $load_pipe;
        mkfifo( $load_pipe, 0666 ) or log->logdie("Error: mkfifo $load_pipe failed: $!");

        # extract to pipe
        my $cmd_gz = qq{pigz -c -d $exp > $load_pipe &};
        say "CMD:$cmd_gz";
        system($cmd_gz) and $log->logdie("Error: can't extract $exp to $load_pipe:$!");

        # now create table and load into it
        my $exp_tbl = _load_exp_into_db( { org => $organism, pipe => $load_pipe, %{$param_href} } );

        # update support table
        my $dbh      = _dbi_connect($param_href);
        my $update_q = qq{
	    UPDATE $param_href->{database}.support
        SET report_expanded = '$exp_name', report_expanded_tbl = '$exp_tbl'
        WHERE ti = $name_ti_pair{$organism} };

        my $rows;
        eval { $rows = $dbh->do($update_q) };
        $log->info("Report: updated $rows rows for organism: $organism!");
        $log->error("Report: updating support table for organism: $organism failed: $@") if $@;

        # delete pipe
        unlink $load_pipe if -e $load_pipe;

        # update expanded table
        _update_exp_tbl( { exp_tbl => $exp_tbl, %{$param_href} } );

        $pm->finish;    # Terminates the child process
    }
    $pm->wait_all_children;

    return;
}


### INTERNAL UTILITY ###
# Usage      : my $exp_tbl = _load_exp_into_db( { org => $organism, pipe => $load_pipe, %{$param_href} } );
# Purpose    : create table, load into it from MySQL
# Returns    : name of expanded table
# Parameters : 
# Throws     : croaks if wrong number of parameters
# Comments   : 
# See Also   : 
sub _load_exp_into_db {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_load_exp_into_db() needs a $param_href') unless @_ == 1;
    my ($param_href) = @_;

    my $database = $param_href->{database} or $log->logcroak('no $database specified on command line!');

    # get new handle
    my $dbh     = _dbi_connect($param_href);
    my $exp_tbl = "$param_href->{org}_report_per_species_expanded";

    # create a table to load into
    my $create_query = sprintf(
        qq{
    CREATE TABLE %s (
    ps TINYINT UNSIGNED NOT NULL,
    ti INT UNSIGNED NOT NULL,
    species_name VARCHAR(200) NOT NULL,
    gene_hits_per_species INT UNSIGNED NOT NULL,
    hits1 INT UNSIGNED NOT NULL,
    hits2 INT UNSIGNED NOT NULL,
    hits3 INT UNSIGNED NOT NULL,
    hits4 INT UNSIGNED NOT NULL,
    hits5 INT UNSIGNED NOT NULL,
    hits6 INT UNSIGNED NOT NULL,
    hits7 INT UNSIGNED NOT NULL,
    hits8 INT UNSIGNED NOT NULL,
    hits9 INT UNSIGNED NOT NULL,
    hits10 INT UNSIGNED NOT NULL,
    PRIMARY KEY(ti),
    KEY(species_name)
    )}, $dbh->quote_identifier($exp_tbl)
    );
    _create_table( { table_name => $exp_tbl, dbh => $dbh, query => $create_query, %{$param_href} } );
    $log->trace("Report: $create_query");

    #import table
    my $load_query = qq{
    LOAD DATA INFILE '$param_href->{pipe}'
    INTO TABLE $exp_tbl } . q{ FIELDS TERMINATED BY '\t'
    LINES TERMINATED BY '\n'
    (ps, ti,  species_name,  gene_hits_per_species,  @dummy,
    hits1, hits2,  hits3, hits4, hits5,  hits6,  hits7,  hits8,  hits9,  hits10,
    @dummy, @dummy, @dummy, @dummy, @dummy, @dummy, @dummy, @dummy, @dummy, @dummy, @dummy)
    };
    my $rows;
    eval { $rows = $dbh->do($load_query) };

    $log->info("Report: import inserted $rows rows!");
    $log->error("Report: loading $exp_tbl failed: $@") if $@;

    return $exp_tbl;
}


### INTERNAL UTILITY ###
# Usage      : _update_exp_tbl( $param_href );
# Purpose    : update expanded table with domains
# Returns    : nothing
# Parameters : 
# Throws     : croaks if wrong number of parameters
# Comments   : 
# See Also   : 
sub _update_exp_tbl {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_update_exp_tbl() needs a $param_href') unless @_ == 1;
    my ($param_href) = @_;

    my $dbh = _dbi_connect($param_href);

    # delete all not in ps1
    my $del_q = qq{
    DELETE exp FROM $param_href->{exp_tbl} AS exp
    WHERE ps NOT IN (1) };
    $log->trace("Report: $del_q");
    my $rows_del;
    eval { $rows_del = $dbh->do($del_q) };

    $log->info("Report: deleted all but ps1 from $param_href->{exp_tbl}");
    $log->error("Report: deleting all but ps1 from $param_href->{exp_tbl} failed: $@") if $@;

    # alter table add domain column
    my $alter_q = qq{
    ALTER TABLE $param_href->{exp_tbl} ADD COLUMN domain VARCHAR(20) };
    $log->trace("Report: $alter_q");
    eval { $dbh->do($alter_q) };

    $log->info("Report: added domain column to table $param_href->{exp_tbl}");
    $log->error("Report: altering table $param_href->{exp_tbl} failed: $@") if $@;

    # update exp_table with archaea
    my $update_archaea = qq{
    UPDATE $param_href->{exp_tbl} AS exp
    INNER JOIN archea AS kin ON exp.ti = kin.ti
    SET exp.domain = 'Archaea' };
    $log->trace("Report: $update_archaea");
    my $rows_a;
    eval { $rows_a = $dbh->do($update_archaea) };

    $log->info("Report: updated $rows_a Archaea species in $param_href->{exp_tbl}");
    $log->error("Report: updating Archaea species in $param_href->{exp_tbl} failed: $@") if $@;

    # update exp_table with cyanobacteria
    my $update_cyanobacteria = qq{
    UPDATE $param_href->{exp_tbl} AS exp
    INNER JOIN cyanobacteria AS kin ON exp.ti = kin.ti
    SET exp.domain = 'Cyanobacteria' };
    $log->trace("Report: $update_cyanobacteria");
    my $rows_c;
    eval { $rows_c = $dbh->do($update_cyanobacteria) };

    $log->info("Report: updated $rows_c Cyanobacteria species in $param_href->{exp_tbl}");
    $log->error("Report: updating Cyanobacteria species in $param_href->{exp_tbl} failed: $@") if $@;

    # update exp_table with archaea
    my $update_bacteria = qq{
    UPDATE $param_href->{exp_tbl} AS exp
    INNER JOIN bacteria AS kin ON exp.ti = kin.ti
    SET exp.domain = 'Bacteria' };
    $log->trace("Report: $update_bacteria");
    my $rows_b;
    eval { $rows_b = $dbh->do($update_bacteria) };

    $log->info("Report: updated $rows_b Bacteria species in $param_href->{exp_tbl}");
    $log->error("Report: updating Bacteria species in $param_href->{exp_tbl} failed: $@") if $@;

    return;
}


### INTERFACE SUB ###
# Usage      : --mode=top_hits
# Purpose    : selects top hits from blastout_uniq-report_per_ps_expanded tables per domain
# Returns    : name of the resulting table
# Parameters : $param_href
# Throws     : croaks if wrong number of parameters
# Comments   :
# See Also   :
sub top_hits {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('top_hits() needs a $param_href') unless @_ == 1;
    my ($param_href) = @_;

    # take top 10 if not defined on command line
    my $top_hits = defined $param_href->{top_hits} ? $param_href->{top_hits} : 10;
    my $top_hits_tbl = 'top_hits' . "$param_href->{top_hits}";

    # connect to database
    my $dbh = _dbi_connect($param_href);

    # create top_hits table
    my $create_top_hits_q = qq{
    CREATE TABLE $top_hits_tbl (
    org_of_origin VARCHAR(5) NOT NULL,
    ti INT UNSIGNED NOT NULL,
    species_name VARCHAR(200) NOT NULL,
    gene_hits_per_species INT UNSIGNED NOT NULL,
    domain VARCHAR(20) NOT NULL,
    hits1 INT UNSIGNED NOT NULL,
    hits2 INT UNSIGNED NOT NULL,
    hits3 INT UNSIGNED NOT NULL,
    hits4 INT UNSIGNED NOT NULL,
    hits5 INT UNSIGNED NOT NULL,
    hits6 INT UNSIGNED NOT NULL,
    hits7 INT UNSIGNED NOT NULL,
    hits8 INT UNSIGNED NOT NULL,
    hits9 INT UNSIGNED NOT NULL,
    hits10 INT UNSIGNED NOT NULL,
    PRIMARY KEY (org_of_origin, ti),
    KEY(species_name, domain)
    )
    };
    _create_table( { table_name => $top_hits_tbl, dbh => $dbh, query => $create_top_hits_q, %{$param_href} } );
    $log->trace("Report: $create_top_hits_q");

    # select all expanded tables in a support table
    my $select_exp_q = qq{ SELECT report_expanded_tbl FROM $param_href->{database}.support };
    my @exp_tables   = map { $_->[0] } @{ $dbh->selectall_arrayref($select_exp_q) };
    my $exp_print    = sprintf( Data::Dumper->Dump( [ \@exp_tables ], [qw(*report_expanded_tables)] ) );
    $log->debug("$exp_print");

    # select top N hits from table
    foreach my $exp_tbl (@exp_tables) {

        # skip empty rows
        next if ( $exp_tbl eq '' );

        # get organism short code
        ( my $organism ) = $exp_tbl =~ m/\A(.+?)\_.+\z/;

        # run for each domain
        foreach my $domain ( 'Archaea', 'Cyanobacteria', 'Bacteria' ) {
            my $ins_hits_q = qq{
            INSERT INTO $top_hits_tbl
            SELECT '$organism' AS org_of_origin, ti, species_name, gene_hits_per_species, domain, hits1, hits2, hits3, hits4, hits5, hits6, hits7, hits8, hits9, hits10
            FROM $exp_tbl
            WHERE domain = '$domain'
            ORDER BY gene_hits_per_species DESC
            LIMIT $top_hits
            };
            $log->trace($ins_hits_q);
            my $rows;
            eval { $rows = $dbh->do($ins_hits_q); };
            $log->info(
                "Action: {$param_href->{database}.$top_hits_tbl} inserted with {$rows} $domain species from {$exp_tbl}")
              unless $@;
            $log->error(
                "Error: inserting {$param_href->{database}.$top_hits_tbl} failed for $domain for {$exp_tbl}: $@")
              if $@;
        }
    }

    # create summary table for top hits
    _top_hits_cnt( { top_hits_tbl => $top_hits_tbl, %{$param_href} } );

    return $top_hits_tbl;
}


### INTERNAL UTILITY ###
# Usage      : _top_hits_cnt( { top_hits_tbl => $top_hits_tbl, %{$param_href} } );
# Purpose    : summary of top_hits table
# Returns    : nothing
# Parameters : 
# Throws     : croaks if wrong number of parameters
# Comments   : 
# See Also   : 
sub _top_hits_cnt {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_top_hits_cnt() needs a $param_href') unless @_ == 1;
    my ($param_href) = @_;

    # connect to database
    my $dbh = _dbi_connect($param_href);

    # create top_hits table
    my $create_top_hits_q = qq{
    CREATE TABLE $param_href->{top_hits_tbl}_cnt (
    domain VARCHAR(20) NOT NULL,
    ti INT UNSIGNED NOT NULL,
    species_name VARCHAR(200) NOT NULL,
    sp_cnt INT UNSIGNED NOT NULL,
    PRIMARY KEY(domain, ti)
    )
    SELECT domain, ti, species_name, COUNT(species_name) AS sp_cnt 
    FROM $param_href->{top_hits_tbl}
    GROUP BY species_name
    ORDER BY sp_cnt DESC;
    };
    _create_table( { table_name => "$param_href->{top_hits_tbl}_cnt", dbh => $dbh, query => $create_top_hits_q, %{$param_href} } );
    $log->trace("Report: $create_top_hits_q");

    return;
}


### INTERFACE SUB ###
# Usage      : --mode=reduce_blastout
# Purpose    : is to remove blast hits that are less than cuttof value (1, 2, ...)
# Returns    : nothing
# Parameters : (blastout, analyze and cuttoff from command line)
# Throws     : croaks if wrong number of parameters
# Comments   : 
# See Also   : 
sub reduce_blastout {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('reduce_blastout() needs a $param_href') unless @_ == 1;
    my ($param_href) = @_;

    my $out      = $param_href->{out}      or $log->logcroak('no $out specified on command line!');
    my $blastout = $param_href->{blastout} or $log->logcroak('no $blastout specified on command line!');
    my $stats    = $param_href->{stats}    or $log->logcroak('no $stats specified on command line!');

    # create SQLite database
    my $dbfile = path( $out, "blastout$$.db" );
    my %conn_attrs = (
        RaiseError         => 1,
        PrintError         => 0,
        AutoCommit         => 1,
        ShowErrorStatement => 1,
    );
    my $dbh = DBI->connect( "dbi:SQLite:dbname=$dbfile", "", "", \%conn_attrs );
    $log->info( 'Report: connected to {', $dbfile, '} by dbh ', $dbh );
    $dbh->do("PRAGMA journal_mode = WAL");      # write ahead journal
    $dbh->do("PRAGMA synchronous = OFF");       # sync is off
    $dbh->do("PRAGMA cache_size = 1000000");    # 1 GB (1 mil pages x 1 Kb page)

    # import analyze stats
    my $analyze_tbl = _import_stats( { %{$param_href}, dbh => $dbh } );

    # import part of blastout
    _import_blastout_partial( { %{$param_href}, dbh => $dbh, analyze_tbl => $analyze_tbl } );

    unlink $dbfile and $log->warn("Action: deleted SQLite database $dbfile");

    return;
}


### INTERNAL UTILITY ###
# Usage      : my $analyze_tbl = _import_stats( { %{$param_href}, dbh => $dbh } );
# Purpose    : import analyze file to SQLite database
# Returns    : $analyze_tbl name
# Parameters : stats file and database handle
# Throws     : croaks if wrong number of parameters
# Comments   : part of reduce_blastout()
# See Also   : 
sub _import_stats {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_import_stats() needs a $param_href') unless @_ == 1;
    my ($param_href) = @_;

    my $dbh   = $param_href->{dbh}   or $log->logcroak('no $dbh sent to _import_stats()!');
    my $stats = $param_href->{stats} or $log->logcroak('no $stats specified on command line!');

    # create genomes per phylostrata table
    my $analyze_tbl = path($stats)->basename;
    $analyze_tbl =~ s/[.-]/_/g;
    my $analyze_create = sprintf(
        qq{
    CREATE TABLE %s (
    ps TINYINT UNSIGNED NOT NULL,
    psti INT UNSIGNED NOT NULL,
    num_of_genes INT UNSIGNED NOT NULL,
    ti INT UNSIGNED NOT NULL,
    PRIMARY KEY(ti)
    ) WITHOUT ROWID }, $dbh->quote_identifier($analyze_tbl)
    );
    _create_table( { table_name => $analyze_tbl, dbh => $dbh, query => $analyze_create } );
    $log->trace("Report: $analyze_create");

    # read and import ps_table
    open( my $stats_fh, "<", $param_href->{stats} )
      or $log->logdie("Error: can't open map $param_href->{stats} for reading:$!");

    # prepare an insert statement
    my $analyze_ins = sprintf(
        qq{
    INSERT INTO %s (ps, psti, num_of_genes, ti)
    VALUES( ?, ?, ?, ? )
    }, $dbh->quote_identifier($analyze_tbl)
    );
    my $sth_ins = $dbh->prepare($analyze_ins);

    # insert entire file in one transaction
    $dbh->do('BEGIN TRANSACTION');

    # $dbh->{AutoCommit} is turned off temporarily during a transaction;

    my $analyze_rows = 0;
    while (<$stats_fh>) {
        chomp;

        # if ps then skip
        if (m/ps/) {
            next;
        }

        # else normal genome in phylostrata line
        else {
            my ( $ps, $psti, $num_of_genes, $ti ) = split "\t", $_;

            # insert to db
            $sth_ins->execute( $ps, $psti, $num_of_genes, $ti );
            $analyze_rows++;
        }
    }    # end while reading stats file

    # commit once at end of insertion
    $dbh->do('COMMIT') and $log->info("Action: inserted $analyze_rows rows to $analyze_tbl");

    # $dbh->{AutoCommit} is turned on again;
    close $stats_fh;
    $sth_ins->finish;

    # create index on phylostrata
    my $analyze_index = sprintf( qq{
    CREATE INDEX ps_idx ON %s (ps)
    }, $dbh->quote_identifier($analyze_tbl) );
    eval { $dbh->do($analyze_index); };
    $log->error("Action: adding index ps_idx on $analyze_tbl failed: $@") if $@;
    $log->trace("Action: index ps_idx on $analyze_tbl created") unless $@;

    return $analyze_tbl;
}


### CLASS METHOD/INSTANCE METHOD/INTERFACE SUB/INTERNAL UTILITY ###
# Usage      : _import_blastout_partial( { %{$param_href}, dbh => $dbh, analyze_tbl => $analyze_tbl } );
# Purpose    : import blastout prot_id by prot_id
# Returns    : nothing
# Parameters : 
# Throws     : croaks if wrong number of parameters
# Comments   : part of reduce_blastout()
# See Also   : 
sub _import_blastout_partial {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_import_blastout_partial() needs a $param_href') unless @_ == 1;
    my ($param_href) = @_;

    my $out      = $param_href->{out}      or $log->logcroak('no $out specified on command line!');
    my $blastout = $param_href->{blastout} or $log->logcroak('no $blastout specified on command line!');
    my $cutoff   = $param_href->{cutoff}   or $log->logwarn('no $cutoff specified on command line. Using $cutoff_ps1!');
    my $cutoff_ps1 = defined $param_href->{cutoff_ps1} ? $param_href->{cutoff_ps1} : undef;
    if ( !$cutoff and !$cutoff_ps1 ) {
        $log->logcroak('no $cutoff nor $cutoff_ps1 specified on command line thus aborting!');
    }
    my $dbh = $param_href->{dbh} or $log->logcroak('no $dbh sent to _import_blastout_partial()!');
    my $analyze_tbl = $param_href->{analyze_tbl}
      or $log->logcroak('no $analyze_tbl sent to _import_blastout_partial()!');

    # create blastout table
    my $blastout_tbl = path($blastout)->basename;
    $blastout_tbl =~ s/[.-]/_/g;    #for files that have dots in name
    my $blastout_ex;
    if ($cutoff_ps1) {
        $blastout_ex = path( $out, $blastout_tbl . "_cutoff_ps1_$cutoff_ps1" );
    }
    else {
        $blastout_ex = path( $out, $blastout_tbl . "_cutoff$cutoff" );
    }

    # check if blastout_ex file exists and delete it
    if ( -f $blastout_ex ) {
        unlink $blastout_ex and $log->warn("Warn: blastout export $blastout_ex deleted!");
    }

    #create table
    my $blastout_create = sprintf(
        qq{
    CREATE TABLE %s (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    prot_id VARCHAR(40) NOT NULL,
    ti INT UNSIGNED NOT NULL,
    pgi VARCHAR(20) NOT NULL,
    hit VARCHAR(40) NOT NULL,
    col3 FLOAT NOT NULL,
    col4 INT UNSIGNED NOT NULL,
    col5 INT UNSIGNED NOT NULL,
    col6 INT UNSIGNED NOT NULL,
    col7 INT UNSIGNED NOT NULL,
    col8 INT UNSIGNED NOT NULL,
    col9 INT UNSIGNED NOT NULL,
    col10 INT UNSIGNED NOT NULL,
    evalue REAL NOT NULL,
    bitscore FLOAT NOT NULL
    ) }, $dbh->quote_identifier($blastout_tbl)
    );
    _create_table( { table_name => $blastout_tbl, dbh => $dbh, query => $blastout_create } );

    # create index on ti (for select on ti)
    my $blastout_index = sprintf(
        qq{
    CREATE INDEX ti_idx ON %s (ti)
    }, $dbh->quote_identifier($blastout_tbl)
    );
    eval { $dbh->do($blastout_index); };
    $log->error("Action: adding index ti_idx on $blastout_tbl failed: $@") if $@;
    $log->trace("Action: index ti_idx on $blastout_tbl created") unless $@;

    # prepare an insert statement
    my $blastout_ins = sprintf(
        qq{
    INSERT INTO %s (prot_id, ti, pgi, hit, col3, col4, col5, col6, col7, col8, col9, col10, evalue, bitscore)
    VALUES ( ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ? )
    }, $dbh->quote_identifier($blastout_tbl)
    );
    $log->trace($blastout_ins);
    my $sth_ins = $dbh->prepare($blastout_ins);

    # open blastout file
    open( my $blastout_fh, "< :encoding(ASCII)", $param_href->{blastout} )
      or $log->logdie("Error: BLASTout file not found:$!");
    open( my $blastout_ex_fh, ">> :encoding(ASCII)", $blastout_ex )
      or $log->logdie("Error: BLASTout file can't be created:$!");

    # needed for filtering duplicates
    # idea is that prot_ids come one after another
    my $prot_prev = '';

# in blastout
#ENSG00000151914|ENSP00000354508    pgi|34252924|ti|9606|pi|0|  100.00  7461    0   0   1   7461    1   7461    0.0 1.437e+04

    $log->debug("Report: started processing of $param_href->{blastout}");
    local $.;
    my $protid_cnt   = 0;
    my $exported_cnt = 0;
    my $total_cnt    = 0;

    # insert entire file in one transaction
    $dbh->{AutoCommit} = 0;
    $dbh->do('BEGIN TRANSACTION');
  BLASTOUT:
    while (<$blastout_fh>) {
        chomp;

        my ( $prot_id, $hit, $col3, $col4, $col5, $col6, $col7, $col8, $col9, $col10, $evalue, $bitscore ) = split "\t",
          $_;
        my ( $pgi, $ti ) = $hit =~ m{pgi\|(\d+)\|ti\|(\d+)\|pi\|(?:\d+)\|};

        # import to database if same prot_id and do analysis
        if ( "$prot_prev" eq "$prot_id" ) {

            #import to db
            $sth_ins->execute(
                $prot_id, $ti,   $pgi,  $hit,  $col3,  $col4,   $col5,
                $col6,    $col7, $col8, $col9, $col10, $evalue, $bitscore
            );
            $prot_prev = $prot_id;
            $protid_cnt++;
            $total_cnt++;
            if ( $protid_cnt == 10000 ) {
                $dbh->do('COMMIT');
            }
        }
        else {
            # commit if end of prot_id
            $dbh->do('COMMIT') and $log->debug("Action: inserted {$prot_prev} $protid_cnt rows to $blastout_tbl");

            # do analysis
            if ( !$prot_prev eq '' ) {

                my $row_exported = _cutoff_pruning(
                    {   %{$param_href},
                        dbh          => $dbh,
                        anaylze_tbl  => $analyze_tbl,
                        blastout_tbl => $blastout_tbl,
                        prot_id      => $prot_prev,
                        blastex_fh   => $blastout_ex_fh
                    }
                );

                # reset to start new prot_id
                $prot_prev  = $prot_id;
                $protid_cnt = 0;
                $exported_cnt += $row_exported;
                $log->debug("Action: starting with next prot_id {$prot_id}") and redo BLASTOUT;
            }

            # there is '' empty prot_prev at start
            else {
                $prot_prev  = $prot_id;
                $protid_cnt = 0;
                $log->debug("Action: starting with next prot_id {$prot_id}") and redo BLASTOUT;
            }
        }

        # show progress
        if ( $. % 1000000 == 0 ) {
            $log->trace("$. lines processed!");
        }

    }    # end while reading blastout

    # need to commit last prot_id outside loop
    $dbh->do('COMMIT') and $log->debug("Action: inserted {$prot_prev} $protid_cnt rows to $blastout_tbl");
    close $blastout_fh;
    $sth_ins->finish;
    my $row_exported = _cutoff_pruning(
        {   %{$param_href},
            dbh          => $dbh,
            anaylze_tbl  => $analyze_tbl,
            blastout_tbl => $blastout_tbl,
            prot_id      => $prot_prev,
            blastex_fh   => $blastout_ex_fh
        }
    );
    $exported_cnt += $row_exported;
    $dbh->{AutoCommit} = 1;    # turned on again;

    $log->info("Report: file {$blastout_ex} printed successfully with $exported_cnt lines (from $total_cnt lines)");

    return;
}


### INTERNAL UTILITY ###
# Usage      : my $row_exported = _cutoff_pruning( { %{$param_href}, dbh => $dbh, analyze_tbl => $analyze_tbl, blastout_tbl => $blastout_tbl, prot_id => $prot_prev, blastex_fh   => $blastout_ex_fh } );
# Purpose    : select and delete taxids that are smaller than cutoff
# Returns    : $row_cnt (number of exported rows)
# Parameters : 
# Throws     : croaks if wrong number of parameters
# Comments   : part of reduce_blastout()
# See Also   : 
sub _cutoff_pruning {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('_cutoff_pruning() needs a $param_href') unless @_ == 1;
    my ($param_href) = @_;

    my $cutoff_ps1 = defined $param_href->{cutoff_ps1} ? $param_href->{cutoff_ps1} : undef;
    my $cutoff  = $param_href->{cutoff};
    my $dbh     = $param_href->{dbh}     or $log->logcroak('no $dbh sent to _cutoff_pruning()!');
    my $prot_id = $param_href->{prot_id} or $log->logcroak('no $prot_id sent to _cutoff_pruning()!');
    my $analyze_tbl = $param_href->{analyze_tbl}
      or $log->logcroak('no $analyze_tbl sent to _cutoff_pruning()!');
    my $blastout_tbl = $param_href->{blastout_tbl}
      or $log->logcroak('no $blastout_tbl sent to _cutoff_pruning()!');
    my $blastex_fh = $param_href->{blastex_fh} or $log->logcroak('no $blastex_fh sent to _cutoff_pruning()!');

    # split logic based on existence of $cutoff_ps1 (shallow analysis)
    my @ps;
    if ($cutoff_ps1) {

        # select ps1 if is smaller or equal than cutoff_ps1
        my $ps_select_ps1 = sprintf(
            qq{
        SELECT an.ps, COUNT(an.ps) AS ps_cnt FROM %s AS bl INNER JOIN %s AS an ON bl.ti = an.ti
        WHERE prot_id = %s AND an.ps = 1 GROUP BY an.ps HAVING ps_cnt <= ?
        }, $dbh->quote_identifier($blastout_tbl), $dbh->quote_identifier($analyze_tbl), $dbh->quote($prot_id)
        );
        $log->trace("Report: $ps_select_ps1");
        my $sth_sel = $dbh->prepare($ps_select_ps1);
        $sth_sel->bind_param( 1, $cutoff_ps1, SQL_INTEGER );
        $sth_sel->execute();

        # get column phylostrata to array to iterate insert query on them
        @ps = map { $_->[0] } @{ $sth_sel->fetchall_arrayref( [0] ) };
        $log->trace( 'Returned phylostrata to delete: {', join( '}{', @ps ), '}' );
    }
    else {
        # select ps which are smaller or equal than cutoff
        my $ps_select = sprintf(
            qq{
        SELECT an.ps, COUNT(an.ps) AS ps_cnt FROM %s AS bl INNER JOIN %s AS an ON bl.ti = an.ti
        WHERE prot_id = %s GROUP BY an.ps HAVING ps_cnt <= ?
        }, $dbh->quote_identifier($blastout_tbl), $dbh->quote_identifier($analyze_tbl), $dbh->quote($prot_id)
        );
        $log->trace("Report: $ps_select");
        my $sth_sel = $dbh->prepare($ps_select);
        $sth_sel->bind_param( 1, $cutoff, SQL_INTEGER );
        $sth_sel->execute();

        # get column phylostrata to array to iterate insert query on them
        @ps = map { $_->[0] } @{ $sth_sel->fetchall_arrayref( [0] ) };
        $log->trace( 'Returned phylostrata to delete: {', join( '}{', @ps ), '}' );
    }

    # delete rows which have tis from phylostrata smaller or equal to cutoff
    my $del_blastout = sprintf(
        qq{
    DELETE FROM %s WHERE ti IN (SELECT ti FROM %s AS an WHERE an.ps IN(}
          . join( ',', ('?') x @ps ) . qq{)) AND prot_id = %s
    }, $dbh->quote_identifier($blastout_tbl), $dbh->quote_identifier($analyze_tbl), $dbh->quote($prot_id)
    );
    my $sth_del = $dbh->prepare($del_blastout);
    $log->trace("Report: $del_blastout");
    eval { $sth_del->execute(@ps); };
    my $del_rows = $sth_del->rows;
    $log->error("Action: deleting $prot_id from $blastout_tbl failed: $@") if $@;
    $log->debug("Action: deleted $del_rows $prot_id rows from $blastout_tbl table") unless $@;

    #SELECT an.ps, COUNT(an.ps) AS ps_cnt FROM hs_all_plus_21_12_2015 AS bl INNER JOIN analyze_hs_9606_cdhit_large_extracted AS an ON bl.ti = an.ti WHERE prot_id = 'ENSP00000046794' GROUP BY an.ps HAVING ps_cnt <= 1;
    #DELETE FROM hs_all_plus_21_12_2015 WHERE ti IN (SELECT ti FROM analyze_hs_9606_cdhit_large_extracted AS an WHERE an.ps IN(11,16)) AND prot_id = 'ENSP00000046794';

    # export to blast_export file
    my $blast_export = sprintf(
        qq{
    SELECT prot_id, hit, col3, col4, col5, col6, col7, col8, col9, col10, evalue, bitscore
    FROM %s
    WHERE prot_id = ?
    }, $dbh->quote_identifier($blastout_tbl)
    );
    my ( $prot_id2, $hit, $col3, $col4, $col5, $col6, $col7, $col8, $col9, $col10, $evalue, $bitscore );
    my $sth_ex = $dbh->prepare($blast_export);
    $log->trace("Report: $blast_export");
    $sth_ex->execute($prot_id);
    $sth_ex->bind_columns(
        \( $prot_id2, $hit, $col3, $col4, $col5, $col6, $col7, $col8, $col9, $col10, $evalue, $bitscore ) );
    my $row_cnt = 0;
    while ( $sth_ex->fetchrow_arrayref ) {
        print {$blastex_fh}
          "$prot_id2\t$hit\t$col3\t$col4\t$col5\t$col6\t$col7\t$col8\t$col9\t$col10\t$evalue\t$bitscore\n";
        $row_cnt++;
    }
    $log->debug("Action: exported $row_cnt rows for $prot_id");

    # truncate blastout_tbl to reduce size of database
    my $blastout_del = sprintf(
        qq{
    DELETE FROM %s
    }, $dbh->quote_identifier($blastout_tbl)
    );
    $log->trace("Report: $blastout_del");
    eval { $dbh->do($blastout_del); };
    $log->error("Action: deleting $blastout_tbl after $prot_id failed: $@") if $@;
    $log->debug("Action: deleted $blastout_tbl table after $prot_id") unless $@;

    return $row_cnt;

}


## INTERFACE SUB ###
# Usage      : export_to_ff
# Purpose    : export proteomes to taxid.ff files
# Returns    : nothing
# Parameters : 
# Throws     : croaks if wrong number of parameters
# Comments   : files are ready for BLAST and PhyloStrat
# See Also   : 
sub export_to_ff {
    my $log = Log::Log4perl::get_logger("main");
    $log->logcroak('export_to_ff() needs {$param_href}') unless @_ == 1;
    my ($param_href) = @_;

    my $out           = $param_href->{out}        or $log->logcroak('no $out specified on command line!');
    my $database      = $param_href->{database}   or $log->logcroak('no $database specified on command line!');
    my $proteomes_tbl = $param_href->{table_name} or $log->logcroak('no $table_name specified on command line!');

    # get new dbh
    my $dbh = _dbi_connect($param_href);

    # get all taxids from table (export by ti)
    my $select_ti = sprintf(
        qq{
    SELECT DISTINCT ti
    FROM %s
    }, $dbh->quote_identifier($proteomes_tbl)
    );
    $log->trace("Report: $select_ti");
    my @tis = map { $_->[0] } @{ $dbh->selectall_arrayref($select_ti) };
    $log->info( "Action: retrieved " . scalar @tis . " tax_ids from ${database}.$proteomes_tbl" );

    # query to select entire fasta sequence and print it to file
    my $select_proteome = sprintf(
        qq{
    SELECT prot_id, prot_name, fasta
    FROM %s
    WHERE ti = ?
    }, $dbh->quote_identifier($proteomes_tbl)
    );
    $log->trace("Report: $select_proteome");

    # export each proteome
    $log->info("Report: exporting proteomes to .ff files in $out");
    foreach my $ti (@tis) {

        # create new file based on ti
        my $ti_path = path( $out, $ti . '.ff' );
        open( my $proteome_fh, ">", $ti_path ) or $log->logdie("Error: can't open $ti_path for writing:$!");

        # retrive proteome based on ti
        my $sth = $dbh->prepare($select_proteome);
        $sth->execute($ti);
        my ( $prot_id, $prot_name, $fasta );
        $sth->bind_columns( \( $prot_id, $prot_name, $fasta ) );
        my $row_cnt = 0;
        while ( $sth->fetchrow_arrayref ) {
            print {$proteome_fh} ">$prot_id\t$prot_name\n$fasta\n";
            $row_cnt++;
        }
        $log->debug("Action: exported $row_cnt rows to $ti_path");
    }

    return;
}



1;
__END__

=encoding utf-8

=head1 NAME

BlastoutAnalyze - It's a modulino used to analyze BLAST output and database.

=head1 SYNOPSIS

    # drop and recreate database (connection parameters in blastoutanalyze.cnf)
    BlastoutAnalyze.pm --mode=create_db -d test_db_here

    # remove duplicates and import BLAST output file into MySQL database
    BlastoutAnalyze.pm --mode=import_blastout -if t/data/hs_all_plus_21_12_2015 -d hs_plus -v

    # remove header and import phylostratigraphic map into MySQL database (reads PS, TI and PSNAME from config)
    BlastoutAnalyze.pm --mode=import_map -if t/data/hs3.phmap_names -d hs_plus -v

    # imports analyze stats file created by AnalyzePhyloDb (uses TI and PS sections in config)
    BlastoutAnalyze.pm --mode=import_blastdb_stats -if t/data/analyze_hs_9606_cdhit_large_extracted  -d hs_plus --names_tbl=names_dmp_fmt_new -v

    # import names file for species_name
    BlastoutAnalyze.pm --mode=import_names -if t/data/names.dmp.fmt.new  -d hs_plus -v

    # runs BLAST output analysis - expanding every prot_id to its tax_id hits and species names
    BlastoutAnalyze.pm --mode=analyze_blastout -d hs_plus -v

    # runs summary per phylostrata per species of BLAST output analysis.
    BlastoutAnalyze.pm --mode=report_per_ps -o -d hs_plus -v

    # removes specific hits from the BLAST output based on the specified tax_id (exclude bad genomes).
    BlastoutAnalyze.pm --mode=exclude_ti_from_blastout -if t/data/hs_all_plus_21_12_2015 -ti 428574 -v

    # update report_per_ps table with unique and intersect hts and gene lists
    BlastoutAnalyze.pm --mode=report_per_ps_unique -o t/data/ --report_per_ps=hs_all_plus_21_12_2015_report_per_ps -d hs_plus -v

    # import full blastout with all columns (plus ti and pgi)
    BlastoutAnalyze.pm --mode=import_blastout_full -if t/data/hs_all_plus_21_12_2015 -d hs_blastout -v

    # import full BLAST database (plus ti and pgi columns)
    BlastoutAnalyze.pm --mode=import_blastdb -if t/data/db90_head.gz -d hs_blastout -v -v

    # import expanded reports into database
    BlastoutAnalyze.pm --mode=import_reports --in t/data/ -d origin --max_processes=4

    # find top N species with most BLAST hits (proteins found) in prokaryotes per domain (Archaea, Cyanobacteria, Bacteria)
    BlastoutAnalyze.pm --mode=top_hits -d kam --top_hits=10

    # reduce blastout based on cutoff (it deletes hits if less or equal to cutoff per phylostratum)
    # or
    BlastoutAnalyze.pm --mode=reduce_blastout --stats=t/data/analyze_hs_9606_cdhit_large_extracted --blastout=t/data/hs_all_plus_21_12_2015 --out=t/data/ --cutoff=3 -v
    # reduce blastout based only on ps1 cutoff_ps1 (it deletes hits if less or equal to cutoff_ps1 from ps1)
    # or
    BlastoutAnalyze.pm --mode=reduce_blastout --stats=t/data/analyze_hs_9606_cdhit_large_extracted --blastout=t/data/hs_all_plus_21_12_2015 --out=t/data/ --cutoff_ps1=1 -v

    # export proteomes from BLAST database table to .ff file ready for BLAST
    BlastoutAnalyze.pm --mode=export_to_ff --out=/msestak/db_22_03_2017/data/all_ff_final/ --table_name=old_proteomes -d phylodb -p msandbox -u msandbox -po 5716 -s /tmp/mysql_sandbox5716.sock

=head1 DESCRIPTION

BlastoutAnalyze is modulino used to analyze BLAST database (to get content in genomes and sequences) and BLAST output (to figure out wwhere are hits comming from). It includes config, command-line and logging management.

 --mode=mode                Description
 --mode=create_db           drops and recreates database in MySQL (needs MySQL connection parameters from config)
 
 For help write:
 BlastoutAnalyze.pm -h
 BlastoutAnalyze.pm -m

=head2 MODES

=over 4

=item create_db

 # options from command line
 BlastoutAnalyze.pm --mode=create_db -ho localhost -d test_db_here -p msandbox -u msandbox -po 5625 -s /tmp/mysql_sandbox5625.sock --charset=ascii

 # options from config
 BlastoutAnalyze.pm --mode=create_db -d test_db_here

Drops ( if it exists) and recreates database in MySQL (needs MySQL connection parameters to connect to MySQL).

=item import_blastout

 # options from command line
 BlastoutAnalyze.pm --mode=import_blastout -if t/data/hs_all_plus_21_12_2015 -d hs_plus -v -p msandbox -u msandbox -po 5625 -s /tmp/mysql_sandbox5625.sock

 # options from config
 BlastoutAnalyze.pm --mode=import_blastout -if t/data/hs_all_plus_21_12_2015 -d hs_plus -v

Extracts columns (prot_id, ti, pgi, e_value with no duplicates), writes them to tmp file and imports that file into MySQL (needs MySQL connection parameters to connect to MySQL).

=item import_map

 # options from command line
 BlastoutAnalyze.pm --mode=import_map -if t/data/hs3.phmap_names -d hs_plus -v -p msandbox -u msandbox -po 5625 -s /tmp/mysql_sandbox5625.sock

 # options from config
 BlastoutAnalyze.pm --mode=import_map -if t/data/hs3.phmap_names -d hs_plus -v

Removes header from map file and writes columns (prot_id, phylostrata, ti, psname) to tmp file and imports that file into MySQL (needs MySQL connection parameters to connect to MySQL).
It can use PS and TI config sections.

=item import_blastdb_stats

 # options from command line
 BlastoutAnalyze.pm --mode=import_blastdb_stats -if t/data/analyze_hs_9606_cdhit_large_extracted  -d hs_plus --names_tbl=names_dmp_fmt_new -v -p msandbox -u msandbox -po 5625 -s /tmp/mysql_sandbox5625.sock

 # options from config
 BlastoutAnalyze.pm --mode=import_blastdb_stats -if t/data/analyze_hs_9606_cdhit_large_extracted  -d hs_plus --names_tbl=names_dmp_fmt_new -v

Imports analyze stats file created by AnalyzePhyloDb.
  AnalysePhyloDb -n /home/msestak/dropbox/Databases/db_02_09_2015/data/nr_raw/nodes.dmp.fmt.new.sync -d /home/msestak/dropbox/Databases/db_02_09_2015/data/cdhit_large/extracted/ -t 9606 > analyze_hs_9606_cdhit_large_extracted
It can use PS and TI config sections.

=item import_names

 # options from command line
 BlastoutAnalyze.pm --mode=import_names -if t/data/names.dmp.fmt.new  -d hs_plus -v -p msandbox -u msandbox -po 5625 -s /tmp/mysql_sandbox5625.sock

 # options from config
 BlastoutAnalyze.pm --mode=import_names -if t/data/names.dmp.fmt.new  -d hs_plus -v

Imports names file (columns ti, species_name) into MySQL.

=item analyze_blastout

 # options from command line
 BlastoutAnalyze.pm --mode=analyze_blastout -d hs_plus -v -p msandbox -u msandbox -po 5625 -s /tmp/mysql_sandbox5625.sock

 # options from config
 BlastoutAnalyze.pm --mode=analyze_blastout -d hs_plus -v

Runs BLAST output analysis - expanding every prot_id to its tax_id hits and species names. It creates 2 table: one with all tax_ids fora each gene, and one with tax_ids only that are for phylostratum of interest.


=item report_per_ps

 # options from command line
 lib/BlastoutAnalyze.pm --mode=report_per_ps -d hs_plus -v -p msandbox -u msandbox -po 5625 -s /tmp/mysql_sandbox5625.sock

 # options from config
 lib/BlastoutAnalyze.pm --mode=report_per_ps -d hs_plus -v

Runs summary per phylostrata per species of BLAST output analysis.

=item exclude_ti_from_blastout

 # options from command line
 lib/BlastoutAnalyze.pm --mode=exclude_ti_from_blastout -if t/data/hs_all_plus_21_12_2015 -ti 428574 -v

 # options from config
 lib/BlastoutAnalyze.pm --mode=exclude_ti_from_blastout -if t/data/hs_all_plus_21_12_2015 -ti 428574 -v

Removes specific hits from the BLAST output based on the specified tax_id (exclude bad genomes).

=item report_per_ps_unique

 # options from command line
 BlastoutAnalyze.pm --mode=report_per_ps_unique -o t/data/ --report_per_ps=hs_all_plus_21_12_2015_report_per_ps -d hs_plus -v -p msandbox -u msandbox -po 5625 -s /tmp/mysql_sandbox5625.sock

 # options from config
 BlastoutAnalyze.pm --mode=report_per_ps_unique -d hs_plus -v

Update report_per_ps table with unique and intersect hits and gene lists.

=item import_blastout_full

 # options from command line
 BlastoutAnalyze.pm --mode=import_blastout_full -if t/data/hs_all_plus_21_12_2015 -d hs_blastout -v -p msandbox -u msandbox -po 5625 -s /tmp/mysql_sandbox5625.sock

 # options from config
 BlastoutAnalyze.pm --mode=import_blastout_full -if t/data/hs_all_plus_21_12_2015 -d hs_blastout -v

Extracts hit column and splits it on ti and pgi and imports this file into MySQL (it has 2 extra columns = ti and pgi with no duplicates). It needs MySQL connection parameters to connect to MySQL.

 [2016/04/20 16:12:42,230] INFO> BlastoutAnalyze::run line:101==>RUNNING ACTION for mode: import_blastout_full
 [2016/04/20 16:12:42,232]DEBUG> BlastoutAnalyze::_extract_blastout_full line:1644==>Report: started processing of /home/msestak/prepare_blast/out/random/hs_all_plus_21_12_2015_good
 [2016/04/20 16:12:51,790]TRACE> BlastoutAnalyze::_extract_blastout_full line:1664==>1000000 lines processed!
 ...  Perl processing (3.5 h)
 [2016/04/20 19:37:59,376]TRACE> BlastoutAnalyze::_extract_blastout_full line:1664==>1151000000 lines processed!
 [2016/04/20 19:38:07,991] INFO> BlastoutAnalyze::_extract_blastout_full line:1670==>Report: file /home/msestak/prepare_blast/out/random/hs_all_plus_21_12_2015_good_formated printed successfully with 503625726 lines (from 1151804042 original lines)
 [2016/04/20 19:38:08,034]TRACE> BlastoutAnalyze::import_blastout_full line:1575==>Time running:0 sec    STATE:Fetched about 2000 rows, loading data still remains
 ... Load (50 min)
 [2016/04/20 20:28:58,788] INFO> BlastoutAnalyze::import_blastout_full line:1581==>Action: import inserted 503625726 rows!
 [2016/04/20 20:28:58,807]TRACE> BlastoutAnalyze::import_blastout_full line:1603==>Time running:0 sec    STATE:Adding indexes
 ... indexing (33 min)
 [2016/04/20 21:01:59,155] INFO> BlastoutAnalyze::import_blastout_full line:1610==>Action: Indices protx and tix on hs_all_plus_21_12_2015_good added successfully!
 [2016/04/20 21:01:59,156] INFO> BlastoutAnalyze::run line:105==>TIME when finished for: import_blastout_full


=item import_blastdb

 # options from command line
 BlastoutAnalyze.pm --mode=import_blastdb -if t/data/db90_head.gz -d hs_blastout -v -p msandbox -u msandbox -po 5625 -s /tmp/mysql_sandbox5625.sock

 # options from config
 BlastoutAnalyze.pm --mode=import_blastdb -if /media/SAMSUNG/msestak/dropbox/Databases/db_02_09_2015/data/dbfull.gz -d dbfull -v -v
 BlastoutAnalyze.pm --mode=import_blastdb -if t/data/db90_head.gz -d hs_blastout -v -v

Imports BLAST database file into MySQL (it has 2 extra columns = ti and pgi). It needs MySQL connection parameters to connect to MySQL.

 ...load (5 h)
 [2016/09/26 11:55:46,940]TRACE> BlastoutAnalyze::import_blastdb line:1889==>Time running:3494 sec       STATE:Fetched about 113690000 rows, loading data still remains
 [2016/09/26 11:55:51,331] WARN> BlastoutAnalyze::import_blastdb line:1833==>Report: file /media/SAMSUNG/msestak/dropbox/Databases/db_02_09_2015/data/dbfull.gz has 113834350 fasta records!
 [2016/09/26 11:55:51,332] WARN> BlastoutAnalyze::import_blastdb line:1834==>Action: file /media/SAMSUNG/msestak/dropbox/Databases/db_02_09_2015/data/blastdb_named_pipe_2016_9_26_10_57_32 written with 113834350 lines/fasta records!
 ...
 [2016/09/26 18:43:38,488]TRACE> BlastoutAnalyze::import_blastdb line:1889==>Time running:17610 sec      STATE:Loading of data about 100.0% done
 [2016/09/26 18:43:48,506] INFO> BlastoutAnalyze::import_blastdb line:1895==>Report: import inserted 113834350 rows!
 ...indexing (41 min)
 [2016/09/26 19:24:19,113]TRACE> BlastoutAnalyze::import_blastdb line:1917==>Time running:2431 sec       STATE:Loading of data about 99.6% done
 [2016/09/26 19:24:29,114] INFO> BlastoutAnalyze::import_blastdb line:1924==>Action: indices prot_namex and pgix on {dbfull} added successfully!

=item import_reports

 # options from command line
 BlastoutAnalyze.pm --mode=import_reports --in t/data/ -d origin --max_processes=4 -p msandbox -u msandbox -po 5625 -s /tmp/mysql_sandbox5625.sock
 BlastoutAnalyze.pm --mode=import_reports --in /msestak/workdir/origin_of_eukaryotes/ClickHouse_db_47_genomes/ -d origin --max_processes=4

 # options from config
 BlastoutAnalyze.pm --mode=import_reports --in t/data/ -d origin --max_processes=4

Imports expanded reports per species in BLAST database into MySQL. It can import in parallel. It needs MySQL connection parameters to connect to MySQL.

=item top_hits

 # find N top hits for all species per domain in a database
 BlastoutAnalyze.pm --mode=top_hits -d kam --top_hits=10

It finds top N species with most BLAST hits (proteins found) in prokaryotes per domain (Archaea, Cyanobacteria, Bacteria).

=item reduce_blastout

 # reduce blastout based on cutoff (it deletes hits if less or equal to cutoff per phylostratum)
 BlastoutAnalyze.pm --mode=reduce_blastout --stats=t/data/analyze_hs_9606_cdhit_large_extracted --blastout=t/data/hs_all_plus_21_12_2015 --out=t/data/ --cutoff=3 -v -v

It deletes hits in a BLAST output file if number of tax ids per phylostratum is less or equal to cutoff. This means that if cutoff=3, all hits with 3 or less hits are deleted and only 4+ hits are retained.
It requires blastout and analyze files. Analyze file is required to get distribution of tax ids per phylostratum.
It works by importing to SQLite database, doing analysis there and exporting filtered BLAST output to $out directory (resulting blastout_export file is deleted if it already exists). SQLite database is also deleted after the analysis.

 # reduce blastout based only on ps1 cutoff_ps1 (it deletes hits if less or equal to cutoff_ps1 from ps1)
 # or
 BlastoutAnalyze.pm --mode=reduce_blastout --stats=t/data/analyze_hs_9606_cdhit_large_extracted --blastout=t/data/hs_all_plus_21_12_2015 --out=t/data/ --cutoff_ps1=1 -v

It deletes hits in a BLAST output file only from phylostratum 1 if number of tax ids per phylostratum is less or equal to cutoff_ps1. This means that if cutoff_ps1=1, all hits with only one hit in ps1 are deleted and only 2+ hits are retained.

=item export_to_ff

  # export proteomes from BLAST database table to .ff file ready for BLAST
  BlastoutAnalyze.pm --mode=export_to_ff --out=/msestak/db_22_03_2017/data/all_ff_final/ --table_name=old_proteomes -d phylodb -p msandbox -u msandbox -po 5716 -s /tmp/mysql_sandbox5716.sock

It exports all proteomes from BLAST database table into .ff files named after tax_id. It has structure needed for PhyloStrat (pgi|ti|pi identifier). Works opposite of --mode=import_blastdb.

=back

=head1 CONFIGURATION

All configuration in set in blastoutanalyze.cnf that is found in ./lib directory (it can also be set with --config option on command line). It follows L<< Config::Std|https://metacpan.org/pod/Config::Std >> format and rules.
Example:

 [General]
 #in       = /home/msestak/prepare_blast/out/dr_plus/
 #out      = /msestak/gitdir/MySQLinstall
 #infile   = /home/msestak/mysql-5.6.27-linux-glibc2.5-x86_64.tar.gz
 #outfile  = /home/msestak/prepare_blast/out/dr_04_02_2016.xlsx
 
 [Database]
 host     = localhost
 database = test_db_here
 user     = msandbox
 password = msandbox
 port     = 5625
 socket   = /tmp/mysql_sandbox5625.sock
 charset  = ascii

=head1 INSTALL

Clone GitHub repo and install dependencies with cpanm.

  git clone https://github.com/msestak/BlastoutAnalyze
  cd BlastoutAnalyze
  # repeat cpanm install until it installs all modules
  cpanm -f -n --installdeps .
  # update DBD::SQLite module
  cpanm -n DBD::SQLite

=head1 LICENSE

Copyright (C) 2016-2017 Martin Sebastijan Šestak.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Martin Sebastijan Šestak
mocnii
E<lt>msestak@irb.hrE<gt>

=cut

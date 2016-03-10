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
use DBI;
use DBD::mysql;

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
        create_db           => \&create_db,              # drop and recreate database in MySQL
        blastout_analyze    => \&blastout_analyze,       # analyze BLAST output and extract prot_id => ti information
        import_blastout     => \&import_blastout,        # import BLAST output
        import_map          => \&import_map,             # import Phylostratigraphic map with header
		import_blastdb_stats => \&import_blastdb_stats,  # import BLAST database stats file

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
	my ($volume, $dir_out, $perl_script) = splitpath( $0 );
	$dir_out = rel2abs($dir_out);
    my ($app_name) = $perl_script =~ m{\A(.+)\.(?:.+)\z};
	$app_name = lc $app_name;
    my $config_file = catfile($volume, $dir_out, $app_name . '.cnf' );
	$config_file = canonpath($config_file);

	#read config to setup defaults
	read_config($config_file => my %config);
	#print 'config:', Dumper(\%config);
	#push all options into one hash no matter the section
	my %opts;
	foreach my $key (keys %config) {
		%opts = (%opts, %{ $config{$key} });
	}
	# put config location to %opts
	$opts{config} = $config_file;
	#say 'opts:', Dumper(\%opts);

	#cli part
	my @arg_copy = @ARGV;
	my (%cli, @mode);
	$cli{argv} = \@arg_copy;
	$cli{quiet} = 0;
	$cli{verbose} = 0;

	#mode, quiet and verbose can only be set on command line
    GetOptions(
        'help|h'        => \$cli{help},
        'man|m'         => \$cli{man},
		'config|cnf=s'  => \$cli{config},
        'in|i=s'        => \$cli{in},
        'infile|if=s'   => \$cli{infile},
        'out|o=s'       => \$cli{out},
        'outfile|of=s'  => \$cli{outfile},

        'host|ho=s'      => \$cli{host},
        'database|d=s'  => \$cli{database},
        'user|u=s'      => \$cli{user},
        'password|p=s'  => \$cli{password},
        'port|po=i'     => \$cli{port},
        'socket|s=s'    => \$cli{socket},

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
	die 'No mode specified on command line' unless $cli{mode};   #DIES here if without mode
	
	#if not -q or --quiet print all this (else be quiet)
	if ($cli{quiet} == 0) {
		#print STDERR 'My @ARGV: {', join( "} {", @arg_copy ), '}', "\n";
		#no warnings 'uninitialized';
		#print STDERR "Extra options from config:", Dumper(\%opts);
	
		if ($cli{in}) {
			say 'My input path: ', canonpath($cli{in});
			$cli{in} = rel2abs($cli{in});
			$cli{in} = canonpath($cli{in});
			say "My absolute input path: $cli{in}";
		}
		if ($cli{infile}) {
			say 'My input file: ', canonpath($cli{infile});
			$cli{infile} = rel2abs($cli{infile});
			$cli{infile} = canonpath($cli{infile});
			say "My absolute input file: $cli{infile}";
		}
		if ($cli{out}) {
			say 'My output path: ', canonpath($cli{out});
			$cli{out} = rel2abs($cli{out});
			$cli{out} = canonpath($cli{out});
			say "My absolute output path: $cli{out}";
		}
		if ($cli{outfile}) {
			say 'My outfile: ', canonpath($cli{outfile});
			$cli{outfile} = rel2abs($cli{outfile});
			$cli{outfile} = canonpath($cli{outfile});
			say "My absolute outfile: $cli{outfile}";
		}
	}
	else {
		$cli{verbose} = -1;   #and logging is OFF

		if ($cli{in}) {
			$cli{in} = rel2abs($cli{in});
			$cli{in} = canonpath($cli{in});
		}
		if ($cli{infile}) {
			$cli{infile} = rel2abs($cli{infile});
			$cli{infile} = canonpath($cli{infile});
		}
		if ($cli{out}) {
			$cli{out} = rel2abs($cli{out});
			$cli{out} = canonpath($cli{out});
		}
		if ($cli{outfile}) {
			$cli{outfile} = rel2abs($cli{outfile});
			$cli{outfile} = canonpath($cli{outfile});
		}
	}

    #copy all config opts
	my %all_opts = %opts;
	#update with cli options
	foreach my $key (keys %cli) {
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
    my $out    = $param_href->{out}    or $log->logcroak('no $out specified on command line!');
    my $table           = path($infile)->basename;
    $table =~ s/\./_/g;    #for files that have dots in name
    my $blastout_import = path($out, $table . "_formated");

    #first shorten the blastout file and extract useful columns
    _extract_blastout( { infile => $infile, blastout_import => $blastout_import } );

    #get new handle
    my $dbh = _dbi_connect($param_href);

    #create table
    my $create_query = qq{
    CREATE TABLE IF NOT EXISTS $table (
    prot_id VARCHAR(40) NOT NULL,
    ti INT UNSIGNED NOT NULL,
    pgi CHAR(19) NOT NULL,
    e_value REAL NOT NULL,
    PRIMARY KEY(prot_id, ti, pgi)
    )};
    _create_table( { table_name => $table, dbh => $dbh, query => $create_query } );

    #import table
    my $load_query = qq{
    LOAD DATA INFILE '$blastout_import'
    INTO TABLE $table } . q{ FIELDS TERMINATED BY '\t'
    LINES TERMINATED BY '\n' 
    (prot_id, ti, pgi, e_value)
    };
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
    ALTER TABLE $table ADD INDEX tix(ti)
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
    $log->info( "Action: Index tix on $table added successfully!" ) unless $@;
	
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

		my ($prot_id, $hit, undef, undef, undef, undef, undef, undef, undef, undef, $e_value, undef) = split "\t", $_;
		my ($pgi, $ti, undef) = $hit =~ m{pgi\|(\d+)\|ti\|(\d+)\|pi\|(?:\d+)\|};

        # check for duplicates for same gene_id with same tax_id and pgi that differ only in e_value
        if (  "$prot_prev" . "$pgi_prev" . "$ti_prev" ne "$prot_id" . "$pgi" . "$ti" ) {
            say {$blastout_fmt_fh} $prot_id, "\t", $ti, "\t", $pgi, "\t", $e_value;
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

    my $infile = $param_href->{infile} or $log->logcroak('no $infile specified on command line!');
	my $stats_ps_tbl = path($infile)->basename;
	$stats_ps_tbl   .= '_stats_ps';
	my $stats_genomes_tbl = path($infile)->basename;
	$stats_genomes_tbl   .='_stats_genomes';

	my $dbh = _dbi_connect($param_href);

    # create ps summary table
    my $ps_summary = sprintf( qq{
	CREATE TABLE %s (
	phylostrata TINYINT UNSIGNED NOT NULL,
	num_of_genomes INT UNSIGNED NOT NULL,
	ti INT UNSIGNED NOT NULL,
	PRIMARY KEY(phylostrata),
	KEY(ti),
	KEY(num_of_genomes)
    ) }, $dbh->quote_identifier($stats_ps_tbl) );
	_create_table( { table_name => $stats_ps_tbl, dbh => $dbh, query => $ps_summary } );
	$log->trace("Report: $ps_summary");

	# create genomes per phylostrata table
    my $genomes_per_ps = sprintf( qq{
	CREATE TABLE %s (
	phylostrata TINYINT UNSIGNED NOT NULL,
	psti INT UNSIGNED NOT NULL,
	num_of_genes INT UNSIGNED NOT NULL,
	ti INT UNSIGNED NOT NULL,
	PRIMARY KEY(ti),
	KEY(phylostrata),
	KEY(num_of_genes)
    ) }, $dbh->quote_identifier($stats_genomes_tbl) );
	_create_table( { table_name => $stats_genomes_tbl, dbh => $dbh, query => $genomes_per_ps } );
	$log->trace("Report: $genomes_per_ps");

	# create tmp file for genomes part of stats file
	my $temp_stats = path(path($infile)->parent, $stats_genomes_tbl);
	open (my $tmp_fh, ">", $temp_stats) or $log->logdie("Error: can't open map $temp_stats for writing:$!");

	# prepare statement handle to insert ps lines
	my $insert_ps = sprintf( qq{
	INSERT INTO %s (phylostrata, num_of_genomes, ti)
	VALUES (?, ?, ?)
	}, $dbh->quote_identifier($stats_ps_tbl) );
	my $sth = $dbh->prepare($insert_ps);
	$log->trace("Report: $insert_ps");

	# need to skip header
	open (my $stats_fh, "<", $infile) or $log->logdie("Error: can't open map $infile for reading:$!");
	while (<$stats_fh>) {
		chomp;

		# if ps then summary line
		if (m/ps/) {
			#import to stats_ps_tbl
			my (undef, $ps, $num_of_genomes, $ti, ) = split "\t", $_;
			$sth->execute($ps, $num_of_genomes, $ti);
		}
		# else normal genome in phylostrata line
		else {
			my ($ps2, $psti, $num_of_genes, $ti2) = split "\t", $_;
			say {$tmp_fh} "$ps2\t$psti\t$num_of_genes\t$ti2";
		}
	}   # end while reading stats file

	# explicit close needed else it can break
	close $tmp_fh;
	$sth->finish;

	# load genomes per phylostrata
    my $load_query = qq{
    LOAD DATA INFILE '$temp_stats'
    INTO TABLE $stats_genomes_tbl } . q{ FIELDS TERMINATED BY '\t'
    LINES TERMINATED BY '\n'
    };
	$log->trace("Report: $load_query");
	my $rows;
    eval { $rows = $dbh->do( $load_query ) };
	$log->error( "Action: loading into table $stats_genomes_tbl failed: $@" ) if $@;
	$log->debug( "Action: table $stats_genomes_tbl inserted $rows rows!" ) unless $@;

	# unlink tmp map file
	unlink $temp_stats and $log->warn("Action: $temp_stats unlinked");
	$dbh->disconnect;

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
    BlastoutAnalyze.pm --mode=import_blastout -if t/data/sc_OUTplus100 -o t/data/ -d hs_plus

    # remove header and import phylostratigraphic map into MySQL database (reads PS, TI and PSNAME from config)
    BlastoutAnalyze.pm --mode=import_map -if t/data/hs3.phmap_names -d hs_plus -v


=head1 DESCRIPTION

BlastoutAnalyze is modulino used to analyze BLAST database (to get content in genomes and sequences) and BLAST output (to figure out wwhere are hits comming from. It includes config, command-line and logging management.

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
 BlastoutAnalyze.pm --mode=import_blastout -if t/data/sc_OUTplus100 -o t/data/ -d hs_plus -p msandbox -u msandbox -po 5625 -s /tmp/mysql_sandbox5625.sock

 # options from config
 BlastoutAnalyze.pm --mode=import_blastout -if t/data/sc_OUTplus100 -o t/data/ -d hs_plus

Extracts columns (prot_id, ti, pgi, e_value with no duplicates), writes them to tmp file and imports that file into MySQL (needs MySQL connection parameters to connect to MySQL).

=item import_map

 # options from command line
 BlastoutAnalyze.pm --mode=import_map -if t/data/hs3.phmap_names -d hs_plus -v -p msandbox -u msandbox -po 5625 -s /tmp/mysql_sandbox5625.sock

 # options from config
 BlastoutAnalyze.pm --mode=import_map -if t/data/hs3.phmap_names -d hs_plus -v

Removes header from map file and writes columns (prot_id, phylostrata, ti, psname) to tmp file and imports that file into MySQL (needs MySQL connection parameters to connect to MySQL).

=item import_blastdb_stats

 # options from command line
 BlastoutAnalyze.pm --mode=import_blastdb_stats -if t/data/analyze_hs_9606_cdhit_large_extracted  -d hs_plus -v -p msandbox -u msandbox -po 5625 -s /tmp/mysql_sandbox5625.sock

 # options from config
 BlastoutAnalyze.pm --mode=import_blastdb_stats -if t/data/analyze_hs_9606_cdhit_large_extracted  -d hs_plus -v

Imports analyze stats file created by AnalyzePhyloDb.
  AnalysePhyloDb -n /home/msestak/dropbox/Databases/db_02_09_2015/data/nr_raw/nodes.dmp.fmt.new.sync -d /home/msestak/dropbox/Databases/db_02_09_2015/data/cdhit_large/extracted/ -t 9606 > analyze_hs_9606_cdhit_large_extracted





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

=head1 LICENSE

Copyright (C) Martin Sebastijan Šestak.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Martin Sebastijan Šestak
mocnii E<lt>msestak@irb.hrE<gt>

=cut

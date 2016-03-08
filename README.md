# NAME

BlastoutAnalyze - It's barebones modulino to build custom scripts. Useful snipets go here.

# SYNOPSIS

    # connection parameters in barebones.cnf
    BlastoutAnalyze.pm --mode=create_db -d test_db_here

# DESCRIPTION

BlastoutAnalyze is modulino used as starting point for modulino development. It includes config, command-line and logging management.

    --mode=mode                Description
    --mode=create_db           drops and recreates database in MySQL (needs MySQL connection parameters from config)
    
    For help write:
    BlastoutAnalyze.pm -h
    BlastoutAnalyze.pm -m

## MODES

- create\_db

        # options from command line
        BlastoutAnalyze.pm --mode=create_db -ho localhost -d test_db_here -p msandbox -u msandbox -po 5625 -s /tmp/mysql_sandbox5625.sock --charset=ascii

        # options from config
        BlastoutAnalyze.pm --mode=create_db -d test_db_here

    Drops ( if it exists) and recreates database in MySQL (needs MySQL connection parameters to connect to MySQL).

# CONFIGURATION

All configuration in set in barebones.cnf that is found in ./lib directory (it can also be set with --config option on command line). It follows [Config::Std](https://metacpan.org/pod/Config::Std) format and rules.
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

# LICENSE

Copyright (C) Martin Sebastijan Šestak.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# AUTHOR

Martin Sebastijan Šestak
mocnii <msestak@irb.hr>

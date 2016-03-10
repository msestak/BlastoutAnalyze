# NAME

BlastoutAnalyze - It's a modulino used to analyze BLAST output and database.

# SYNOPSIS

    # drop and recreate database (connection parameters in blastoutanalyze.cnf)
    BlastoutAnalyze.pm --mode=create_db -d test_db_here

    # remove duplicates and import BLAST output file into MySQL database
    BlastoutAnalyze.pm --mode=import_blastout -if t/data/sc_OUTplus100 -o t/data/ -d hs_plus

    # remove header and import phylostratigraphic map into MySQL database (reads PS, TI and PSNAME from config)
    BlastoutAnalyze.pm --mode=import_map -if t/data/hs3.phmap_names -d hs_plus -v

# DESCRIPTION

BlastoutAnalyze is modulino used to analyze BLAST database (to get content in genomes and sequences) and BLAST output (to figure out wwhere are hits comming from. It includes config, command-line and logging management.

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

- import\_blastout

        # options from command line
        BlastoutAnalyze.pm --mode=import_blastout -if t/data/sc_OUTplus100 -o t/data/ -d hs_plus -p msandbox -u msandbox -po 5625 -s /tmp/mysql_sandbox5625.sock

        # options from config
        BlastoutAnalyze.pm --mode=import_blastout -if t/data/sc_OUTplus100 -o t/data/ -d hs_plus

    Extracts columns (prot\_id, ti, pgi, e\_value with no duplicates), writes them to tmp file and imports that file into MySQL (needs MySQL connection parameters to connect to MySQL).

- import\_map

        # options from command line
        BlastoutAnalyze.pm --mode=import_map -if t/data/hs3.phmap_names -d hs_plus -v -p msandbox -u msandbox -po 5625 -s /tmp/mysql_sandbox5625.sock

        # options from config
        BlastoutAnalyze.pm --mode=import_map -if t/data/hs3.phmap_names -d hs_plus -v

    Removes header from map file and writes columns (prot\_id, phylostrata, ti, psname) to tmp file and imports that file into MySQL (needs MySQL connection parameters to connect to MySQL).

# CONFIGURATION

All configuration in set in blastoutanalyze.cnf that is found in ./lib directory (it can also be set with --config option on command line). It follows [Config::Std](https://metacpan.org/pod/Config::Std) format and rules.
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

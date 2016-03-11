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
    It can use PS and TI config sections.

- import\_blastdb\_stats

        # options from command line
        BlastoutAnalyze.pm --mode=import_blastdb_stats -if t/data/analyze_hs_9606_cdhit_large_extracted  -d hs_plus -v -p msandbox -u msandbox -po 5625 -s /tmp/mysql_sandbox5625.sock

        # options from config
        BlastoutAnalyze.pm --mode=import_blastdb_stats -if t/data/analyze_hs_9606_cdhit_large_extracted  -d hs_plus -v

    Imports analyze stats file created by AnalyzePhyloDb.
      AnalysePhyloDb -n /home/msestak/dropbox/Databases/db\_02\_09\_2015/data/nr\_raw/nodes.dmp.fmt.new.sync -d /home/msestak/dropbox/Databases/db\_02\_09\_2015/data/cdhit\_large/extracted/ -t 9606 > analyze\_hs\_9606\_cdhit\_large\_extracted
    It can use PS and TI config sections.

- import\_names

        # options from command line
        BlastoutAnalyze.pm --mode=import_names -if t/data/names.dmp.fmt.new  -d hs_plus -v -p msandbox -u msandbox -po 5625 -s /tmp/mysql_sandbox5625.sock

        # options from config
        BlastoutAnalyze.pm --mode=import_names -if t/data/names.dmp.fmt.new  -d hs_plus -v

    Imports names file (columns ti, species\_name) into MySQL.

- analyze\_blastout

        # options from command line
        BlastoutAnalyze.pm --mode=analyze_blastout -d hs_plus -v -p msandbox -u msandbox -po 5625 -s /tmp/mysql_sandbox5625.sock

        # options from config
        BlastoutAnalyze.pm --mode=analyze_blastout -d hs_plus -v

    Runs BLAST output analysis - expanding every prot\_id to its tax\_id hits and species names. It creates 2 table: one with all tax\_ids fora each gene, and one with tax\_ids only that are for phylostratum of interest.

- report\_per\_ps

        # options from command line
        lib/BlastoutAnalyze.pm --mode=report_per_ps -o t/data/ -d hs_plus -v -p msandbox -u msandbox -po 5625 -s /tmp/mysql_sandbox5625.sock

        # options from config
        lib/BlastoutAnalyze.pm --mode=report_per_ps -o t/data/ -d hs_plus -v

    Runs summary per phylostrata per species of BLAST output analysis.

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

# EXAMPLE

    [msestak@tiktaalik blastoutanalyze]$ lib/BlastoutAnalyze.pm --mode=import_blastout -if /home/msestak/prepare_blast/out/hs_plus/hs_all_plus_21_12_2015 -o t/data/ -d hs_plus
    My input file: /home/msestak/prepare_blast/out/hs_plus/hs_all_plus_21_12_2015
    My absolute input file: /home/msestak/prepare_blast/out/hs_plus/hs_all_plus_21_12_2015
    My output path: t/data
    My absolute output path: /home/msestak/gitdir/blastoutanalyze/t/data
    \ {
        argv       [
            [0] "--mode=import_blastout",
            [1] "-if",
            [2] "/home/msestak/prepare_blast/out/hs_plus/hs_all_plus_21_12_2015",
            [3] "-o",
            [4] "t/data/",
            [5] "-d",
            [6] "hs_plus",
            [7] "-v",
            [8] "-v"
        ],
        charset    "ascii",
        config     "/home/msestak/gitdir/blastoutanalyze/lib/blastoutanalyze.cnf",
        database   "hs_plus",
        host       "localhost",
        infile     "/home/msestak/prepare_blast/out/hs_plus/hs_all_plus_21_12_2015",
        mode       [
            [0] "import_blastout"
        ],
        out        "/home/msestak/gitdir/blastoutanalyze/t/data",
        password   "msandbox",
        port       5625,
        quiet      0,
        socket     "/tmp/mysql_sandbox5625.sock",
        user       "msandbox",
        verbose    2
    }
    [2016/03/10 14:38:00,545] INFO> BlastoutAnalyze::_extract_blastout line:681==>Report: started processing of /home/msestak/prepare_blast/out/hs_plus/hs_all_plus_21_12_2015
    [2016/03/10 14:38:09,017]TRACE> BlastoutAnalyze::_extract_blastout line:701==>1000000 lines processed!
    ...
    [2016/03/10 17:24:50,134]TRACE> BlastoutAnalyze::_extract_blastout line:701==>1152000000 lines processed!
    [2016/03/10 17:24:53,210] INFO> BlastoutAnalyze::_extract_blastout line:707==>Report: file /home/msestak/gitdir/blastoutanalyze/t/data/hs_all_plus_21_12_2015_formated printed successfully with 503859793 lines (from 1152339698 original lines)
    [2016/03/10 17:24:53,215]TRACE> BlastoutAnalyze::_create_table line:458==>Action: hs_all_plus_21_12_2015 dropped successfully!
    [2016/03/10 17:24:53,229]TRACE> BlastoutAnalyze::_create_table line:462==>Action: hs_all_plus_21_12_2015 created successfully!
    [2016/03/10 17:24:53,229]TRACE> BlastoutAnalyze::_dbi_connect line:429==>Report: connected to DBI:mysql:database=hs_plus;host=localhost;port=5625;mysql_socket=/tmp/mysql_sandbox5625.sock;mysql_server_prepare=1;mysql_use_result=0 by dbh DBI::db=HASH(0x1b024d8)
    [2016/03/10 17:24:53,231]TRACE> BlastoutAnalyze::import_blastout line:611==>Time running:0.001 sec      STATE:System lock
    [2016/03/10 17:25:03,232]TRACE> BlastoutAnalyze::import_blastout line:611==>Time running:10.002 sec     STATE:Fetched about 7730000 rows, loading data still remains
    ...
    [2016/03/10 17:47:53,470]TRACE> BlastoutAnalyze::import_blastout line:611==>Time running:1380.240 sec   STATE:Fetched about 503859000 rows, loading data still remains
    [2016/03/10 17:48:03,472]TRACE> BlastoutAnalyze::import_blastout line:611==>Time running:1390.242 sec   STATE:Loading of data about 1.9% done
    ...
    [2016/03/10 17:54:23,541]TRACE> BlastoutAnalyze::import_blastout line:611==>Time running:1770.311 sec   STATE:Loading of data about 97.9% done
    [2016/03/10 17:54:33,544]TRACE> BlastoutAnalyze::import_blastout line:611==>Time running:1780.313 sec   STATE:Verifying index uniqueness: Checked 20000 of 0 rows in key-PRIMA
    ...
    [2016/03/10 19:19:04,335]TRACE> BlastoutAnalyze::import_blastout line:611==>Time running:6851.105 sec   STATE:Verifying index uniqueness: Checked 503780000 of 0 rows in key-P
    [2016/03/10 19:19:14,336] INFO> BlastoutAnalyze::import_blastout line:617==>Action: import inserted 503859793 rows!
    [2016/03/10 19:19:14,337]TRACE> BlastoutAnalyze::_dbi_connect line:429==>Report: connected to DBI:mysql:database=hs_plus;host=localhost;port=5625;mysql_socket=/tmp/mysql_sandbox5625.sock;mysql_server_prepare=1;mysql_use_result=0 by dbh DBI::db=HASH(0x1afa9c8)
    [2016/03/10 19:19:14,340]TRACE> BlastoutAnalyze::import_blastout line:640==>Time running:0.002 sec      STATE:init
    [2016/03/10 19:19:24,341]TRACE> BlastoutAnalyze::import_blastout line:640==>Time running:10.004 sec     STATE:Adding indexes: Fetched 40143000 of about 503859793 rows, loadin
    ...
    [2016/03/10 19:34:24,496]TRACE> BlastoutAnalyze::import_blastout line:640==>Time running:910.159 sec    STATE:Adding indexes: Fetched 503859000 of about 503859793 rows, loadi
    [2016/03/10 19:34:34,497]TRACE> BlastoutAnalyze::import_blastout line:640==>Time running:920.160 sec    STATE:Loading of data about 0.8% done
    ...
    [2016/03/10 19:40:44,596]TRACE> BlastoutAnalyze::import_blastout line:640==>Time running:1290.258 sec   STATE:Loading of data about 98.9% done
    [2016/03/10 19:40:54,596] INFO> BlastoutAnalyze::import_blastout line:647==>Action: Index tix on hs_all_plus_21_12_2015 added successfully!
    [2016/03/10 19:40:59,627] WARN> BlastoutAnalyze::import_blastout line:650==>File /home/msestak/gitdir/blastoutanalyze/t/data/hs_all_plus_21_12_2015_formated unlinked!
    [2016/03/10 19:40:59,628] INFO> BlastoutAnalyze::run line:89==>TIME when finished for: import_blastout

# AUTHOR

Martin Sebastijan Šestak mocnii <msestak@irb.hr>

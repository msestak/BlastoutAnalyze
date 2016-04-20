# NAME

BlastoutAnalyze - It's a modulino used to analyze BLAST output and database.

# SYNOPSIS

    # drop and recreate database (connection parameters in blastoutanalyze.cnf)
    BlastoutAnalyze.pm --mode=create_db -d test_db_here

    # remove duplicates and import BLAST output file into MySQL database
    BlastoutAnalyze.pm --mode=import_blastout -if t/data/hs_all_plus_21_12_2015 -d hs_plus -v

    # remove header and import phylostratigraphic map into MySQL database (reads PS, TI and PSNAME from config)
    BlastoutAnalyze.pm --mode=import_map -if t/data/hs3.phmap_names -d hs_plus -v

    # imports analyze stats file created by AnalyzePhyloDb (uses TI and PS sections in config)
    BlastoutAnalyze.pm --mode=import_blastdb_stats -if t/data/analyze_hs_9606_cdhit_large_extracted  -d hs_plus -v

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
    BlastoutAnalyze.pm --mode=import_blastout -if t/data/hs_all_plus_21_12_2015 -d hs_blastout -v

    # import full BLAST database (plus ti and pgi columns)
    BlastoutAnalyze.pm --mode=import_blastout -if t/data/db90_head.gz -d hs_blastout -v -v

# DESCRIPTION

BlastoutAnalyze is modulino used to analyze BLAST database (to get content in genomes and sequences) and BLAST output (to figure out wwhere are hits comming from). It includes config, command-line and logging management.

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
        BlastoutAnalyze.pm --mode=import_blastout -if t/data/hs_all_plus_21_12_2015 -d hs_plus -v -p msandbox -u msandbox -po 5625 -s /tmp/mysql_sandbox5625.sock

        # options from config
        BlastoutAnalyze.pm --mode=import_blastout -if t/data/hs_all_plus_21_12_2015 -d hs_plus -v

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
        lib/BlastoutAnalyze.pm --mode=report_per_ps -d hs_plus -v -p msandbox -u msandbox -po 5625 -s /tmp/mysql_sandbox5625.sock

        # options from config
        lib/BlastoutAnalyze.pm --mode=report_per_ps -d hs_plus -v

    Runs summary per phylostrata per species of BLAST output analysis.

- exclude\_ti\_from\_blastout

        # options from command line
        lib/BlastoutAnalyze.pm --mode=exclude_ti_from_blastout -if t/data/hs_all_plus_21_12_2015 -ti 428574 -v

        # options from config
        lib/BlastoutAnalyze.pm --mode=exclude_ti_from_blastout -if t/data/hs_all_plus_21_12_2015 -ti 428574 -v

    Removes specific hits from the BLAST output based on the specified tax\_id (exclude bad genomes).

- report\_per\_ps\_unique

        # options from command line
        BlastoutAnalyze.pm --mode=report_per_ps_unique -o t/data/ --report_per_ps=hs_all_plus_21_12_2015_report_per_ps -d hs_plus -v -p msandbox -u msandbox -po 5625 -s /tmp/mysql_sandbox5625.sock

        # options from config
        BlastoutAnalyze.pm --mode=report_per_ps_unique -d hs_plus -v

    Update report\_per\_ps table with unique and intersect hits and gene lists.

- import\_blastout\_full

        # options from command line
        BlastoutAnalyze.pm --mode=import_blastout -if t/data/hs_all_plus_21_12_2015 -d hs_blastout -v -p msandbox -u msandbox -po 5625 -s /tmp/mysql_sandbox5625.sock

        # options from config
        BlastoutAnalyze.pm --mode=import_blastout -if t/data/hs_all_plus_21_12_2015 -d hs_blastout -v

    Extracts hit column and splits it on ti and pgi and imports this file into MySQL (it has 2 extra columns = ti and pgi with no duplicates). It needs MySQL connection parameters to connect to MySQL.

- import\_blastdb

        # options from command line
        BlastoutAnalyze.pm --mode=import_blastdb -if t/data/db90_head.gz -d hs_blastout -v -p msandbox -u msandbox -po 5625 -s /tmp/mysql_sandbox5625.sock

        # options from config
        BlastoutAnalyze.pm --mode=import_blastout -if t/data/db90_head.gz -d hs_blastout -v -v

    Imports BLAST database file into MySQL (it has 2 extra columns = ti and pgi). It needs MySQL connection parameters to connect to MySQL.

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
mocnii
<msestak@irb.hr>

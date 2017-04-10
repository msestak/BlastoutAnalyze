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
        BlastoutAnalyze.pm --mode=import_blastdb_stats -if t/data/analyze_hs_9606_cdhit_large_extracted  -d hs_plus --names_tbl=names_dmp_fmt_new -v -p msandbox -u msandbox -po 5625 -s /tmp/mysql_sandbox5625.sock

        # options from config
        BlastoutAnalyze.pm --mode=import_blastdb_stats -if t/data/analyze_hs_9606_cdhit_large_extracted  -d hs_plus --names_tbl=names_dmp_fmt_new -v

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

- import\_blastdb

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

- import\_reports

        # options from command line
        BlastoutAnalyze.pm --mode=import_reports --in t/data/ -d origin --max_processes=4 -p msandbox -u msandbox -po 5625 -s /tmp/mysql_sandbox5625.sock
        BlastoutAnalyze.pm --mode=import_reports --in /msestak/workdir/origin_of_eukaryotes/ClickHouse_db_47_genomes/ -d origin --max_processes=4

        # options from config
        BlastoutAnalyze.pm --mode=import_reports --in t/data/ -d origin --max_processes=4

    Imports expanded reports per species in BLAST database into MySQL. It can import in parallel. It needs MySQL connection parameters to connect to MySQL.

- top\_hits

        # find N top hits for all species per domain in a database
        BlastoutAnalyze.pm --mode=top_hits -d kam --top_hits=10

    It finds top N species with most BLAST hits (proteins found) in prokaryotes per domain (Archaea, Cyanobacteria, Bacteria).

- reduce\_blastout

        # reduce blastout based on cutoff (it deletes hits if less or equal to cutoff per phylostratum)
        BlastoutAnalyze.pm --mode=reduce_blastout --stats=t/data/analyze_hs_9606_cdhit_large_extracted --blastout=t/data/hs_all_plus_21_12_2015 --out=t/data/ --cutoff=3 -v -v

    It deletes hits in a BLAST output file if number of tax ids per phylostratum is less or equal to cutoff. This means that if cutoff=3, all hits with 3 or less hits are deleted and only 4+ hits are retained.
    It requires blastout and analyze files. Analyze file is required to get distribution of tax ids per phylostratum.
    It works by importing to SQLite database, doing analysis there and exporting filtered BLAST output to $out directory (resulting blastout\_export file is deleted if it already exists). SQLite database is also deleted after the analysis.

        # reduce blastout based only on ps1 cutoff_ps1 (it deletes hits if less or equal to cutoff_ps1 from ps1)
        # or
        BlastoutAnalyze.pm --mode=reduce_blastout --stats=t/data/analyze_hs_9606_cdhit_large_extracted --blastout=t/data/hs_all_plus_21_12_2015 --out=t/data/ --cutoff_ps1=1 -v

    It deletes hits in a BLAST output file only from phylostratum 1 if number of tax ids per phylostratum is less or equal to cutoff\_ps1. This means that if cutoff\_ps1=1, all hits with only one hit in ps1 are deleted and only 2+ hits are retained.

- export\_to\_ff

        # export proteomes from BLAST database table to .ff file ready for BLAST
        BlastoutAnalyze.pm --mode=export_to_ff --out=/msestak/db_22_03_2017/data/all_ff_final/ --table_name=old_proteomes -d phylodb -p msandbox -u msandbox -po 5716 -s /tmp/mysql_sandbox5716.sock

    It exports all proteomes from BLAST database table into .ff files named after tax\_id. It has structure needed for PhyloStrat (pgi|ti|pi identifier). Works opposite of --mode=import\_blastdb.

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

# INSTALL

Clone GitHub repo and install dependencies with cpanm.

    git clone https://github.com/msestak/BlastoutAnalyze
    cd BlastoutAnalyze
    # repeat cpanm install until it installs all modules
    cpanm -f -n --installdeps .
    # update DBD::SQLite module
    cpanm -n DBD::SQLite

# LICENSE

Copyright (C) 2016-2017 Martin Sebastijan Šestak.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

# AUTHOR

Martin Sebastijan Šestak
mocnii
<msestak@irb.hr>

requires 'perl', '5.010001';

on 'test' => sub {
    requires 'Test::More', '0.98';
	requires 'Test::Log::Log4perl';
};

requires 'strict';
requires 'warnings';
requires 'autodie';
requires 'Exporter';
requires 'Carp';
requires 'Data::Dumper';
requires 'Data::Printer';
requires 'Path::Tiny';
requires 'DBI';
requires 'DBD::mysql';
requires 'Getopt::Long';
requires 'Pod::Usage';
requires 'Capture::Tiny';
requires 'Log::Log4perl';
requires 'File::Find::Rule';
requires 'DBI';
requires 'DBD::mysql';

author_requires 'Term::ReadKey';
author_requires 'Regexp::Debugger';

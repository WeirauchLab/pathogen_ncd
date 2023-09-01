#!/usr/bin/env perl
use strict;
use warnings;
use autodie;
use JSON;
use English;
use Template;
use File::Basename;

my $jsonfile = 'meta.json';
my $section = 'meta';
my ($json, $fh, $dirs, $meta, $tt);

foreach (@ARGV) {
    if (-r) {
        $jsonfile = $_;
    } else {
        $section = $_;
    }
}

# (filename, dirs, suffix)
($_, $dirs, $_) = fileparse $jsonfile, '.json';
my $outfile = "$dirs$section.html";
my $template = "$section.tt";

{
    open $fh, '<', $jsonfile;
    $/ = undef;
    $json = <$fh>;
}

$meta = decode_json $json;
$tt = Template->new({ INCLUDE_PATH => 'templates' });

# source: https://stackoverflow.com/a/47946606
use open qw( :std :encoding(UTF-8) );
open my $ofh, '>', "$outfile";

$tt->process($template, $meta, $ofh) || die $tt->error();
close $ofh;

print STDERR "Wrote '$outfile'.\n";

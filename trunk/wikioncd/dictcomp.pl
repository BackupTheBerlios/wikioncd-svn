#!/usr/bin/perl
#
require 'dictcomp.pm';

my $text = join '', (<>);

my $c = Compress::Dictionary::ADR::new_for_compress("dictionary");
my $compressed = $c->compress($text);
print $compressed;

my $d = Compress::Dictionary::ADR::new_for_decompress("dictionary");

open my $out, '>', 'decompressed.txt';
my $decompressed = $d->decompress($compressed);
print $out $decompressed;
close $out;


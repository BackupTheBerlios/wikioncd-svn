###
# WikiOnCD Conversion Tool
# Part of WikiOnCD
# Copyright (C) 2005, Andrew Rodland <arodland@entermail.net>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

use IO::File;
use List::Util;

my %words;

$::savings_threshold = 1024;

sub get_next_record {
	my $fh = shift;

	while (1) {
		if ($buf =~ m/\(\d+,(\d+),'(.*?)','(.*?)','.*?',\d+,'(.*?)','.*?','.*?',\d+,(\d+).+?\)[,;]/g) {

			my ($ns, $title, $text, $ts, $redir) = ($1, $2, $3, $4, $5);

			%unescape = (
					"'" => "'", '"' => '"', "_" => "_", "%" => "%", "\\" => "\\",
					"n" => "\n", "t" => "\t", "r" => "");

			$title =~ s/\\(.)/$unescape{$1}/eg;
			$text =~ s/\\(.)/$unescape{$1}/eg;

# namespace, title, text, timestamp, is_redirect
			return ($ns, $title, $text, $ts, $redir);
		} else {
			if (! defined($buf = <$fh>)) {
				return (undef);
			}
		}
	}
}

sub count_words {

	my $filename = shift;
	open my $fh, $filename or die $!;

	my $n = 0;

	while (!eof($fh)) {
		my ($namespace, $title, $text, undef, $is_redirect) = get_next_record($fh);
		next unless defined($namespace);

#		next unless defined $::namespaces{$namespace};
		next unless $namespace == 0 || $namespace == 4 || $namespace == 10 ||
			$namespace == 14;
#		next unless  $namespace == 10 || $namespace == 14;

		unless ($is_redirect) {
			for my $thing ($text, $title) {
				while ($thing =~ /(\w+)/g) {
					$words{$1} ++;
				}
			}
		}

		$n++;

		unless ($n % 1000) {
			print "\r$n";
		}
	}
	print "\r$n\n";
	close $fh;
	print STDERR "There are ", scalar keys %words, " unique words.\n";
}

my $filename = $ARGV[0];

$|++;

count_words($filename);
my $word, $count;

open my $out, '>', 'wordcounts';

while (($word, $count) = each %words) {
	print $out "$word $count\n" if length($word) > 1 && $count > 1;
}

close $out;

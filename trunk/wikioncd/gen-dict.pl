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

$::savings_threshold = 256;

sub load_dict {
	open my $in, "<", "wordcounts" or die $!;
	my @words;

	my $n = 0;
	
	while(<$in>) {
		chomp;
		my ($word, $count) = split ' ', $_;
		my $savings = $count * (length($word) - 1) - length($word);
		if ($savings >= $::savings_threshold) {
			push @words, [$word, $savings, $count];
		}
		$n ++;
		unless ($n % 1000) {
			print "\rLoaded $n words.";
		}
	}
	
	print "\rLoaded $n words.\n";
	return @words;
}

sub gen_dict {

	local *list = \@_;	

	open my $dict, ">dictionary" or die $!; 
	my $bs = 0;
	my $cont = 0;

	print STDERR "Kept ", scalar @list, " words.\n";
	print STDERR "Sorting...\n";

	for (1 .. 64) {
		my $max = $list[0][1];
		my $max_ind = 0;

		for (0 .. $#list) {
			if ($list[$_][1] > $max) {
				$max_ind = $_;
				$max = $list[$_][1];
			}
		}

		goto out if $max < $::savings_threshold;

		$bs += $max;
		print $dict $list[$max_ind][0], "\n";	
		splice @list, $max_ind, 1, ();
	}

	print "Phase 2: Filtering... ";
	for (@list) {
		$_->[1] = $_->[2] * (length($_->[0]) - 2) - length($_->[0]);
	}

	@list = grep { $_->[1] >= $::savings_threshold } @list;
	print STDERR scalar @list, " words.\n";

	print STDERR "Sorting...\n";

	for (1 .. 8001) {
		my $max = $list[0][1];
		my $max_ind = 0;

		for (0 .. $#list) {
			if ($list[$_][1] > $max) {
				$max_ind = $_;
				$max = $list[$_][1];
			}
		}

		goto out if $max < $::savings_threshold;

		$bs += $max;
		print $dict $list[$max_ind][0], "\n";	
		splice @list, $max_ind, 1, ();
	}

	for (@list) {
		$_->[1] = $_->[2] * (length($_->[0]) - 3) - length($_->[0]);
	}

	print STDERR "Phase 3: Filtering... ";
	@list = grep { $_->[1] >= $::savings_threshold } @list;
	print STDERR scalar @list, " words.\n";


	if (@list > 2056320) {
		splice @list, 2056320;
	}

	for (@list) {
		print $dict $_->[0], "\n";
		$bs += $_->[1];
	}

out: close $dict;
	 print "$bs possible bytes saved.\n";
}

$|++;

my @list = load_dict();
gen_dict(@list);

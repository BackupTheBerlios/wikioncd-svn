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
					$words{$1} = [ undef, 0, 0 ] unless exists $words{$1};
					$words{$1}->[2] ++;
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

sub gen_dict {

	open my $dict, ">dictionary" or die $!; 
	my $bs = 0;
	my $cont = 0;

#	my @list = map { [ $_, $words{$_} * (length($_) - 1) - length($_),
#		$words{$_} ] } keys %words;
#	%words = ();

	print STDERR scalar keys %words, " words.\n";

	for (keys %words) {
		my $a = $words{$_};
		$a->[1] = $a->[2] * (length($_) - 2) - length($_);
		if ($a->[1] >= $::savings_threshold) {
			$a->[0] = $_;
			push @list, $a;
		}
		delete $words{$_};
	}
	%words = ();
	print STDERR scalar @list, " words.\n";

	for (1 .. 64) {
		my $max = $list[0][1];
		my $max_ind = 0;

		for (0 .. $#list) {
			if ($list[$_][1] > $max) {
				$max_ind = $_;
				$max = $list[$_][1];
			}
		}

		print STDERR "$list[$max_ind][0]: $list[$max_ind][1]\n";	
		goto out if $max < $::savings_threshold;

		$bs += $max;
		print $dict $list[$max_ind][0], "\n";	
		splice @list, $max_ind, 1, ();
	}

	for (@list) {
		$_->[1] = $_->[2] * (length($_->[0]) - 2) - length($_->[0]);
	}

	print STDERR scalar @list, " words.\n";
	@list = grep { $_->[1] >= $::savings_threshold } @list;
	print STDERR scalar @list, " words.\n";


	for (1 .. 8001) {
		my $max = $list[0][1];
		my $max_ind = 0;

		for (0 .. $#list) {
			if ($list[$_][1] > $max) {
				$max_ind = $_;
				$max = $list[$_][1];
			}
		}

		print STDERR "$list[$max_ind][0]: $list[$max_ind][1]\n";	
		goto out if $max < $::savings_threshold;

		$bs += $max;
		print $dict $list[$max_ind][0], "\n";	
		splice @list, $max_ind, 1, ();
	}

	for (@list) {
		$_->[1] = $_->[2] * (length($_->[0]) - 3) - length($_->[0]);
	}

	print STDERR scalar @list, " words.\n";
	@list = grep { $_->[1] >= $::savings_threshold } @list;
	print STDERR scalar @list, " words.\n";


	for (1 .. 2064385) {
		my $max = $list[0][1];
		my $max_ind = 0;

		for (0 .. $#list) {
			if ($list[$_][1] > $max) {
				$max_ind = $_;
				$max = $list[$_][1];
			}
		}

		print STDERR "$list[$max_ind][0]: $list[$max_ind][1]\n";	
		goto out if $max < $::savings_threshold;

		$bs += $max;
		print $dict $list[$max_ind][0], "\n";
		splice @list, $max_ind, 1, ();
	}

out: close $dict;
	 print "$bs possible bytes saved.\n";
}

sub gen_dict_sorty {

	open my $dict, ">dictionary" or die $!; 
	my $bs = 0;
	my $cont = 0;

	my @sorted = sort { $words{$b} * (length($b) - 1) - length($b)
		<=>
			$words{$a} * (length($a) - 1) - length($a)
	} keys %words;

	my @top = splice @sorted, 0, 64;

	for (@top) {
		my $score = $words{$_} * (length($_) - 1) - length($_);
		goto out if $score < $::savings_threshold;
		$bs += $score;
		$count ++;
		print $dict $_, "\n";
		delete $words{$_};
	}

	my @sorted = sort { $words{$b} * (length($b) - 2) - length($b)
		<=>
			$words{$a} * (length($a) - 2) - length($a)
	} keys %words;

	my @top = splice @sorted, 0, 8001;

	for (@top) {
		my $score = $words{$_} * (length($_) - 2) - length($_);
		goto out if $score < $::savings_threshold;
		$bs += $score;
		$count ++;
		print $dict $_, "\n";
		delete $words{$_};
	}

	my @sorted = sort { $words{$b} * (length($b) - 3) - length($b)
		<=>
			$words{$a} * (length($a) - 3) - length($a)
	} keys %words;

#	my @top = splice @sorted, 0, 2056320;

	for (@sorted) {
		my $score = $words{$_} * (length($_) - 3) - length($_);
		goto out if $score < $::savings_threshold;
		goto out if $count >= 2064385;
		$bs += $score;
		$count++;
		print $dict $_, "\n";
	}

out: close $dict;
	 print "$bs possible bytes saved.\n";
}

sub gen_dict_schwartz {

	open my $dict, ">dictionary" or die $!; 
	my $bs = 0;

	my @sorted = 
		sort { $b->[1] <=> $a->[1] }
	map { [ $_, $words{$_} * (length($_) - 1) - length($_) ] } 
	keys %words;

	my @top = splice @sorted, 0, 64;

	for (@top) {
		goto out if $_->[1] < $::savings_threshold;
		$bs += $_->[1];
		print $dict $_->[0], "\n";
		delete $words{$_->[0]};
	}

	@sorted =
		sort { $b->[1] <=> $a->[1] }
	map { [ $_, $words{$_} * (length($_) - 2) - length($_) ] } 
	keys %words;

	@top = splice @sorted, 0, 8001;

	for (@top) {
		goto out if $_->[1] < $::savings_threshold;
		$bs += $_->[1];
		print $dict $_->[0], "\n";
		delete $words{$_->[0]};
	}

	@sorted =
		sort { $b->[1] <=> $a->[1] }
	map { [ $_, $words{$b} * (length($_) - 3) - length($_) ] } 
	keys %words;

	@top = splice @sorted, 0, 2056320;

	for (@top) {
		goto out if $_->[1] < $::savings_threshold;
		$bs += $_->[1];
		print $dict $_->[0], "\n";
	}

out: close $dict;
	 print "$bs possible bytes saved.\n";
}

my $filename = $ARGV[0];

$|++;

count_words($filename);
gen_dict();

#!/usr/bin/perl
###
# Manual Retrieval Tool
# Part of WikiOnCD
# Copyright (C) 2005, Andrew Rodland <arodland@entermail.net>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.


#use Compress::Bzip2;
use Tree::Binary::Search;
require 'bzr.pm';

sub load_redirect {
	my $prefix = shift;

	my %redir;

	open my $fh, "out/$prefix/redirect";
	while (<$fh>) {
		chomp;
		my ($from, $to) = split /:/;
		$redir{$from} = $to;
	}
	close $fh;
	return \%redir;
}


sub simplify_title {
	my ($title, $namespace) = @_;
	$title =~ s/[\s_]+/ /g;
	$title = ucfirst lc $title;
	$title .= "_$namespace" if $namespace;
	return $title;
}


sub title_to_web {
	my $simp = simplify_title(@_);

# These two chars have to be completely boring
	substr($simp, 0, 2) =~ s/[^A-Za-z0-9\_]/_/g;
	return $simp;
}

sub title_to_key {
	my ($title, $ns) = @_;
	my $simplified = title_to_web($title);

	my $key = $simplified;

	$key .= "-$ns" if $ns;

	$counter = 0;
	while (defined($::titles{$key}) && $::titles{$key} ne $simplified) {
		$counter ++;
		
		$key = $simplified;
		$key .= "-$ns" if $ns;
		$key .= "-$counter";
	}

	$::titles{$key} = $simplified unless defined($::titles{$key});

	return $key;
}

sub read_file {
	my $filename = shift;
	
	my $prefix = substr $filename, 0, 2;
	$prefix .= lc $prefix if length($prefix) < 2;
	my $first = substr $prefix, 0, 1;

	my $bzr = Compress::Bzip2::RandomAccess->new_from_file(
			"out/$first/$prefix.bzr");

	return $bzr->read_file($filename);
}

print read_file(title_to_web($ARGV[0], $ARGV[1]));
print "\n";

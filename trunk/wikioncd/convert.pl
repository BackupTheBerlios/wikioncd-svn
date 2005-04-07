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
require 'bzr.pm';

$::blocksize = 512;
$::debug = 0;
$::lang = "en";

sub simplify_title {
	my $title = shift;
	$title =~ s/[\s_]+/ /g;
	$title = ucfirst lc $title;
	return $title;
}


#sub title_to_web {
#	my ($title, $ns) = @_;
#	$title = lc $title;
#	$title =~ s/[^a-z0-9\_]/_/g;
#	$title .= "-$ns" if$ns;
#
#	return $title;
#}

sub title_to_web {
	my $simp = simplify_title(@_);

# These two chars have to be completely boring
	substr($simp, 0, 2) =~ s/[^A-Za-z0-9\_]/_/g;
	return $simp;
}

sub title_to_key {
	my ($title, $ns) = @_;

	$ns = $ns || "";

	my $simplified = title_to_web($title);

	my $key = $simplified;

	my $counter = 0;
	while (defined($::titles{$ns}{$key}) && $::titles{$ns}{$key} ne $simplified) {
		$counter ++;
		$key = $simplified;
		$key .= "_$counter";
	}

	$::titles{$ns}{$key} = $simplified unless defined($::titles{$ns}{$key});

	return $key;
}

sub key_to_title {
	my $key = shift;

	return $::titles{$key};
}

%namespaces = (
		0 => "",
		4 => "wp",
		10 => "t",
		14 => "c",
		);

%namespace_reverse = (
		"template" => 10,
		"category" => 14,
		"wikipedia" => 4,
		);

sub init_index {

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

		my $ns = $namespaces{$namespace};

		my $key = title_to_key($title, $ns);

		if ($is_redirect) {
			if ($text =~ /^\#REDIRECT \[\[([^]]+)\]/i) {
				my $target = $1;
				
				$target =~ s/^.*://;
				$target = title_to_key($target, $ns);

				if ($target eq $key) {
					print STDERR "Wtf? Circular redirect. key=$key ns=$ns\n" if $::debug;
				} else {
					print STDERR $key, " => ", title_to_key($target, $ns), "\n" if $::debug;
					$key .= "_$ns" if $ns;
					$target .= "_$ns" if $ns;
					write_redirect($key, $target) if $target;
				}
			}
		} else {
			print STDERR $key, "\n" if $::debug;
			$key .= "_$ns" if $ns;
			write_data($key, \$text);
		}

		$n ++;
		if ($n % 1000 == 0) {
			print "\r$n ";
		}
	}

	print "\r$n\n";
}

sub write_data {
	my ($key, $text) = @_;

	rewrite_links($text);
	
	my $prefix = substr $key, 0, 2;
	$prefix .= lc $prefix if length($prefix) < 2;

	my $onechar = substr $prefix, 0, 1;

	if (!$::did_dir{$onechar}) {
		mkdir "out/$onechar" unless -d "out/$onechar";
		$::did_dir{$onechar} ++;
	}

	if (!defined $::bzr{$prefix}) {
		$::bzr{$prefix} = Compress::Bzip2::RandomAccess->new_to_file(
				"out/$onechar/$prefix.bzr", $::blocksize) or die $!; 
	}

	$::bzr{$prefix}->write_file($key, $$text) 
}


sub rewrite_links {
	
	my $text = shift;

	$$text =~ s/\[\[([^]]+)]/"[[" . rewrite_link($1) . "]"/ego;
	$$text =~ s/(?<!{){{([^{][^}]+)}/ "{{" . title_to_key($1, "t") . "}" /ego;

}

sub rewrite_link {
	my $link = shift;
	my $namespace = "";

	if ($link =~ /^:/) {
		$link =~ s/^://;
	}
	
	if ($link =~ /:/) {
		($namespace, $link) = split ':', $link, 2;

		if ($namespace ne $::lang) {
			if ($::namespace_reverse{lc $namespace}) {
				$namespace = $::namespaces{$::namespace_reverse{lc $namespace}};
			} else {
				return "$namespace:$link";
			}
		}
	}

	my ($target, $desc) = split /\|/, $link;
	
	my ($page, $anchor) = split /#/, $target;

	if (title_to_key($page, $namespace) ne title_to_web($page)) {
		$ret = title_to_key($page, $namespace);
		if (!$desc) {
			$desc = "|$page";
		}
	} else {
		$ret = $page;
	}

	$ret = "$namespace:$ret" if $namespace;
	$ret .= "#$anchor" if $anchor;
	$ret .= "|$desc" if $desc;

	return $ret;

}

sub write_redirect {
	my ($key, $pointer) = @_;

	my $prefix = substr $key, 0, 1;

	if (!$::did_dir{$prefix}) {
		mkdir "out/$prefix" unless -d "out/$prefix";
		$::did_dir{$prefix} ++;
	}

	if (!defined $::redirect_fh{$prefix}) {	
		$::redirect_fh{$prefix} = new IO::File;
		open $::redirect_fh{"$prefix"}, '>', "out/$prefix/redirect" or die $!;
	}
	print { $::redirect_fh{$prefix} } $key, ":", $pointer, "\n";
}

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


$|++;
my $out = select(STDERR);
$|++;
select($out);

my $filename = $ARGV[0];

mkdir("out");

init_index($filename);

print "Total FH: ", keys(%::redirect_fh) + keys(%::bzr), "\n";

print "Flushing...";
close $::redirect_fh{$_} for keys %::redirect_fh;
$::bzr{$_}->close_for_write() for keys %::bzr;
print "\n";


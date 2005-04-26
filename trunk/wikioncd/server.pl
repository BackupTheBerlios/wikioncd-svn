#!/usr/bin/perl
###
# WikiOnCD Server
# Part of WikiOnCD
# Copyright (C) 2005, Andrew Rodland <arodland@entermail.net>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

use Tree::Binary::Search;
use POE::Component::Server::HTTP;
use HTTP::Status;
use URI::Escape;
use DB_File;

require 'bzr-inline.pm';
require 'w2h.pl';

our $cache = 1;

sub load_redirect {
	my $prefix = shift;

	my %redir;

	tie %redir, "DB_File", "out/$prefix/redirect", O_RDONLY, 0666
		or (%redir = ());
	return \%redir;
}

sub canonicalize {
	my ($filename, $namespace) = @_;
	$namespace = lc $namespace;
	$namespace .= ":" if $namespace;

	$filename = ucfirst lc $filename;
	$filename =~ s/[^A-Za-z0-9,.'()\x80-\xff-]/_/g;

	return $namespace . $filename;
}


sub gen_filename {
	my $prefix = lc substr $_[0], 0, 2;
	$prefix =~ s/[^A-Za-z0-9_]/_/g;
	$prefix .= $prefix if length($prefix) < 2;

	my $first = substr $prefix, 0, 1;

	return ($first, $prefix);
}


sub wiki_handler {
	my ($request, $response) = @_;

	my $uri = uri_unescape($request->uri);
	my ($page) = ($uri =~ /wiki\/(.*)$/);
	my $namespace;
	if ($page =~ /:/) {
		($namespace, $page) = split ':', $page, 2;
	}

	return do_wiki($response, $page, $namespace);
}

sub get_handler {
	my ($request, $response) = @_;

	my $uri = $request->uri;
	
	use Data::Dumper;
	my %k = $uri->query_form;

	my $page = $k{q};
	
	if ($page) {	
		my $namespace;
		if ($page =~ /:/) {
			($namespace, $page) = split ':', $page, 2;
		}

		return do_wiki($response, $page, $namespace);
	} else {
		$response->code(500);
		$response->header("Content-Type" => "text/html");
		$response->content(<<EO500);
<html>
<head>
<title>Invalid Request</title>
<body>
<p>
I have no idea what you were going for, there, but it didn&apos;t work.
Sorry.
</p>
EO500
		return RC_OK;
	}

}

sub get_wiki {
	my ($page, $namespace) = @_;

	my $filename = canonicalize($page, $namespace);

	my ($first, $prefix) = gen_filename($page);

	$::redirect{$first} = load_redirect($first) unless defined $::redirect{$first};

	my $count = 0;
	
	while ($::redirect{$first}{$filename}) {
		$filename = $::redirect{$first}{$filename};
		my $first = substr $filename, 0, 1;
		$::redirect{$first} = load_redirect($first) unless defined $::redirect{$first};
		$count ++;
		last if $count > 3;
	}


	my $file = read_file($page, $namespace);
	return $file;
}

sub do_wiki {
	my ($response, $page, $namespace) = @_;

	my $file = get_wiki($page, $namespace);
	
	if ($file) {
		$response->code(RC_OK);
		$response->header("Content-Type" => "text/html");
	
		my $html = WikiToHTML($page, $file, $namespace, 1, 1);

		$response->content($html);
	} else {
		do_404($response, $namespace ? "$namespace:" : "" . $page);
	}
	return RC_OK;
}

sub read_file {
	my ($page, $namespace) = @_;

	my $filename = canonicalize($page, $namespace);

	print STDERR "read_file wants $filename -- " if $::debug;

	my ($first, $prefix) = gen_filename($page);

	print STDERR "geting it from $first/$prefix.bzr\n" if $::debug;

	if (!defined $::bzr{$prefix}) {
		$::bzr{$prefix} = Compress::Bzip2::RandomAccess->new_from_file(
			"out/$first/$prefix.bzr") or return undef;
		if ($::cache) {
			$::bzr{$prefix}->cache_offsets;
		}
	}
	my $ret = $::bzr{$prefix}->read_file($filename);
	return $ret;
}

sub do_404 {
	my ($response, $page) = @_;

	$response->code(404);
	$response->header("Content-Type" => "text/html");
	$response->content(<<EO404);
<html>
<head>
<title>404 - Not Found</title>
</head>
<body>
<h1>Not Found</h1>
<p>
Sorry, the article &quot;$page&quot; was not found. If you entered the address
yourself, make sure that you typed it correctly. If you followed a link from
another article, then the article &quot;$page&quot; may not actually exist in
this edition of the Wikipedia CD Image. You may wish to add this content to the
online Wikipedia at <a href="http://$wiki_language.wikipedia.org">
http://$wiki_language.wikipedia.org</a>. For now, either use the back button in
your browser, or visit the <a href="/$MainPagePath">$MainPageName</a>.
</p>
</body>
</html>
EO404
	return RC_OK;
}

sub default_handler {
	my ($request, $response) = @_;
	return do_wiki($response, "Main Page", "");
}	
	
my $server = POE::Component::Server::HTTP->new(
		Port => 8080,
		Headers => {
			Server => "WikiOnCD"
		},
		ContentHandler => {
			'/' => \&default_handler,
			'/wiki/' => \&wiki_handler,
			'/search/' => \&get_handler,
		}
		);

POE::Kernel->call($aliases->{httpd}, "shutdown");
POE::Kernel->run;


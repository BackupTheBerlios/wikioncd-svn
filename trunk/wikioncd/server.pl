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

require 'bzr.pm';
require 'w2h.pl';

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
	my $title = shift;
	$title =~ s/[\s_]+/ /g;
	$title = ucfirst lc $title;
	return $title;
}


sub title_to_web {
	my ($title, $namespace) = @_;
	my $simp = simplify_title($title);

	
# These two chars have to be completely boring
	substr($simp, 0, 2) =~ s/[^A-Za-z0-9\_]/_/g;

	$simp .= "_$namespace" if $namespace;

	return $simp;
}

sub title_to_key {
	my ($title, $ns) = @_;
	my $simplified = title_to_web($title);

	my $key = $simplified;

	$key .= "_$ns" if $ns;

	$counter = 0;
	while (defined($::titles{$key}) && $::titles{$key} ne $simplified) {
		$counter ++;
		
		$key = $simplified;
		$key .= "_$ns" if $ns;
		$key .= "_$counter";
	}

	$::titles{$key} = $simplified unless defined($::titles{$key});

	return $key;
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

	
	my $first = substr $filename, 0, 1;

	$::redirect{$first} = load_redirect($first) unless $::redirect{$first};

	my $count = 0;
	
	while ($::redirect{$first}{$filename}) {
		$filename = $::redirect{$first}{$filename};
		my $first = substr $filename, 0, 1;
		$::redirect{$first} = load_redirect($first) unless $::redirect{$first};
		$count ++;
		last if $count > 3;
	}

	my $filename = title_to_web($page, $namespace);

	my $file = read_file($filename);
	return $file;
}

sub do_wiki {
	my ($response, $page, $namespace) = @_;

	my $filename = title_to_web($page);

	my $file = get_wiki($page, $namespace);
	
	if ($file) {
		$response->code(RC_OK);
		$response->header("Content-Type" => "text/html");
		
		$response->content(WikiToHTML($filename, $file, 1, 1));
	} else {
		do_404($response, $namespace ? "$namespace:" : "" . $page);
	}
	return RC_OK;
}

sub read_file {
	my $filename = shift;

	my $prefix = substr $filename, 0, 2;
	$prefix .= lc $prefix if length($prefix) < 2;
	my $first = substr $prefix, 0, 1;

	if (!defined $::bzr{$prefix}) {
		$::bzr{$prefix} = Compress::Bzip2::RandomAccess->new_from_file(
			"out/$first/$prefix") or return undef;
	}
	return $::bzr{$prefix}->read_file($filename);
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


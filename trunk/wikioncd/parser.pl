#!/usr/bin/perl
#

use strict;
use warnings;

sub match_balanced {
	my ($data, $open, $close) = @_;

	my $count = 0;

	my $start = pos($$data);

	while ($$data =~ m#(\Q$open\E|\Q$close\E|(?i:<nowiki>))#cg) {
		my $token = $1;
		if ($token =~ m#<nowiki>#i) {
			$$data =~ m#\G.*</nowiki>#cgi;
			next;
		}

		if ($token eq $open) {
			$count ++;
		} elsif ($token eq $close) {
			$count --;
		}

		if ($count == 0) {
			last;
		}
	}

	my $len = pos($$data) - $start;
	return substr($$data, $start, $len);
}

sub do_list {
	my ($sigil, $stash, $cb) = @_;
	
	my $match = 0;
	my $alen = length($sigil);
	my $blen = length($$stash);

	while ($alen > $match && $blen > $match &&
			substr($sigil, $match, 1) eq substr($$stash, $match, 1)) {
		$match ++;
	}
#print STDERR "Comparing $sigil with $$stash -- $match in common.\n";

	for my $index ($match .. $blen - 1) {
		my $ch = substr($$stash, $index, 1);
		$cb->{"list_${ch}_item_close"}->();
		$cb->{"list_${ch}_close"}->();
	}

	for my $index ($match .. $alen - 1) {
		my $ch = substr($sigil, $index, 1);
		$cb->{"list_${ch}_open"}->();
		$cb->{"list_${ch}_item_open"}->();
	}

	if ($match) {
		my $ch = substr($sigil, $match - 1, 1);
		$cb->{"list_${ch}_item_close"}->();
		$cb->{"list_${ch}_item_open"}->();
	}

	$$stash = $sigil;
}	

sub do_pre {
	my ($data, $pre, $cb) = @_;

	my $temp = substr($$data, pos($$data), 3);

	if ($$data =~ /\G +/cg) {
		if (!$$pre) {
			$cb->{pre_open}->();
			$$pre = 1;
		}
	} else {
		if ($$pre) {
			$cb->{pre_close}->();
			$$pre = 0;
		}
	}
}

sub do_link {
	my ($link, $suffix, $cb) = @_;
	my $appearance;

	if ($link =~ /^:/) {
		($appearance = $link) =~ s/://;
		return ($link, $appearance);
	}

	if ($link =~ /\|/) {
		($link, $appearance) = split /\|/, $link, 2;
	} else {
		$appearance = $link;
	}

	$appearance .= $suffix;
	$cb->{'link'}->($link, $appearance);
}

sub do_template {
	my ($template) = @_;
	my $params; my @params; my %params;
	my $link = 0;
	my $prev = 0;

	($template, $params) = split /\|/, $template, 2;

	while ($params && $params =~ /(\[\[|\]\]|<nowiki>|\|)/cgis) {
		my $token = $1;
		if ($token eq '[[') {
			$link ++;
		} elsif ($token eq ']]') {
			$link --;
		} elsif (lc $token eq '<nowiki>') {
			$params =~ m#</nowiki>#cgis;
		} else { # $token eq "|"
			if ($link == 0) {
				my $pos = pos($params);
				my $len = $pos - $prev;
				my $param = substr($params, $prev, $len - 1);
				$prev = $pos;
				if ($param =~ /=/) {
					my $name;
					($name, $param) = split /=/, $param, 2;
					$params{$name} = $param;
				}
				push @params, $param;
			}
		}
	}

	if ($params && $params =~ /\G(\S+)/) {
		push @params, $1;
	}

	print "Template: $template, params (";
	print join ',', map { "''$_''" } @params;
	print ")<br />";
}
	
sub parse_wiki {
	my ($data, $cb) = @_;

	my $list = "";
	my $pre = 0;

	while ($data !~ /\G\z/cg) {
		if ($data =~ /\G\n\n/cgs) {
			do_pre(\$data, \$pre, $cb);
			if ($data =~ /\G(?<=\n)([*#]+)/cg) {
				do_list($1, \$list, $cb);
			} else {
				do_list("", \$list, $cb);
			}
			$cb->{paragraph}->();
		} elsif ($data =~ /\G\n/cgs) {
			do_pre(\$data, \$pre, $cb);
			if ($data =~ /\G(?<=\n)([*#]+)/cg) {
				do_list($1, \$list, $cb);
			} else {
				do_list("", \$list, $cb);
			}
			$cb->{whitespace}->();
		} elsif ($data =~ /\G\s+/cg) {
			$cb->{whitespace}->();
		} elsif ($data =~ m#\G<nowiki>(.*?)</nowiki>#cgis) {
			$cb->{nowiki}->($1);
		} elsif ($data =~ m#\G<math>(.*?)</math>#cgis) {
			$cb->{math}->($1);
		} elsif ($data =~ /\G<!--(.*?)-->/cgs) {
			$cb->{comment}->($1);
		} elsif ($data =~ /\G(?<=\n)-----*/cg) {
			$cb->{divider}->();
		} elsif ($data =~ /\G\[\[/cg) {
			pos($data) -= 2;
			my $link = match_balanced(\$data, "[[", "]]");
			$link = substr($link, 2);
			substr($link, -2, 2, '');
			$data =~ /\G([[:alnum:]]+)/cg;
			my $suffix = defined($1)?$1:"";
			do_link($link, $suffix, $cb);
		} elsif ($data =~ /\G(?<!\{)\{\{[^{]/cg) {
			pos($data) -= 3;
			my $template = match_balanced(\$data, "{{", "}}");
			$template = substr($template, 2);
			substr($template, -2, 2, '');
			do_template($template);
		} elsif ($data =~ /\G''''/cg) {
			my $start = pos($data);
			$data =~ m#\G.*?''#cg;
			my $len = pos($data) - $start - 4;
			$cb->{em3_open}->();
			parse_wiki(substr($data, $start, $len), $cb);
			$cb->{em3_close}->();
		} elsif ($data =~ /\G'''/cg) {
			my $start = pos($data);
			$data =~ m#\G.*?'''#cg;
			my $len = pos($data) - $start - 3;
			$cb->{em2_open}->();
			parse_wiki(substr($data, $start, $len), $cb);
			$cb->{em2_close}->();
		} elsif ($data =~ /\G''/cg) {
			my $start = pos($data);
			$data =~ m#\G.*?''#cg;
			my $len = pos($data) - $start - 2;
			$cb->{em1_open}->();
			parse_wiki(substr($data, $start, $len), $cb);
			$cb->{em1_close}->();
		} elsif ($data =~ /\G====(.*?)====/cg) {
			$cb->{sec3}->($1);
		} elsif ($data =~ /\G===(.*?)===/cg) {
			$cb->{sec2}->($1);
		} elsif ($data =~ /\G==(.*?)==/cg) {
			$cb->{sec1}->($1);
		} else {
			$data =~ /\G(.[[:alnum:] <>\/]*)/cgi;
			$cb->{text}->($1);
		}
	}
}

die "WTF" unless @ARGV == 1;
open my $in, '<', $ARGV[0] or die $!;
my $data = do { local $/; <$in>; };
close $in;

print "<html><body>";
parse_wiki($data, {
		'text' => sub { print $_[0] },
		'nowiki' => sub { print $_[0] },
		'paragraph' => sub { print "<p />\n\n" },
		'list' => sub { print "<br />List: <code>$_[0]</code>\n"; },
		'link' => sub { print "<code>$_[0]</code>" },
		'template' => sub { print "<code>$_[0]</code>" },
		'em1_open' => sub { print "<i>"; },
		'em1_close' => sub { print "</i>"; },
		'em2_open' => sub { print "<b>"; },
		'em2_close' => sub { print "</b>"; },
		'em3_open' => sub { print "<b><i>"; },
		'em3_close' => sub { print "</i></b>"; },
		'sec1' => sub { print "<h1>$_[0]</h1>\n" },
		'sec2' => sub { print "<h2>$_[0]</h2>\n" },
		'sec3' => sub { print "<h3>$_[0]</h3>\n" },
#		'comment' => sub { print "<!-- $_[0] -->" },
		'comment' => sub { 1 },
		'divider' => sub { print "<hr>\n" },
		'whitespace' => sub { print " "; },
		'list_#_open' => sub { print "<ol>" },
		'list_#_item_open' => sub { print "<li>" },
		'list_#_item_close' => sub { print "</li>" },
		'list_#_close' => sub { print "</ol>" },
		'list_*_open' => sub { print "<ul>" },
		'list_*_item_open' => sub { print "<li>" },
		'list_*_item_close' => sub { print "</li>" },
		'list_*_close' => sub { print "</ul>" },
		'pre_open' => sub { print "<pre>" },
		'pre_close' => sub { print "</pre>" },
		'link' => sub { print qq(<a href="/$_[0]">$_[1]</a>); },
		});

print "</body></html>";


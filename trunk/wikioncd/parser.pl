#!/usr/bin/perl
###
# Wikitext Parser
# Part of WikiOnCD
# Copyright (C) 2005, Andrew Rodland <arodland@entermail.net>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.


use strict;
use warnings;

sub trim {
	my $data = shift;

	$data =~ s/^[ \n\t\r\0\x0b]*//g;
	$data =~ s/[ \n\t\r\0\x0b]*$//g;

	return $data;
}

sub deref_var {
	my ($magic, $var) = @_;

	$var = lc trim($var);

	my $data = $magic->{$var};
	if (!defined($data)) {
		return "Unknown variable $var.";
	} elsif (ref($data) eq 'CODE') {
		return $data->();
	} else {
		return $data;
	}
}

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

	if ($link =~ /\|/) {
		($link, $appearance) = split /\|/, $link, 2;
	} else {
		$appearance = $link;
	}

	$appearance .= $suffix;
	$cb->{'link'}->($link, $appearance);
}

sub do_template {
	my ($template, $cb, $magic, $vars, $st) = @_;
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
				my $param = trim(substr($params, $prev, $len - 1));
				$prev = $pos;
				if ($param =~ /=/) {
					my $name;
					($name, $param) = split /=/, $param, 2;
					$name = trim($name);
					$params{$name} = $param;
				}
				push @params, $param;
			}
		}
	}

	if ($params && $params =~ /\G(\S+)/) {
		push @params, $1;
	}

	$template =~ s/(?<!{){{([^{}]+)}}/deref_var($magic, $1)/eg;

	print "Template: $template, params (";
	print join ',', map { "''$_''" } @params;
	print ")<br />";
}

{
	my %closemap =
		(em1 => 'em1_close',
		 em2 => 'em2_close',
		 em3 => 'em3_close',
		 caption => 'table_caption_close',
		 row => 'table_row_close',
		 col => 'table_cell_close',
		 header => 'table_header_close',
		 table => 'table_close',
		 dl => 'def_list_close',
		 dt => 'def_title_close',
		 dd => 'def_data_close',
		);

	sub close_tags {
		my $st = shift;
		my $cb = shift;

		for my $thing (@_) {
			if ($st->{$thing}) {
				$cb->{$closemap{$thing}}->();
				$st->{$thing} --;
			}
		}
	}

}

sub parse_wiki {
	my ($data, $cb, $magic, $vars, $st) = @_;


	$st->{list} = "";

	while ($data !~ /\G\z/cg) {
		if ($data =~ /\G\n\n/cgs) {
			do_pre(\$data, \($st->{pre}), $cb);
			if ($data =~ /\G(?<=\n)([*#]+)/cg) {
				do_list($1, \($st->{list}), $cb);
			} else {
				do_list("", \($st->{list}), $cb);
			}
			$cb->{paragraph}->();
			close_tags($st, $cb, qw(em1 em2 em3 caption));
		} elsif ($data =~ /\G\n/cgs) {
			do_pre(\$data, \($st->{pre}), $cb);
			if ($data =~ /\G(?<=\n)([*#]+)/cg) {
				do_list($1, \($st->{list}), $cb);
			} else {
				do_list("", \($st->{list}), $cb);
			}
			if ($data !~ /\G(?<=\n)[;:]/cg) {
				close_tags($st, $cb, qw(dd dt dl));
			}
			$cb->{whitespace}->();
			close_tags($st, $cb, qw(em1 em2 em3 caption));
		} elsif ($data =~ /\G\s+/cg) {
			$cb->{whitespace}->();
		} elsif ($data =~ m#\G<nowiki>(.*?)</nowiki>#cgis) {
			$cb->{nowiki}->($1);
		} elsif ($data =~ m#\G<math>(.*?)</math>#cgis) {
			$cb->{math}->($1);
		} elsif ($data =~ /\G<!--(.*?)-->/cgs) {
			$cb->{comment}->($1);
		} elsif ($data =~ /\G(?:(?<=\n)|\A);/cg) {
			close_tags($st, $cb, qw(dd dt));
			$cb->{def_list_open}->();
			$cb->{def_title_open}->();
			@{$st}{qw(dl dt)} = qw(1 1);
		} elsif ($data =~ /\G(?:(?<=\n)|\A):/cg) {
			if ($st->{dl}) {
				close_tags($st, $cb, 'dt');
				$cb->{def_data_open}->();
				$st->{dd} = 1;
			} else {
				$cb->{indent}->();
			}
		} elsif ($st->{dd} && $data =~ /\G(?<=\s):/cg) {
			close_tags($st, $cb, 'dt');
			$cb->{def_data_open}->();
			$st->{dd} = 1;
		} elsif ($data =~ /\G(?:(?<=\n)|\A)-----*/cg) {
			$cb->{divider}->();
		} elsif ($data =~ /\G(?:(?<=\n)|\A){\|(.*)/cg) {
			$cb->{table_open}->($1);
			$st->{row} = 0;
			$st->{table} ++;
		} elsif ($data =~ /\G(?:(?<=\n)|\A)\|\}/cg) {
			close_tags($st, $cb, qw(col header row table));
		} elsif ($data =~ /\G(?:(?<=\n)|\A)\|-(.*)/cg) {
			close_tags($st, $cb, qw(col header row));
			$cb->{table_row_open}->($1);
			$st->{row} = 1;
		} elsif ($data =~ /\G(?:(?<=\n)|\A)\|\+/cg) {
			$cb->{table_caption_open}->();
			$st->{caption} = 1;
		} elsif ($data =~ /\G((?:(?<=\n)|\A)\||\|\|)/cg) {
			my $start = pos($data);
			my ($link, $bar) = (undef, undef);
			my $params;

			if ($data =~ /\G.*?\[\[/cg) {
				$link = pos($data);
			}
			pos($data) = $start;
			if ($data =~ /\G.*?(?<!\|)\|(?!\|)/cg) {
				$bar = pos($data);
			}

			if (defined($bar) && (!defined($link) || $bar < $link)) {
				$params = substr($data, $start, ($bar - $start - 1));
				pos($data) = $bar;
			} else {
				$params = "";
				pos($data) = $start;
			}

			close_tags($st, $cb, qw(col header));

			$st->{row} || $cb->{table_row_open}->("");
			$cb->{table_cell_open}->($params);
			@{$st}{qw(row col)} = qw(1 1);
		} elsif ($data =~ /\G((?:(?<=\n)|\A)!|!!)/cg) {
			my $start = pos($data);
			my ($link, $bar) = (undef, undef);
			my $params;

			if ($data =~ /\G.*?\[\[/cg) {
				$link = pos($data);
			}
			pos($data) = $start;
			if ($data =~ /\G.*?\|(?!\|)/cg) {
				$bar = pos($data);
			}

			if (defined($bar) && (!defined($link) || $bar < $link)) {
				$params = substr($data, $start, ($bar - $start - 1));
				pos($data) = $bar;
			} else {
				$params = "";
				pos($data) = $start;
			}

			close_tags($st, $cb, qw(col header));
			$st->{row} || $cb->{table_row_open}->("");
			$cb->{table_header_open}->($params);
			@{$st}{qw(row header)} = qw(1 1);
		} elsif ($data =~ /\G\[\[/cg) {
			pos($data) -= 2;
			my $link = match_balanced(\$data, "[[", "]]");
			$link = substr($link, 2);
			substr($link, -2, 2, '');
			$data =~ /\G([[:alnum:]]+)/cg;
			my $suffix = defined($1)?$1:"";
			do_link($link, $suffix, $cb);
		} elsif ($data =~ /\G\{\{\{/cg) {
			pos($data) -= 3;
			my $varname = match_balanced(\$data, "{{{", "}}}");
			$varname = substr($varname, 3);
			substr($varname, -3, 3, '');
		
			my $value = $vars->{lc trim $varname};
			if (!defined($value)) {
				$cb->{text}->("Reference to undefined var $varname.");
			} else {
				parse_wiki($value, $cb, $magic, $vars, $st);
			}
#		} elsif ($data =~ /\G(?<!\{)\{\{[^{]/cg) {
#			pos($data) -= 3;
		} elsif ($data =~ /\G\{\{/cg) {
			pos($data) -= 2;
			my $template = match_balanced(\$data, "{{", "}}");
			$template = substr($template, 2);
			substr($template, -2, 2, '');
			do_template($template, $cb, $magic, $vars, $st);
		} elsif ($data =~ /\G''''/cg) {
			if ($st->{em3}) {
				close_tags($st, $cb, 'em3');
			} else {
				$cb->{em3_open}->();
				$st->{em3} = 1;
			}
		} elsif ($data =~ /\G'''/cg) {
			if ($st->{em2}) {
				close_tags($st, $cb, 'em2');
			} else {
				$cb->{em2_open}->();
				$st->{em2} = 1;
			}
		} elsif ($data =~ /\G''/cg) {
			if ($st->{em1}) {
				close_tags($st, $cb, 'em1');
			} else {
				$cb->{em1_open}->();
				$st->{em1} = 1;
			}
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
				'link' => sub { print qq(<a href="/wiki/$_[0]">$_[1]</a>); },
				'table_open' => sub { print qq(<table $_[0]>) },
				'table_close' => sub { print "</table>" },
				'table_row_open' => sub { print qq(<tr $_[0]>) },
				'table_row_close' => sub { print "</tr>" },
				'table_cell_open' => sub { print qq(<td $_[0]>) },
				'table_cell_close' => sub { print "</td>" },
				'table_header_open' => sub { print qq(<th $_[0]>) },
				'table_header_close' => sub { print "</th>" },
				'table_caption_open' => sub { print "<caption>" },
				'table_caption_close' => sub { print "</caption>" },
				'def_list_open' => sub { print "<dl>" },
				'def_list_close' => sub { print "</dl>" },
				'def_title_open' => sub { print "<dt>" },
				'def_title_close' => sub { print "</dt>" },
				'def_data_open' => sub { print "<dd>" },
				'def_data_close' => sub { print "</dd>" },
				'indent' => sub { 1 },
		});

		print "</body></html>";


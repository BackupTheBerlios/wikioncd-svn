#!/usr/bin/perl
#

use strict;
use warnings;

sub match_balanced {
	my ($data, $open, $close) = @_;

	my $count = 0;

	my $start = pos($$data);

	while ($$data =~ m#\G.*?(\Q$open\E|\Q$close\E|(?i:<nowiki>))#cg) {
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

sub parse_wiki {
	my ($data, $cb) = @_;

	my $list = "";

	while ($data !~ /\G\z/cg) {
		if ($data =~ /\G\n\n/cgs) {
			if ($data =~ /\G(?<=\n)([*#]+)/cg) {
				do_list($1, \$list, $cb);
			} else {
				do_list("", \$list, $cb);
			}
			$cb->{paragraph}->();
		} elsif ($data =~ /\G\n/cgs) {
			if ($data =~ /\G(?<=\n)([*#]+)/cg) {
				do_list($1, \$list, $cb);
			} else {
				do_list("", \$list, $cb);
			}
			$cb->{whitespace}->();
		} elsif ($data =~ /\G\s/cg) {
			$cb->{whitespace}->();
		} elsif ($data =~ m#\G<nowiki>(.*?)</nowiki>#cgi) {
			$cb->{nowiki}->($1);
		} elsif ($data =~ m#\G<math>(.*?)</math>#cgi) {
			$cb->{math}->($1);
		} elsif ($data =~ /\G<!--(.*?)-->/cg) {
			$cb->{comment}->($1);
		} elsif ($data =~ /\G(?<=\n)-----*/cg) {
			$cb->{divider}->();
		} elsif ($data =~ /\G\[\[/cg) {
			pos($data) -= 2;
			my $link = match_balanced(\$data, "[[", "]]");
			$cb->{'link'}->($link);
		} elsif ($data =~ /\G\{\{/cg) {
			pos($data) -= 2;
			my $template = match_balanced(\$data, "{{", "}}");
			$cb->{template}->($template);
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
		'link' => sub { print "<code>$_[0]</code>\n" },
		'template' => sub { print "<code>$_[0]</code>\n" },
		'em1_open' => sub { print "<i>"; },
		'em1_close' => sub { print "</i>"; },
		'em2_open' => sub { print "<b>"; },
		'em2_close' => sub { print "</b>"; },
		'em3_open' => sub { print "<b><i>"; },
		'em3_close' => sub { print "</i></b>"; },
		'sec1' => sub { print "<h1>$_[0]</h1>\n" },
		'sec2' => sub { print "<h2>$_[0]</h2>\n" },
		'sec3' => sub { print "<h3>$_[0]</h3>\n" },
		'comment' => sub { print "<!-- $_[0] -->" },
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
		});

print "</body></html>";


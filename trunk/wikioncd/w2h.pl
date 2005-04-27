###
# Wiki2HTML Code
# Part of WikiOnCD
# Copyright (C) 2005, Andrew Rodland <arodland@entermail.net>
# Based on Wiki2Static 0.61
###############################
# 
# Copyright (C) 2004, Alfio Puglisi <puglisi@arcetri.astro.it>,
#                     Erik Zachte (epzachte at chello.nl),
#                     Markus Baumeister (markus at spampit.retsiemuab.de)
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

$wiki_language = "en";
$include_media = 0;
$include_toc = 3;

%Wikiarray = (
"numberofarticles" => "500,000",
"currentyear" => "2005",
"currentmonthname" => "April",
"currentday" => "21",
"stub" => "",
"writer-stub" => "",
);

$MainPageName = "Main Page";
$MainPagePath = "/" . GetFileName($MainPageName);

@list_seps = ( "\#", "\:", "\*", " ");

$list_open{"\*"} = "<ul><li>";
$list_continue{"\*"} = "</li><li>";
$list_close{"\*"} = "</li></ul>";

$list_open{"\:"} = "<dl><dd>";
$list_continue{"\:"} = "</dd><dd>";
$list_close{"\:"} = "</dd></dl>";

$list_open{"\#"} = "<ol><li>";
$list_continue{"\#"} = "</li><li>";
$list_close{"\#"} = "</li></ol>";

$list_open{" "} = "<pre>";
$list_continue{" "} = "";
$list_close{" "} = "</pre>";

sub WikiToHTML {
	my ($title, $text, $namespace, $do_toc, $do_html, $redir_from) = @_;
	my ($page, $title_spaces, $heading, $sep, $protocol);
	my ($line, $n, $item, $html_lists, $diff, $opened, $gone_on, $splitted, $want_toc, @TOC);
	my ($tex_start, $tex_end, $math);
	my ($variable, $original_var, $params, $p, $counter, @params, $replace, $recursive_replace, $parname, $parvalue);
	my ($start_nowiki, $end_nowiki, @nowiki, $fragment);	
	
#	return $text if ($level > 5)

	# Remove <nowiki> segments, saving them
	
	@nowiki = ();
	$start_nowiki = "<nowiki>";
	$end_nowiki = "</nowiki>";
	
	while ($text =~ m/${start_nowiki}.*?${end_nowiki}/is)
		{
		$text =~ s/${start_nowiki}(.*?)${end_nowiki}/$nowiki_replacement/;
		push @nowiki, $1;
		}

#	$text = RemoveHTMLcomments($text);	
	# Dig into the articles and convert all [[links]] into HREFs, storing their titles in the process...

# Whee. Not necessary! We can just do it once, after.
#	while ($text =~ /\[\[/) {
#		my $count = 0;
#		while ($text =~ /(\[\[|\]\])/gc) {
#			$count += { "[[" => 1, "]]" => -1 }->{$1};
#			last unless $count > 0;
#		}
#		$text =~ s/\[\[(.*)\]\]\G/ProcessLink($1)/e;
#	}

	# Convert TeX math notation

	$tex_start = "<math>";
	$tex_end = "</math>";
	
#	while( $text =~ m|${tex_start}(.*?)${tex_end}|so)
#		{
#		$math = $1;
#		$math =~ s|\\r\\n||g;
#		$replacement = &ConvertTex($math);
#		$text =~ s|${tex_start}.*?${tex_end}|$replacement|s;
#		}

	# {{Templates}}
	# To be done after TeX conversion, otherwise we pick up {{}}s from it!
	# But before everything else, because there's wiki markup inside
	
	# This regexp avoids matching nested variables, so they will be interpreted in the right order
	
	$Wikiarray{pagename} = $title;
	$templates_max = 100;
	$templates_num = 0;
	while( $text =~ m#\{\{([^\{]*?)\}\}#mo)	
		{
		$variable = $1;
		$replace = "";

		$original_var = $variable;
		
		# remove "|" and remember parameters
		if (scalar($variable =~ s/(.*?)\|(.*)$/$1/s) >0)
			{
			$params = $2;
			}
		else
			{
			$params = "";
			}

		## Remove newlines from parameters			
		$params =~ s/\\r\\n//g;
		$params =~ s/\\n//g;

		my $count = 0;

		@params = ();

		while ($params =~ /(\[\[|\]\]|\|)/gc) {
			$count += { "[[" => 1, "]]" => -1, "|" => 0 }->{$1};

			if ($1 eq "|" && $count == 0) {
				my $param = substr $params, 0, pos($params) - 1, '';
				push @params, $param;

				substr($params, 0, 1) = '';
				pos $params = 0;
			}
		}
		
		push @params, $params if $params =~ /\S/;	

		## Put underscore instead of spaces for filename
#		$variable =~ s/\s/_/g;

#		print STDERR "Variable is: $variable \n";		
#		print STDERR "Params are: ".join("**",@params)."\n";

		# we don't handle localurl
		if ($variable =~ m/localurl/i)
			{
			$replace = "";
			}
		else
			{
			$replace = $Wikiarray{lc $variable};
	
			if ($replace eq "")
				{
#				print LOGFILE "Wikiarray for $variable was empty \n";
				## match msg:, Template;, etc.	
				$msg = $variable;
				if ($variable =~ m/(.*?)\:(.*?)$/i)
					{
					$ns = $1;
					$msg = $2;
					} else {
						$ns = "template";
					}
#				print LOGFILE "Now looking at $msg \n";
				$replace = GetMsgValue($msg, $ns);
				
				$templates_num = $templates_num+1;
				$replace = "" if ($templates_num > $templates_max);
				}
			}	
		
#		print LOGFILE "For message $original_var got text $replace \n";

		## Parameter substitution is commented out due to problems with UTF8 languages (see bg)
#		$replace =~ s/\{\{.*?\}\}//g;
		
		# Do parameter substitution, if necessary
		
		if ($params ne "")
			{
			$counter =0;
			foreach $p (@params)
				{
				$counter = $counter+1;
				if ($p =~ m/\=/s)
					{
					($parname, $parvalue) = split("=", $p, 2);
					}
				else
					{
					$parname = $counter;
					$parvalue = $p;
					}
					
				$parname =~ s/^\s+//;
				$parname =~ s/\s+$//;
				$parvalue =~ s/^\s+//;
				$parvalue =~ s/\s+$//;
				$parname =~ s/\?/\\\?/g;
				
				$parname =~ s/\s/_/g;

#				$replace =~ s/\Q\{\{\{${parname}\}\}\}/$parvalue/isg;
				$replace =~ s/\{\{\{\Q${parname}\E\}\}\}/$parvalue/isg;
#				$replace =~ s/\{\{\{$counter\}\}\}/$parvalue/sg;

#				$replace =~ s/({{[^}]+){{\Q${parname}\E}}/$1$parvalue/isg;
				}
			}
		
		# Avoid recursive templates
#		$replace =~ s/\{\{//g;
#		$replace =~ s/\}\}//g;

#		print LOGFILE "Final text: $replace \n";
	
		## Recursive include of parameters
#		$recursive_replace = WikiToHTML( $level+1, "", $replace, 0, 0);
		
#		print LOGFILE "Text after recursion: $recursive_replace \n";
		
		$text =~ s#\{\{[^\{]*?\}\}#$replace#m;

#		print LOGFILE "Text is now:\n$text \n";
		}

	# Now redo links conversion for the links inserted by {{}} parameters

	my $desperation = 0;
	
	while ($text =~ /\[\[/) {
#		print STDERR $text, "\n";
		my $count = 0;
		while ($text =~ /(\[\[|\]\])/gc) {
			$count += { "[[" => 1, "]]" => -1 }->{$1};
			last unless $count > 0;
		}
		$desperation ++;
		if ($desperation == 1000) {
			print STDERR "BUG replacing links in $text\n";
		}

		$text =~ s/\[\[(.*)\]\]\G/ProcessLink($1)/e;
	}

	## Newlines
	
	$nextline = "\n";
	
#	$text =~ s|\r\n\r\n|\n<p>\n|go;			# Double newline = paragraph
	$text =~ s|\r\n|\n|go;						# Single newline
	$text =~ s|\n\n|\n<p>\n|go;

	# Wiki tables	
	
	while ( scalar($text =~ m/({\|.*?\|})/so) )
		{	
		my $table, $table_params, $search, $subst;
		
		# Get table markup
		$table =$1;

		print "Table found in $title \n" if $debug>0;
		
		# Find table paramters. Add a <tr> (generates a double <tr><tr> sometimes)
		$subst = "<table ";
		$table =~  s/\{\|(.*)/${subst} $1 \><tr>/m;

		## Close table
		$subst = "</td></tr></table>";
		$table =~ s/\|\}/${subst}/g;
		
		## handle "||" putting back to newline+"|"
		$subst = "\n|";
		$table =~ s/\|\|/$subst/mg;

		## repeat for  "!!"
		$subst = "\n!";
		$table =~ s/\!\!/$subst/mg;

		## Convert <tr>
		$subst = "</td></tr><tr";
		$table =~ s/\|\-(.*)/$subst $1 \>/mg;
		
		## Except for the first..
		$table =~ s|(\<table.*?\>\s*)\<\/td\>\<\/tr\>|$1|s;

		## remove double <tr><tr> sometimes found after <table>
		$table =~ s/\<tr\>\s*(\<tr)/$1/g;
		
		## Now the caption
		$subst = "<caption ";
		$subst2 = "</caption>";
		$table =~ s/\|\+(.*?)\|(.*)/${subst} $1\>$2${subst2}/m;
		$table =~ s/\|\+(.*)/${subst}\>$1${subst2}/m;
		
		## Now all the TDs
		$subst = "</td><td ";
		$table =~ s/^\|(.*?)\|(.*)/${subst} $1\>$2/mg;
		$table =~ s/^\|(.*)/${subst}\>$1/mg;

		## Except the first on each row...
		$table =~ s|(\<tr[^\>]*?\>\s*)\<\/td\>|$1|sg;

		## Repeat for THs
		$subst = "</th><th ";
		$table =~ s/^\!(.*?)\|(.*)/${subst} $1\>$2/mg;
		$table =~ s/^\!(.*)/${subst}\>$1/mg;

		## Except the first on each row...
		$table =~ s|(\<tr[^\>]*?\>\s*)\<\/th\>|$1|sg;

		## Now put the table back inside the text

		$table = &RemoveHTMLentities($table);
		
		$text =~ s/\{\|.*?\|\}/$table/s;
		}
		
	 
	# Random wiki markup

#	$nextline = "\r\n";
	
#	$text =~ s|\\r\\n\\r\\n|<p>$nextline|go;			# Double newline = paragraph
#	$text =~ s|\\r\\n|$nextline|go;						# Single newline
#	$text =~ s|\\n\\n|$nextline|go;
#	$text =~ s|^\s(.*?)$|<pre>$1</pre>|sg;				# Initial space (with text inside) = monospaced format (now handled as list)
	$text =~ s|^-----*|<hr>|mgo;						# Four+ dashes = horizontal line
	$text =~ s|'''(.*?)'''|<strong>$1</strong>|g;		# Three quotes = strong
	$text =~ s|''(.*?)''|<em>$1</em>|g;				# Two quotes = emphatize
#	$text =~ s|\\'\\'\\'(.*?)\\'\\'\\'|<strong>$1</strong>|g;		# Three quotes = strong
	


	# handle lists and TOC by splitting into individual lines
	
	# Use an external flag to split only one time, if needed
	$splitted=0;
	$want_toc=0;
	@lines=();
	@TOC=();
		
	# Check if we have any kind of list
	if ( $text =~ m/^([\#\:\* ]+)/mgo)
		{
		# Split the text into individual lines
		if ($splitted == 0)
			{
			@lines = split(/\n/, $text);
			$splitted=1;
			}

		# Work on a line-by-line basis

		%previous=("#",0,":",0,"*",0," ",0);
		foreach $line (@lines)
			{
			# Count the leading list markers on each line
			#(including non-list lines, they could be the closing ones!)
			if ($line =~ s/^([\#\:\*]+|\s)//m)
				{
				$current = $1;
				}	
			else
				{
				$current = "";
				}

			%this_one=("#"=>0, ":"=>0, "*"=>0, " "=>0);
			if ($current ne "")
				{
				$allofthem=0;
				foreach $n (0 .. length($current)-1)
					{
					$item = substr( $current, $n, 1);
					$this_one{$item} ++;
					$allofthem++;
					}
				$this_one{" "} = 1 if $this_one{" "} > 1;		# Leading-space monospaced format "list" has only one level
				$this_one{" "} = 0 if $allofthem>1;				# And must also be alone
				}

			# Now we can compare with the previous line and see
			# what we must open, close or carry on.
			$html_lists = "";
			$opened=0;
			foreach $item (@list_seps)
				{
				$diff = $this_one{$item} - $previous{$item};
				if ($diff >0)
					{
					$html_lists .= $list_open{$item} x $diff;
					$opened++;
					}
				if ($diff <0)
					{
					$html_lists .= $list_close{$item} x (-$diff);
					}			
				}

			# When carrying on lists, a bit of care must be employed
			$gone_on=0;
			foreach $item (@list_seps)
				{
				$diff = $this_one{$item} - $previous{$item};
			
				if (($diff<=0) && ($this_one{$item} >0) && ($opened==0) && ($gone_on==0))
					{
					$html_lists .= $list_continue{$item};
					$gone_on++;
					}
				}		

			# Replace leading list markers with HTML tags
			if ($html_lists ne "")
				{
				$line = $html_lists.$line;
				}

			# Save this line status to compare it with the next one.
			%previous = %this_one;
			}
		}

	# See if we need to close any remaining list
	$closure="";
	foreach $item (@list_seps)
		{
		if ($this_one{$item} >0)
			{
			$closure .= $list_close{$item} x $this_one{$item};
			}
		}

	# Check for the TOC
	if ((!($text =~ m/__NOTOC__/mio)) && ( $text =~ m/==+/mg) && ($include_toc>0) && ($title ne $MainPageRecord))
		{
		if ($splitted == 0)
			{
			# Split the text into individual lines
			@lines = split(/\n/, $text);
			$splitted=1;
			}

		foreach $line (@lines)
			{
			if ($line =~ m/(==+)\s*(.*?)\s*==+/m)
				{
				$level = length($1);
				$name = &HTMLLinksToText($2);

				push @TOC, $level.":".$name;
				$want_toc++;
				}
			}
		}
		
	# Rebuild the page if needed

	if ($splitted)
		{
		$text = join("\n", @lines);
		}

	## Insert the list closure (if any) at the end of the article
	$text .= $closure;


	# If a TOC is wanted, place it
	
	if (($want_toc >= $include_toc) && ($do_toc))
		{
		$first_level = substr($TOC[0], 0, 1);
		$cur_level = $first_level;
		
		$TOC_html = <<END_STARTTOC;
		
<p><table border="0" id="toc"><tr><td align="center">
<b>Table of contents</b> <script type='text/javascript'>showTocToggle("show","hide")</script></td></tr><tr id='tocinside'><td align="left">
<div style="margin-left:2em;">

END_STARTTOC

		@counter=();
		foreach $TOCitem (@TOC)
			{
			# Get the TOC item properties
			$level = substr($TOCitem, 0, 1) - $first_level;
			$name = substr($TOCitem, 2);

			# Open and close DIVs as necessary			
			$level = 0 if $level<0;
			$diff = $level - $cur_level;
			if ($diff >0)
				{
				$TOC_html .="<div style=\"margin-left:2em;\">\n" x ($diff);
				}
			if ($diff <0)
				{
				$TOC_html .= "</div>\n" x (-$diff);
				}

			$cur_level = $level;
			
			# Count items and subitems, build an index number, and save the html string
			$counter[$level]++;
			if ($level == 0)
				{
				$number = $counter[0];
				}
			else
				{
				$number = join(".", @counter[0..$level]);
				}
			
			$TOC_html .= "$number <A CLASS=\"internal\" HREF=\"#${name}\">$name</A><BR>\n";
			}
			
		# End TOC
		$TOC_html .= "</td></tr></table><P>\n";
		
		# Place the TOC just before the first heading
		$text =~ s/(==+)/${TOC_html}$1/;
		}

	# Remove __NOTOC__ command, if present
	
	$text =~ s/__NOTOC__//mg;	
	
	# Remove other random commands
	
	$text =~ s/__NOEDITSECTION__//mg;
	
	# Headings (in reverse order, otherwise it does not work!)
	# Convert to <H>, and make anchors too.
	#
	# This substitution must be made AFTER the TOC has been generated and placed in the page
	
	for ( $i=6; $i >= 2; $i--)
		{
		$heading = "=" x $i;
		while ( $text =~ m|${heading}\s*(.*?)\s*${heading}|m )
			{
			$header = $1;
			$anchor_name = &HTMLLinksToText($header);
			$text =~ s|${heading}\s*.*?\s*${heading}|<A NAME=\"${anchor_name}\"><H${i}>${header}</H${i}>|m;
			}
		}
		
	# External links and [External links]
	# Do not change the order of substitutions
	
	$sep = "\<\,\;\.\:"; 		## List of separators that can happen at the end of an URL without being included in it.
	$external_reference_counter=1;
	foreach $protocol ( qw(http https ftp gopher news mailto))
		{
		while ( $text =~ s|\[(${protocol}\:\S+)\s*\]|<A HREF=\"$1\" class="external">\[${external_reference_counter}\]</A>|mg)
			{
			$external_reference_counter++;
			}
		$text =~ s|\[(${protocol}\:\S+)\s+(.*?)\]|<A HREF=\"$1\" class="external">$2</A>|mg;
		$text =~ s|([^\"])(${protocol}\:\S+)([${sep}]*)\b|$1<A HREF=\"$2\" class="external">$2</A>$3|mg;
		}

	# unicode -> html character codes &#nnnn;
	if ($wiki_language ne "en")
		{
		$entry =~ s/([\x80-\xFF]+)/&UnicodeToHtml($1)/ge ;
		}

	# Put back <nowiki> segments
	
	# Possible change:
# 	$text =~ s|${nowiki_replacement}|shift(@nowiki)|es;
	
	while ($text =~ m/$nowiki_replacement/)
		{
		$fragment = shift @nowiki;
		$text =~ s/${nowiki_replacement}/$fragment/;
		}

	if ($do_html)
		{
		$title_spaces = $title;
		$title_spaces =~ tr/_/ /;
		if ($redir_from) {
			$redir_from = qq(&nbsp;<small>(redirected from <b>$redir_from</b>)</small>);
		}
	

		$article_link = "http://${wiki_language}.wikipedia.org/wiki/${title}";
		if ($edit_article_link>0)
			{
			$article_link = "http://${wiki_language}.wikipedia.org/w/wiki.phtml?title=${title}&amp;action=edit";
			}

		$alphabetical_index = "";
#		$alphabetical_index = " | <a href=\"../../abc.html\">Alphabetical index</a>" if $wiki_language eq "en";

$page = <<ENDHTMLPAGE;	
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">
<html lang="en"><head><title>$title_spaces</title><meta http-equiv="Content-type" content="text/html; charset=${WikiCharset}">
<link rel="stylesheet" href="../../wikistatic.css"></head>
<body bgcolor='#FFFFFF'>
<div id=topbar><table width='98%' border=0><tr><td><a href="${MainPagePath}" title="${MainPageName}">${MainPageName}</a> | <b><a href="${article_link}" title="${title_spaces}">See live article</a></b>${alphabetical_index}</td>
<td align=right nowrap><form name=search class=inline method=get action="/search/"><input name=q size=19><input type=submit value=Search></form></td></tr></table></div>
<div id=article><h1>$title_spaces$redir_from</h1>$text</div><br><div id=footer><table border=0><tr><td>
<small>This article is from <a href="http://www.wikipedia.org/">Wikipedia</a>. All text is available under the terms of the <a href="../../g/gn/gnu_free_documentation_license.html">GNU Free Documentation License</a>.</small></td></tr></table></div></body></html>
ENDHTMLPAGE


		}		# Fine di if ($do_html)
	else
		{
		$page = $text;
		}
	
	$page;
}

sub ProcessLink
{
	my($original_link) = @_;
	my($linkname, $linkappereance, $linkhref, $sep, $namespace);
	my($medianame, $realmediapath, $diskmediapath, $href, $is_image, $mediafile, $fileprefix);


	$sep = ".,;:!?\"\$";
	
	$colon = ($original_link =~ m/:/);
		
	$original_link =~ s/[${sep}]+$//g;		# remove separators at the end

	$original_link =~ s/(\&.+)$/$1\;/g;		# put back ";" if part of an HTML entity

	$linkname = $original_link;
	$linkappereance = $original_link;
	

	# Watch out for pipes (they change link appereance, and would also break regexps if left in the link)
	if ($linkname =~ m/^\s*(.*?)\|(.*)/o)
		{
		$linkname = $1;
		$linkappereance = $2;
		
			
		# If empty, use the first part and remove the parenthesis, if present
		if ($2 eq "")
			{
			$linkappereance = $linkname;
			$linkappereance =~ s/\(.*?\)//o;
			}
		}
			
	$linkhref = "";

	# Deal with image: or media: links

	if (($linkname =~ m/^media:/oi) || ($linkname =~ m/^image:/oi))

		{
		if ($debug >1)
			{
			print LOGFILE "HERE IS A MEDIA FILE: $linkname\n";
			print LOGFILE "." x 4000;
			print LOGFILE "\n";
			}
	
		if ($include_media == 0)
			{
			return ("", "");
			}
		else
			{
			# Get the name without spaces and its MD5 hash
			$linkname =~ m/.*:(.*?)$/;
			$medianame = $1;
			$medianame =~ s/^\s+//;
			$medianame =~ s/\s+$//;
			
			($realmediapath, $fileprefix) = &GetMediaPath($medianame);

			# The $realmediapath is the online path, which must be checked for special characters to be encoded
			$realmediapath =~ s|\?|\%3F|g;
			
			# Remove extension from name and get a good filename
			$medianame =~ s|(.*)(\..*?)$|$1|o;
			$ext = $2;

			## Watch out for files with no extension - the previous $1 is used
			$ext = "" if $ext eq $medianame;
			$diskmediapath = $fileprefix . &GetUniqueMedia($medianame) . (lc $ext);

			# Mark the image as present (don't delete it later)
			$existing_images{$diskmediapath} = 0 if ($keep_old_versions ==0);
#			print LOGFILE "Marking $diskmediapath to avoid deletion (array value is ".$existing_images{$diskmediapath}.")\n";

			
			 if ($include_media == 1)
				{
				## Link media to the online site
				$linkhref = $online_media_prefix.$realmediapath;
				@options =  split(/\|/, $original_link);
		
				# Get last field (display name)
				shift @options;
				$linkappereance = pop @options;				
				
				print LOGFILE "Linking media $linkhref\n";
				$href = "<A HREF=\"${linkhref}\" title=\"${linkname}\" class=\"external\">$linkappereance</A>";
				}
			elsif ($include_media == 6)
				{
				## Link media to the online site
				$linkhref = $online_media_prefix.$realmediapath;
		
				print LOGFILE "Linking img $linkhref\n";
				$href = "<IMG SRC=\"${linkhref}\">";
				}

			else
				{
				$is_image=1;
				if ($linkname =~ m/^media/oi)
					{
					$is_image=0;
					}

				$mediafile = $media_prefix.$diskmediapath;
	
				if ($include_media > 2)
					{

					## Skip repeated failures if asked to
					if ( $retry_failures == 0)
						{
						if ($failed_images{$mediafile} >0)
							{
							print LOGFILE "Skipping media $mediafile (already failed)\n";
							return "";
							}
						}

					## Write out the conversion table for images
					## We use a DOS command

					$oldname = $fileprefix.$medianame.$ext;
					$newname = $diskmediapath;
					$oldname =~ s|\\|/|g;
					$newname =~ s|\\|/|g;

					print IMAGETABLE "mv \"$newname\" \"$oldname\"\n";

					
					## Check for the copying...
					if ($include_media==5)
						{
						# Re-generate name with full path
						$oldname = $media_prefix.$fileprefix.$medianame.$ext;
						$newname = $media_prefix.$diskmediapath;

						if (-e $oldname)
							{
							rename $oldname, $newname;
							print LOGFILE "Renamed $oldname to $newname\n";
							}
						}
					else
						{
						# Remove incorrectly-downloaded files
						if ((-e $mediafile) && (&FileSize($mediafile) == 0) && ($keep_zero_files == 0))
							{
							unlink $mediafile;
							print LOGFILE "DELETED media file $mediafile (0 bytes)\n";
							}

						## HERE we should check for a more recent version of the image
						if ( ($include_media == 3) && (-e $mediafile))
							{
							print LOGFILE "Media $realmediapath already in cache\n";
							}
						else
							{
							&MakeDirs($mediafile);
							print LOGFILE "Downloading media ${online_media_prefix}${realmediapath} ...";
							$content = &DownloadURL($online_media_prefix.$realmediapath);
							
							$fail=0;
							if (open( MEDIA, ">$mediafile"))
								{
								binmode(MEDIA);
								print MEDIA $content;
								close(MEDIA);
								print LOGFILE length($content)." bytes\n";
								$downloaded_media++;
								
								# Mark the image as downloaded
								$images_for_download{$medianame} = 0;	
								}
							else
								{
								$fail=1;
								print LOGFILE "CANNOT WRITE $mediafile: $!\n";
								}
								
							## Record failures
							if (($fail == 1) or (length($content)== 0))
								{
								$failed_images{$mediafile} = 1;
								}
								
							}
						}
					}

				## If it's an image, include it. Otherwise, leave as a link
				$total_media++;
				if ($is_image)
					{
#					$href = "<IMG SRC=\"../../../media/".$diskmediapath."\">";
#
#                   Awaiting testing:
#
					$href = &GetImageHTML($original_link, $diskmediapath, $linkappereance);
#

					$total_images++;
					}
				else
					{
					$href = "<A HREF=\"../../../media/".$diskmediapath."\">$linkappereance</A>";
					}
				}
			}	
		}
	else
		{	
		
		# Delink [[Wikipedia:]] links
		if ($linkname =~ m/^Wikipedia:/io)
			{
			return ($linkappereance, $linkappereance);
			}
			
		## Remove language links and anything in a different namespace
		elsif ($linkname =~ m/^(.*):/o)
			{
			$namespace = $1;
			$linkname =~ s/^.*://;
			$linkappereance =~ s/^.*://;

#		... or don't. That's rude.
			if ($namespace ne 't' && $namespace ne 'c' && $namespace ne 'wp') {
				return ($linkappereance, $linkappereance);
			}
#			return ("", "");
			}
		
		
		# Watch out for anchors
		if ($linkname =~ /^\#/)
			{
			# An anchor translates into a link directly in this page
			$href = "<A HREF=\"".$linkname."\" class='internal' title=\"\">$linkappereance</A>";
			}					
		else
			{
			# Find redirect target. If pointing to nowhere, delink it.
#			$target = GetRedirectTarget($linkname);
#			if (defined($target))
#				{
#				$linkname = $target;
#				}
#			else
#				{
#				return ($linkappereance, $linkappereance);
#				}
			
			print LOGFILE "Link found: $linkname\n" if $debug;
		
			## For good links, make a nice HREF
			$linkhref = &GetFileName($linkname, $namespace);


			# Remove the common prefix (these are URLs, not disk paths)
			$linkhref =~ s/^$prefix//o;
		
			# No spaces in our filenames
			$linkhref =~ s/\s/_/go;
		
			# Build a nice HREF link
			$href = "<A HREF=\"../../${linkhref}\" title=\"${linkname}\">$linkappereance</A>";
			}	
		}

	$href = $linkappereance if ($href eq "");
		
	return ($linkappereance, $href);
}

########################
# HTMLLinksToText
#
# Converts any links inside the text to their
# pure appereance, without HREFS and formatting

sub HTMLLinksToText
{
	my ($text) = @_;

	$text =~ s/\<A HREF.*?\>(.*?)\<\/A\>/$1/sig;

	$text;
}		

sub RemoveHTMLcomments {
	my ($text) = @_;
	my ($comment_start, $comment_end);
	
	$comment_start = "<!--";
	$comment_end = "-->";
	
	$text =~ s/\Q$comment_start\E.*?\Q$comment_end\E//msgo;
	
	$text;
}

sub RemoveHTMLentities {
	my ($text) = @_;
	my (%entities, $key, $subst);
		
	%entities =  (	"&amp;"		=>	"&",
					"&ndash;"	=>	"-",
					"&lt;"		=>	"<",
					"&gt;"		=>	">",
					"&quote;"	=>	"\"",
					"&quot;"	=>	"\'"
				 );
	
	foreach $key (keys %entities)
		{
		$subst = $entities{$key};
		$text =~ s/$key/$subst/g;
		}
		
	$text;
}

sub GetFileName {
	my ($linkname, $namespace) = @_;
	my $uri = canonicalize($linkname, $namespace);
	return "wiki/" . uri_escape($uri);
}

sub GetMsgValue {
	my $file = shift;
	my $ns = shift || "template";
	my ($ret) = get_wiki($file, $ns);
	return $ret;
}

1;

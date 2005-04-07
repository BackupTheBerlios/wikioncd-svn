###
# Compress::Bzip2::RandomAccess
# Part of WikiOnCD
# Copyright (C) 2005, Andrew Rodland <arodland@entermail.net>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.


package Compress::Bzip2::RandomAccess;

use Compress::Bzip2;

our $default_blocksize = 600;

sub new_to_file {
	my ($class, $file, $blocksize) = @_;

	my $package = ref($class) || $class || __PACKAGE__;

	open my $datafh, '>:raw', "$file.bz2" or return undef;
	open my $indexfh, '>:raw', "$file.index" or return undef;

	our $default_blocksize;
	
	$blocksize = $blocksize || $default_blocksize;

	print $indexfh pack("N", 0xc001d00d), pack("N", $blocksize);

	$blocksize *= 1024;
	
	my $self = {
		data => $datafh,
		'index' => $indexfh,
		blocksize => $blocksize,
	};

	bless $self, $package;
}

sub write_file {
	my ($self, $filename, $data) = @_;

	my $len = length $data;

	print { $self->{index} } pack("N", $len);	
	print { $self->{index} } "$filename\n";
	
	$self->{buffer} .= $data;

	while (length($self->{buffer}) >= $self->{blocksize}) {
		$self->flush;
	}
}

sub write_file_from_file {
	my ($self, $key, $filename) = @_;

	my $data;
	
	{
		local $/;
		open my $fh, '<:raw', $filename;
		$data = <$fh>;
		close $fh;
	}

	return $self->write_file($key, $data);
}


sub flush {
	my ($self) = @_;
	
	my $buf = substr $self->{buffer}, 0, $self->{blocksize}, '';

	my $compressed = Compress::Bzip2::compress($buf);

	my $len = length $compressed;
	print { $self->{index} } pack("N", $len | 0x80000000);
	print { $self->{data} } $compressed;
}

sub close_for_write {
	my ($self) = @_;
	
	$self->flush;
	close $self->{index};
	close $self->{data};
}

sub new_from_file {
	my ($class, $file) = @_;

	my $package = ref($class) || $class || __PACKAGE__;

	open my $datafh, '<:raw', "$file.bz2" or return undef;
	open my $indexfh, '<:raw', "$file.index" or return undef; 

	read $indexfh, my $magic, 4;
	read $indexfh, my $blocksize, 4;
	
	$blocksize = unpack("N", $blocksize);
	
	$blocksize *= 1024;

	if (!$blocksize) {
		return undef;
	}

	my $self = {
		data => $datafh,
		'index' => $indexfh,
		blocksize => $blocksize,
	};

	bless $self, $package;

	$self->do_index;
	return $self;

}

sub do_index {
	my ($self) = @_;

	my $fpos = 0;
	my $cpos = 0;
	my $block = 0;

	while (!eof($self->{'index'})) {
		read $self->{'index'}, my $code, 4;
		my $len = unpack("N", $code);
		
		if ($len & 0x80000000) {
			$len &= 0x7fffffff;
			$self->{block}[$block] = [ $cpos, $len ];
			$cpos += $len;
			$block ++;
		} else {
			chomp(my $filename = readline $self->{'index'});
			$self->{files}{$filename} = [$fpos, $len];
#			push @{$self->{filelist}}, [$x, $fpos, $y];
			$fpos += $len;
		}
	}
}

sub get_block {
	my ($self, $block) = @_;
#	print STDERR "B: $block ";
	my ($offset, $len) = @{ $self->{block}[$block] };
#	print "@ $offset:$len\n";
	my $data;

	seek $self->{data}, $offset, SEEK_SET;
	read $self->{data}, $data, $len;

	$data = Compress::Bzip2::decompress($data);
	return $data;
}

sub read_file {
	my ($self, $file) = @_;

#	print STDERR "$file\n";
	my ($offset, $len) = @{ $self->{files}{$file} };

	my $block = int($offset / $self->{blocksize});
	my $skip = $offset % $self->{blocksize};

	my $data = $self->get_block($block);
	substr($data, 0, $skip) = undef;

	while (!eof($self->{data}) && length $data < $len) {
		$block++;
		$data .= $self->get_block($block);
	}

	substr($data, $len) = undef; #Trim excess
		return $data;
}

sub close_for_read {
	my ($self) = @_;

	close $self->{'index'};
	close $self->{data};
}

1;

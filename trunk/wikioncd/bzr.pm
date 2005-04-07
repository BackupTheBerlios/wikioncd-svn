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

	open my $fh, '>:raw', $file or return undef;

	our $default_blocksize;
	
	$blocksize = $blocksize || $default_blocksize;

	print $fh pack("N", 0xc001d00d), pack("N", $blocksize);

	$blocksize *= 1024;
	
	my $self = {
		fh => $datafh,
		blocksize => $blocksize,
	};

	bless $self, $package;
}

sub file {
	my ($self, $filename, $len) = @_;

	print { $self->{fh} } pack("N", $len);
	print { $self->{fh} } "$filename\n";
}

sub data {
	my ($self, $data) = @_;
	$self->{buffer} .= $data;

	while (length($self->{buffer}) >= $self->{blocksize}) {
		$self->flush;
	}
}


sub write_file {
	my ($self, $filename, $data) = @_;

	my $len = length $data;

	$self->file($filename, $len);
	$self->data($data);
}

sub write_file_from_file {
	my ($self, $key, $filename) = @_;

	my $data;
	
	open my $fh, '<:raw', $filename;
	my $size = -s $fh;
	
	$self->file($key, $size);

	while (read $fh, $data, $self->{blocksize}) {
		$self->data($data);
	}
	close $fh;
}


sub flush {
	my ($self) = @_;
	
	my $buf = substr $self->{buffer}, 0, $self->{blocksize}, '';

	my $compressed = Compress::Bzip2::compress($buf);

	my $len = length $compressed;
	
	if ($len >= 0x80000000) {
		die "Trying to write a block of 2^31 bytes or more. Sorry.";
	}
	
	print { $self->{fh} } pack("N", $len | 0x80000000);
	print { $self->{fh} } $compressed;
	
}

sub close_for_write {
	my ($self) = @_;
	
	$self->flush;
	close $self->{fh};
}

sub new_from_file {
	my ($class, $file) = @_;

	my $package = ref($class) || $class || __PACKAGE__;

	open my $fh, '<:raw', $file or return undef;

	read $fh, my $magic, 4;
	read $fh, my $blocksize, 4;
	
	$blocksize = unpack("N", $blocksize);
	
	$blocksize *= 1024;

	if (!$blocksize) {
		return undef;
	}

	my $self = {
		fh => $indexfh,
		blocksize => $blocksize,
	};

	bless $self, $package;

	return $self;

}

sub cache_offsets {
	my $self = shift;

	my $file_pos = 0; my $block_pos = 4; my $block = 0;

	while (!eof($self->{fh})) { # Won't likely trigger, but...

		seek $self->{fh}, $block_pos, SEEK_SET;
		
		read $self->{fh}, my $code, 4;
		last if eof($self->{fh});
		my $len = unpack("N", $code);

		if ($len & 0x80000000) {
			$len &= 0x7fffffff;
			$self->{block}[$block] = [ $block_pos, $len ];
			$block_pos += 4 + $len;
			$block ++;
		} else {
			my $filename = readline $self->{fh};
			$block_pos += 4 + length $filename;
			chomp($filename);

			$self->{files}{$filename} = [ $file_pos, $len ];
			$file_pos += $len;
		}
	}
}	

sub find_file_cached {
	my ($self, $filename) = @_;

	my ($fpos, $flen) = @{ $self->{files}{$file} };
	
	my $block = int($fpos / $self->{blocksize});
	my $skip = $fpos % $self->{blocksize};
	
	my ($bpos, $blen) = @{ $self->{block}{$block} };

	seek $self->{fh}, $bpos, SEEK_SET;

	return ($flen, $skip);
}

sub find_file_nocache {
	my ($self, $wantfile) = @_;
	
	my $file_pos = 0; my $block_pos = 4; my $block = 0;
	my ($want_pos, $want_len);
	
	while (!eof($self->{fh})) {

		seek $self->{fh}, $block_pos, SEEK_SET;
		read $self->{fh}, my $code, 4 or die $!;
		my $len = unpack("N", $code);

		if ($len & 0x80000000) {
			if (defined $want_pos && ($block + 1) * $blocksize >= $want_pos) {
				seek $self->{fh}, $block_pos, SEEK_SET; #Back it up a bit.
				return ($want_len, $want_pos % self->{blocksize});
			}
				
			$len &= 0x7fffffff;
			$block_pos += 4 + $len;
			$block ++;
		} else {
			my $filename = readline $self->{fh};
			$block_pos += 4 + length $filename;
			chomp($filename);

			if ($filename eq $wantfile) {
				$want_pos = $file_pos;
			}
			$file_pos += $len;
		}
	}
}

sub decompress_one_block {
	my $self = shift;
	
	my $code;
	read $self->{fh}, $code, 4;
	my $len = unpack("N", $code);
	
	die "Doesn't look like a block" unless $len & 0x80000000;
	$len &= 0x7fffffff;

	my $data;
	read $self->{fh}, $data, $len or die $!;
	return Compress::Bzip2::decompress($data);
}

sub read_file {
	my ($self, $file) = @_;

	my ($len, $skip);
	
	if (defined $self->{block} && defined $self->{files}) {
		($len, $skip) = $self->find_file_cached($file);
	} else {
		($len, $skip) = $self->find_file_nocache($file);
	}

	my $data = $self->decompress_one_block();
	substr ($data, 0, $skip) = undef;
	
	while (length $data < $len) {
		$data .= $self->decompress_one_block();
	}

	substr($data, $len) = undef;
	return $data;
}

sub close_for_read {
	my ($self) = @_;

	close $self->{fh};
}

1;

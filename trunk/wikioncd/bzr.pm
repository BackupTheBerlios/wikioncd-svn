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
our $debug = 1;

sub debug {
	our $debug;
	
	print STDERR @_ if $debug;
}

sub new_to_file {
	my ($class, $file, $blocksize) = @_;

	my $package = ref($class) || $class || __PACKAGE__;

	open my $fh, '>:raw', $file or return undef;

	our $default_blocksize;
	
	$blocksize = $blocksize || $default_blocksize;

	print $fh pack("N", 0xc001d00d), pack("N", $blocksize);

	$blocksize *= 1024;
	
	my $self = {
		fh => $fh,
		blocksize => $blocksize,
	};

	bless $self, $package;
}

sub file {
	my ($self, $filename, $len) = @_;

	print { $self->{fh} } pack("N", $len);
	print { $self->{fh} } "$filename\n";
	
	debug "wrote header for $len bytes file $filename.\n";
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

	debug "Wrote header for $len bytes block.\n";	
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
		fh => $fh,
		blocksize => $blocksize,
	};

	bless $self, $package;

	return $self;

}

sub cache_offsets {
	my $self = shift;

	my $file_pos = 0; my $block_pos = 8; my $block = 0;

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
			debug "(C) found $len bytes block.\n";
			
		} else {
			my $filename = readline $self->{fh};
			$block_pos += 4 + length $filename;
			chomp($filename);

			$self->{files}{$filename} = [ $file_pos, $len ];
			$file_pos += $len;

			debug "(C) found $len bytes file $filename.\n";
		}
	}
}	

sub find_file_cached {
	my ($self, $filename) = @_;

	my ($fpos, $flen) = @{ $self->{files}{$filename} };
	
	my $block = int($fpos / $self->{blocksize});
	my $skip = $fpos % $self->{blocksize};
	
	my ($bpos, $blen) = @{ $self->{block}[$block] };

	seek $self->{fh}, $bpos, SEEK_SET;

	return ($flen, $skip);
}

sub find_file_nocache {
	my ($self, $wantfile) = @_;
	
	my $file_pos = 0; my $block_pos = 8; my $block = 0;
	my ($want_pos, $want_len);
	
	while (!eof($self->{fh})) {

		seek $self->{fh}, $block_pos, SEEK_SET;
		read $self->{fh}, my $code, 4 or return undef;
		my $len = unpack("N", $code);

		if ($len & 0x80000000) {
			if (defined $want_pos && ($block + 1) * $self->{blocksize} >= $want_pos) {
				debug "(U) And we're there!\n";
				seek $self->{fh}, $block_pos, SEEK_SET; #Back it up a bit.
				return ($want_len, $want_pos % $self->{blocksize});
			}
				
			$len &= 0x7fffffff;
			$block_pos += 4 + $len;
			$block ++;

			debug "(U) found $len bytes block.\n";
			
		} else {
			my $filename = readline $self->{fh};
			$block_pos += 4 + length $filename;
			chomp($filename);

			debug "(U) found $len bytes file $filename.\n";

			if ($filename eq $wantfile) {
				$want_pos = $file_pos;
				$want_len = $len;
				debug "(U) That's it!\n";
			}
			$file_pos += $len;
		}
	}
}

sub decompress_one_block {
	my $self = shift;
	my $len;

	while (!$len) {	
		my $code;
		read $self->{fh}, $code, 4;
		$len = unpack("N", $code);
		if ($len & 0x80000000) {
			$len &= 0x7fffffff;
		} else {
			readline $self->{fh};
			$len = 0;
		}
	}

	my $data;
	read $self->{fh}, $data, $len or die $!;

	$data = Compress::Bzip2::decompress($data);
	
	my $elen = length $data;
	
	debug "Read $len bytes block ($elen bytes).\n";
	return $data;

}

sub read_file {
	my ($self, $file) = @_;

	my ($len, $skip);
	
	if (defined $self->{block} && defined $self->{files}) {
		($len, $skip) = $self->find_file_cached($file);
	} else {
		($len, $skip) = $self->find_file_nocache($file);
	}

	return(undef), debug "Not found!\n" unless $len;

	debug "Getting $len bytes data.\n";

	my $data = $self->decompress_one_block();
	substr ($data, 0, $skip) = undef;
	
	while (length($data) < $len) {
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

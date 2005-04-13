package Compress::Dictionary::ADR;

sub new_for_compress {
	my $filename = shift;
	
	my %words;
	my $count = 0;
	
	open my $fh, '<', $filename or die $!;

	while (<$fh>) {
		chomp;
		if ($count < 64) {
			$words{$_} = chr(0x80 + $count);
		} elsif ($count < 8128) {
			my $lower = ($count - 64) % 128;
			my $upper = ($count - 64) / 128;
			$words{$_} = chr(0xc0 + $upper) . chr($lower)
		} else {
			my $upper = ($count - 8128) / 32768;
			my $mid = ($count - 8128) % 32768;
			my $lower = $mid % 256;
			$mid /= 256;
			$words{$_} = chr(0xc0 + $upper) . chr(0x80 + $mid) . chr($lower);
		}
		$count ++;
	}

	bless { words => \%words };
}

sub new_for_decompress {
	my $filename = shift;

	my @words;

	open my $fh, '<', $filename or die $!;

	while (<$fh>) {
		chomp;
		push @words, $_;
	}

	bless { words => \@words };
}

sub compress_word {
	my ($self, $word) = @_;
	
	return $self->{words}{$word} || $word;
}

sub compress {
	my ($self, $text) = @_;

	$text =~ s/([\x80-\xff])/\xff$1/msg;

	$text =~ s/(\w+)/$self->{words}{$1} || $1/emsg;

	return $text;
}

sub decompress_word {
	my ($self, $code) = @_;

	my ($first, $second, $third) = split '', $code;
	
	my $one = ord $first;
	
	die unless $one >= 128;
	
	if ($one == 0xff) {
		print STDERR "a\n";
		return $second;
	} elsif ($one & 0x40) {
		print STDERR "b\n";
		$one &= 0x3f;
		my $two = ord $second;
		if ($two & 0x80) {
			$two &= 0x80;
			print STDERR "b\n";
			my $three = ord $third;
			return $self->{words}[8128 + $three +
				256 * ($two + 128 * $one)];
		} else {
			print STDERR "c\n";
			return $self->{words}[64 + $two +
				128 * $one];
		}
	} else {
		print STDERR "d\n";
		$one &= 0x3f;
		return $self->{words}[$one];
	}
}

sub decompress {
	my ($self, $text) = @_;
	my $ch;
	my $out;

	while (($ch = substr $text, 0, 1, '') ne '') {
		my $one = ord ($ch);

		unless ($one & 0x80) {
#			print STDERR "literal\n";
			$out .= $ch;
			next;
		}

		if ($one == 0xff) {
#			print STDERR "escape\n";
			$out .= substr $text, 0, 1, '';
			next;
		}

		unless ($one & 0x40) {
#			printf STDERR "1byte: \%x\n", $one;
			$out .= $self->{words}[$one & 0x3f];
		} else {
			$one &= 0x3f;
			my $two = ord substr $text, 0, 1, '';
			unless ($two & 0x80) {
#				printf STDERR "2byte: \%x \%x\n", $one, $two;
				$out .= $self->{words}[64 + $two + 128 * $one];
			} else {
				my $three = ord substr $text, 0, 1, '';
#				printf STDERR "3byte: \%x \%x \%x\n", $one, $two, $three;
				$two &= 0x7f;
				$out .= $self->{words}[8128 + $three + 256 * ($two + 128 *
						$one)];
			}
		}
	}

	return $out;	
}

1;

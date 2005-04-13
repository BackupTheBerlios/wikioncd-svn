#!/usr/bin/perl
#
use Inline Config => CLEAN_AFTER_BUILD => 0;

use Inline C => DATA => LIBS => '-lbz2';

$bz2 = compress("Hello, world!\n");
print $bz2, "\n----------\n";
my $orig = decompress($bz2);
print $orig, "\n";

__END__
__C__

#include <bzlib.h>

void compress(SV *in) {
	char *indata;
	int len, outlen, bz_status;
	SV *ret;
	
	Inline_Stack_Vars;

	indata = SvPV(in, len);
	outlen = len + (len / 100) + 600;

	ret = newSVpv("", outlen);

	bz_status = BZ2_bzBuffToBuffCompress(SvPVX(ret), &outlen, indata, len, 9, 0, 0);

	if (bz_status == BZ_OK) {
		sv_setpvn(ret, SvPVX(ret), outlen);
	} else {
		sv_setsv(ret, &PL_sv_undef);
	}
	Inline_Stack_Push(ret);
	Inline_Stack_Done;
	
}

void decompress(SV *in) {
	char *indata;
	int len, outlen, bz_status;
	SV *ret;
	
	Inline_Stack_Vars;

	indata = SvPV(in, len);
	outlen = len * 2;

	ret = newSVpv("", outlen);
	
	bz_status = BZ2_bzBuffToBuffDecompress(SvPVX(ret), &outlen, indata, len, 0, 0);
	while (bz_status == BZ_OUTBUFF_FULL) {
		outlen *= 2;
		sv_setpvn(ret, SvPVX(ret), outlen);
		bz_status = BZ2_bzBuffToBuffDecompress(SvPVX(ret), &outlen, indata, len,
				0, 0);
	}
	if (bz_status == BZ_OK) {
		sv_setpvn(ret, SvPVX(ret), outlen);
	} else {
		sv_setsv(ret, &PL_sv_undef);
	}
	Inline_Stack_Push(ret);
	Inline_Stack_Done;
}

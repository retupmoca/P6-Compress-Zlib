use v6;
module Compress::Zlib;

need Compress::Zlib::Raw;
use NativeCall;

our sub compress(Blob $data, Int $level = 6 --> Buf) is export {
    if $level < -1 || $level > 9 {
        die "compression level must be between -1 and 9";
    }
    my $indata = CArray[int8].new();
    my $inlen = 0;
    for $data.list {
        $indata[$inlen++] = $_;
    }

    my $outlen = CArray[int].new();
    $outlen[0] = Compress::Zlib::Raw::compressBound($inlen);
    my $outdata = CArray[int8].new();
    $outdata[$outlen[0] - 1] = 1;

    Compress::Zlib::Raw::compress2($outdata, $outlen, $indata, $inlen, $level);

    my $len = $outlen[0];
    my @out;
    for 0..^$len {
        @out[$_] = $outdata[$_];
    }
    return Buf.new(@out);
}

our sub uncompress(Blob $data --> Buf) is export {
    my $indata = CArray[int8].new();
    my $inlen = 0;
    for $data.list {
        $indata[$inlen++] = $_;
    }

    my $bufsize = $inlen;
    my $outdata = CArray[int8].new();
    my $outlen = CArray[int].new();
    my $ret = Compress::Zlib::Raw::Z_BUF_ERROR;
    while $ret == Compress::Zlib::Raw::Z_BUF_ERROR {
        $bufsize = $bufsize * 2;
        $outdata[$bufsize - 1] = 1;
        $outlen[0] = $bufsize;

        $ret = Compress::Zlib::Raw::uncompress($outdata, $outlen, $indata, $inlen);
        if $ret == Compress::Zlib::Raw::Z_DATA_ERROR {
            die "uncompress data error";
        }
    }

    my $len = $outlen[0];
    my @out;
    for 0..^$len {
        @out[$_] = $outdata[$_];
    }
    return Buf.new(@out);
}

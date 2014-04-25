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

class Compress::Zlib::Stream {
    has $!z-stream;
    has $!gz-header;

    has $!has-header;
    has $!deflate-init = False;
    has $!inflate-init = False;

    has $.finished = False;

    has $!zlib-finished = False;

    method inflate($data) {
        die "Cannot inflate and deflate with the same object!" if $!deflate-init;
        die "Stream end reached!" if $.finished;

        unless $!inflate-init {
            $!z-stream = Compress::Zlib::Raw::z_stream.new;
        }

        my $input-buf = CArray[int8].new;
        for 0..^$data.elems {
            $input-buf[$_] = $data[$_];
        }
        $!z-stream.set-input($input-buf, $data.elems);

        my @out;

        loop {
            my $output-buf = CArray[int8].new;
            $output-buf[1023] = 1;
            $!z-stream.set-output($output-buf, 1024);

            unless $!inflate-init {
                $!inflate-init = True;
                Compress::Zlib::Raw::inflateInit($!z-stream);
            }

            my $ret = Compress::Zlib::Raw::inflate($!z-stream, Compress::Zlib::Raw::Z_SYNC_FLUSH);
            
            unless $ret == Compress::Zlib::Raw::Z_OK|Compress::Zlib::Raw::Z_STREAM_END {
                fail "...";
            }

            for 0..^(1024 - $!z-stream.avail-out) {
                @out.push($output-buf[$_]);
            }
            
            if $ret == Compress::Zlib::Raw::Z_STREAM_END {
                self.finish;
            }

            if $ret == Compress::Zlib::Raw::Z_STREAM_END || ($!z-stream.avail-out && !($!z-stream.avail-in)) {
                return Buf.new(@out);
            }
        }
    }

    method deflate($data) {
        die "Cannot inflate and deflate with the same object!" if $!inflate-init;
        die ".finish was called!" if $.finished;

        unless $!deflate-init {
            $!z-stream = Compress::Zlib::Raw::z_stream.new;
        }

        my $input-buf = CArray[int8].new;
        for 0..^$data.elems {
            $input-buf[$_] = $data[$_];
        }
        $!z-stream.set-input($input-buf, $data.elems);

        my @out;

        loop {
            my $output-buf = CArray[int8].new;
            $output-buf[1023] = 1;
            $!z-stream.set-output($output-buf, 1024);

            unless $!deflate-init {
                $!deflate-init = True;
                Compress::Zlib::Raw::deflateInit($!z-stream, 6);
            }

            # XXX At some point, we should support Z_NO_FLUSH, as we can get
            # slightly better compression ratios that way
            my $ret = Compress::Zlib::Raw::deflate($!z-stream, Compress::Zlib::Raw::Z_SYNC_FLUSH);

            unless $ret == Compress::Zlib::Raw::Z_OK {
                fail "...";
            }

            for 0..^(1024 - $!z-stream.avail-out) {
                @out.push($output-buf[$_]);
            }

            if $!z-stream.avail-out && !($!z-stream.avail-in) {
                return Buf.new(@out);
            }
        }
    }

    method flush(:$finish) {
        if $!inflate-init {
            return Buf.new();
        } elsif $!deflate-init {
            if $finish && !$!finished {
                my @out;
                loop {
                    my $output-buf = CArray[int8].new;
                    $output-buf[1023] = 1;
                    $!z-stream.set-output($output-buf, 1024);

                    my $ret = Compress::Zlib::Raw::deflate($!z-stream, Compress::Zlib::Raw::Z_FINISH);

                    unless $ret == Compress::Zlib::Raw::Z_OK|Compress::Zlib::Raw::Z_STREAM_END {
                        fail "...";
                    }

                    for 0..^(1024 - $!z-stream.avail-out) {
                        @out.push($output-buf[$_]);
                    }

                    if $ret == Compress::Zlib::Raw::Z_STREAM_END {
                        $!finished = True;
                    }

                    if $ret == Compress::Zlib::Raw::Z_STREAM_END || $!z-stream.avail-out {
                        return Buf.new(@out);
                    }
                }
            } else {
                return Buf.new();
            }
        }
    }

    method finish() {
        if $!zlib-finished {
            return;
        }
        $!zlib-finished = True;
        my $flushed = self.flush(:finish);
        if $!inflate-init {
            Compress::Zlib::Raw::inflateEnd($!z-stream);
            $!finished = True;
        } elsif $!deflate-init {
            Compress::Zlib::Raw::deflateEnd($!z-stream);
            $!finished = True;
        }
        return $flushed;
    }
}

# implement a 'role zlibStream' (so you can do $file but zlibStream)

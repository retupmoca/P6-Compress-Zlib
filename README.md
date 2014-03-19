P6-Compress-Zlib
================

## Name ##

Compress::Zlib - A (hopefully) nice interface to zlib

## Description ##

Compresses and uncompresses data using zlib. Currently is only an interface to zlib's compress2() and
uncompress() functions. At some point in the future (or if requested), the stream-oriented functions
will be added.

## Example Usage ##

    use Compress::Zlib;
    
    my $compressed = compress($string.encode('utf8'));
    my $original = uncompress($compressed).decode('utf8');

## Functions ##

### `compress(Blob $data, Int $level? --> Buf)`

Compresses binary $data. $level is the optional compression level (0 <= x <= 9); defaults to 6.

### `uncompress(Blob $data --> Buf)`

Uncompresses previously compressed $data.

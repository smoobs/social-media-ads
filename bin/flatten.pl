#!/usr/bin/env perl

use v5.10;

use autodie;
use strict;
use warnings;

use DateTime;
use JSON ();
use Path::Class;

STDOUT->binmode(":utf8");

for my $src (@ARGV) {
  my $stash = load_json($src);
  for my $rec (@$stash) {
    my @flat = flatten($rec);
    say "--";
    for my $row (@flat) {
      say sprintf "%-40s: \"%s\"", $row->[0], $row->[1];
    }
  }
}

sub flatten {
  my ( $rec, @path ) = @_;

  if ( ref $rec ) {
    if ( "ARRAY" eq ref $rec ) {
      my $path = join( ".", @path ) . "[]";
      return map { flatten( $_, $path ) } @$rec;
    }

    if ( "HASH" eq ref $rec ) {
      return map { flatten( $rec->{$_}, @path, $_ ) } sort keys %$rec;
    }

    die "Can't flatten that";
  }

  return [join( ".", @path ), $rec];
}

sub save_json {
  my ( $file, $json ) = @_;
  my $fh = file($file)->openw;
  $fh->binmode(":utf8");
  $fh->print( JSON->new->pretty->canonical->encode($json) );
}

sub load_json {
  my $file = shift;
  my $fh   = file($file)->openr;
  $fh->binmode(":utf8");
  return JSON->new->decode(
    do { local $/; <$fh> }
  );
}

# vim:ts=2:sw=2:sts=2:et:ft=perl


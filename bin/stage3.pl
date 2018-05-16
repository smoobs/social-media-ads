#!/usr/bin/env perl

use v5.10;

use autodie;
use strict;
use warnings;

use JSON ();
use Path::Class;

use constant TXT => dir("trove/txt");
use constant IN  => file("work/stage2.json");
use constant OUT => file("work/stage3.json");

my $context = undef;

sub report(@) {
  my @msg = @_;
  push @msg, ' in "', $context->{source}, '"'
   if defined $context;
  warn @msg;
}

OUT->parent->mkpath;

my $stash     = load_json(IN);
my $stash_out = [];

my $mapper = make_mapper(
  { 'also_match.*' => 'match.*',
    'behaviors.*'  => 'match.*',
    'interests'    => 'match.interests',
    'job_title'    => 'match.job_title',
    'politics'     => 'match.politics',
  }
);

for my $rec (@$stash) {
  set_context($rec);
  my $out  = {};
  my @flat = flatten($rec);
  for my $attr (@flat) {
    my ( $fd, $val ) = @$attr;
    my $mfd = $mapper->($fd);
    if ( $mfd =~ /^(.+)\[\]$/ ) {
      push @{ $out->{$1} }, $val;
    }
    else {
      $out->{$mfd} = $val;
    }
  }
  push @$stash_out, $out;
}

save_json( OUT, $stash_out );

sub make_mapper {
  my $map = shift;

  my @match = ();
  while ( my ( $from, $to ) = each %$map ) {
    my $re = key_to_re($from);
    push @match, { re => $re, to => $to };
  }

  return sub {
    my $key = shift;
    ( my $alias = $key ) =~ s/\[\]$//;
    for my $m (@match) {
      if ( my @cap = ( $alias =~ $m->{re} ) ) {
        ( my $to = $m->{to} ) =~ s/\*/shift @cap/eg;
        return $to . "[]";
      }
    }
    return $key;
  };
}

sub key_to_re {
  my $key = shift;
  my $re  = join quotemeta("."),
   map { $_ eq '*' ? "([^.]+)" : quotemeta($_) } split /\./, $key;
  return qr{^$re$};
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

sub set_context { $context = shift }

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


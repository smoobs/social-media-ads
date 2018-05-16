#!/usr/bin/env perl

use v5.10;

use autodie;
use strict;
use warnings;

use File::Find;
use Path::Class;
use List::Util qw( max );

use constant TXT => dir("trove/txt");

use constant MAX_DEPTH => 6;
use constant MIN_COUNT => 10;

my $tree = {};

find(
  { wanted => sub {
      return unless /\.txt$/i;
      return if /-\d{3}\.txt$/i;
      scan( file($_) );
    },
    no_chdir => 1
  },
  TXT
);

show_tree($tree);

sub scan {
  my $file = shift;
  my $fh   = $file->openr;
  while (<$fh>) {
    chomp;

    s/^\s+//;
    s/\s+$//;
    s/\s+/ /g;
    s/\x0c//g; # Remove form feed

    my @words = split /\s+/;
    my $slot  = $tree;
    for my $word (@words) {
      $slot->{$word} //= { count => 0, next => {} };
      $slot->{$word}{count}++;
      $slot = $slot->{$word}{next};
    }
  }
}

sub show_tree {
  my $nd    = shift;
  my $depth = shift // 0;
  my @path  = @_;

  my @by_freq = map { $_->[1] }
   sort { $b->[0] <=> $a->[0] }
   grep { $_->[0] >= MIN_COUNT }
   map { [$nd->{$_}{count}, $_] } keys %$nd;

  return unless @by_freq;

  my $pad = "  " x $depth;
  my $fmt = "%6d |$pad %s";

  for my $key (@by_freq) {
    say "" unless $depth;
    say sprintf $fmt, $nd->{$key}{count}, join " ", @path, $key;
    show_tree( $nd->{$key}{next}, $depth + 1, @path, $key )
     if $depth < MAX_DEPTH;
  }
}

# vim:ts=2:sw=2:sts=2:et:ft=perl


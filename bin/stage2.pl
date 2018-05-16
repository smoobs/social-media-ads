#!/usr/bin/env perl

use v5.10;

use autodie;
use strict;
use warnings;

use File::Find;
use JSON ();
use List::Util qw( max );
use Path::Class;

use constant TXT => dir("trove/txt");
use constant IN  => file("work/stage1.json");
use constant OUT => file("work/stage2.json");

OUT->parent->mkpath;

my $context = undef;

sub report(@) {
  my @msg = @_;
  push @msg, ' in "', $context->{source}, '"'
   if defined $context;
  warn @msg;
}

my $number = sub {
  my $val = shift;

  return 0 if $val eq "None";

  $val =~ s/[,;\s]//g;
  $val =~ s/O/0/g;

  # Fix multiple dots
  my @part = split /\./, $val;
  if ( @part > 1 ) {
    my $deci = pop @part;
    $val = join ".", join( "", @part ), $deci;
  }

  report "Bad number: $val"
   unless $val =~ /^\d+(?:\.\d+)?$/;

  return $val;
  return 1 * $val;
};

my $currency = sub {
  my $val = shift;

  return { amount => 0, currency => "UNK" }
   if $val eq "None" || $val =~ /^0+(?:\.0+)?$/;

  $val =~ s/US0/USD/;
  $val =~ s/\s+$//;

  report "Bad currency: $val"
   unless $val =~ /^(.+?)\s*([A-Z]\s?[A-Z]\s?[A-Z])$/;

  my $amt = $number->($1);
  ( my $cur = $2 ) =~ s/\s//g;

  return { amount => $amt, currency => $cur };
};

my %field_trans = (
  ad_impressions        => $number,
  ad_clicks             => $number,
  ad_spend              => $currency,
  ad_targeting_location => sub { },
  ad_targeting_custom   => sub { },
  ad_creation_date      => sub { },
  ad_landing_page       => sub { },
  ad_text               => sub { },
  ad_id                 => sub { },
  ad_end_date           => sub { },
  age                   => sub { },
  placements            => sub { },
  people_who_match      => sub { },
  sponsored             => sub { },
  language              => sub { },
  excluded_connections  => sub { },
  interests             => sub { },
);

my $stash = load_json(IN);
my $key   = "ad_id";
my %count = ();

for my $rec (@$stash) {
  $context = $rec;
  next unless exists $rec->{$key};
  my $val = join " ", @{ $rec->{$key} };
  $number->($val);
  $count{$val}++;
}

for my $key ( sort { $count{$a} <=> $count{$b} } keys %count ) {
  printf "%5d %s\n", $count{$key}, $key;
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


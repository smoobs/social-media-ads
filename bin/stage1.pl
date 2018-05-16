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
use constant OUT => file("work/stage1.json");

OUT->parent->mkpath;

my %field_tag = (
  'Ad Clicks'               => 'clicks',
  'Ad Creation Date'        => 'creation_date',
  'Ad Custom Includes:'     => 'custom_includes',
  'Ad End Date'             => 'end_date',
  'Ad ID'                   => 'id',
  'Ad Impressions'          => 'impressions',
  'Ad Landing Page'         => 'landing_page',
  'Ad Spend'                => 'spend',
  'Ad Targeting Custom'     => 'targeting_custom',
  'Ad Targeting Location'   => 'targeting_location',
  'Ad Targeting Location:'  => 'targeting_location',
  'Ad Text'                 => 'text',
  'Age:'                    => 'age',
  'Excluded Connections:'   => 'excluded_connections',
  'Gender:'                 => 'gender',
  'Interests:'              => 'interests',
  'Language:'               => 'language',
  'People Who Match:'       => 'people_who_match',
  'Placements'              => 'placements',
  'Placements:'             => 'placements',
  'Redactions Completed at' => undef,
  'Sponsored'               => 'sponsored',
);

my $field_re = make_field_re( \%field_tag );

my $stash = [];

find(
  { wanted => sub {
      return unless /\.txt$/i;
      return if /-\d{3}\.txt$/i;
      push @$stash, scan( file($_) );
    },
    no_chdir => 1
  },
  TXT
);

save_json( OUT, $stash );

sub scan {
  my $file = shift;

  my $fh  = $file->openr;
  my $rec = { source => "$file" };
  my $key = undef;

  while (<$fh>) {
    chomp;

    s/^\s+//;
    s/\s+$//;
    s/\s+/ /g;
    s/\x0c//g;    # Remove form feed
    s/—/-/g;    # Normalise hyphens

    my $ln = $_;
    if ( $ln =~ /^($field_re)\s*(.*)/ ) {
      my ( $tag, $tail ) = ( $1, $2 );
      die "Can't map \"$tag\"" unless exists $field_tag{$tag};
      $key = $field_tag{$tag};
      $ln  = $tail;
    }

    push @{ $rec->{$key} }, $ln
     if defined $key && length $ln;
  }
  return $rec;
}

sub make_field_re {
  my $map  = shift;
  my @keys = sort { length $b <=> length $a } keys %$map;
  my $alt  = join "|", map quotemeta, @keys;
  return qr{$alt};
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


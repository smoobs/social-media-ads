#!/usr/bin/env perl

use v5.10;

use autodie;
use strict;
use warnings;

use DateTime;
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

my %tz_map = (
  PDT => '-0700',
  PST => '-0800',
);

my $f_or_list = sub {
  return [or_list( $_[0] )];
};

my $f_number = sub {
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

  return 1 * $val;
};

my $f_integer = sub {
  my $val = $f_number->(shift);
  $val =~ s/\.//g;
  return 1 * $val;
};

my $f_currency = sub {
  my $val = shift;

  return { amount => 0, currency => "UNK" }
   if $val eq "None" || $val =~ /^0+(?:\.0+)?$/;

  $val =~ s/US[0O]/USD/;
  $val =~ s/\s+$//;

  report "Bad currency: $val"
   unless $val =~ /^(.+?)\s*([A-Z]\s?[A-Z]\s?[A-Z])$/;

  my $amt = $f_number->($1);
  ( my $cur = $2 ) =~ s/\s//g;

  return { amount => $amt, currency => $cur };
};

my $f_date = sub {
  my $val = shift;

  $val =~ s/\s*([:\/])\s*/$1/g;

  report "Bad date: $val"
   unless $val =~ m{
     ^
     (\d\d)/(\d\d)/(\d\d) \s+ 
     (\d\d):(\d\d):(\d\d) \s+ 
     ([AP]M) \s+ 
     ([A-Z]{3})
     $
   }x;

  my ( $mo, $da, $yr, $hr, $mi, $se, $xm, $tz )
   = ( $1, $2, $3, $4, $5, $6, $7, $8 );

  my $hour = $hr % 12;
  $hour += 12 if $xm eq "PM";

  my $tz_offset = $tz_map{$tz} // report "Bad timezone: $tz";

  my $date = DateTime->new(
    year      => $yr + 2000,
    month     => $mo,
    day       => $da,
    hour      => $hour,
    minute    => $mi,
    second    => $se,
    time_zone => $tz_offset,
  );

  return $date->format_cldr("yyyy-MM-dd'T'HH:mm:ssZ");
};

my $f_age = sub {
  my $val = shift;

  report "Bad age: $val"
   unless $val =~ /^(\d+)[-\s]+(\d+\+?)$/;

  my $rep = { min => $1 };
  $rep->{max} = $2 unless $2 eq "65+";
  return $rep;
};

my $f_url = sub {
  my $val = shift;
  $val =~ s/\s+//g;
  $val =~ s{^(https?):H}{$1://};
  return $val;
};

my $f_match = make_tag_matcher(
  { 'Behaviors'              => 'behaviors',
    'Employers'              => 'employers',
    'Field of study'         => 'field_of_study',
    'Friends of connections' => 'friends_of_connections',
    'Friends of people who'  => 'friends_of',
    'Industry'               => 'industry',
    'Interests'              => 'interests',
    'Job title'              => 'job_title',
    'People who like'        => 'like',
    'Politics'               => 'politics',
  }
);

my $f_location_match = make_tag_matcher(
  { 'Living In:'   => 'living_in',
    'Recently In:' => 'recently_in',
  },
  "living_in"
);

my $f_location = sub {
  my $val = shift;
  $val =~ s/^-\s*//;
  return $f_location_match->($val);
};

my $f_behave = make_tag_matcher(
  { 'Field of study'          => 'field_of_study',
    'Multicultural Affinity:' => 'multicultural_affinity',
  },
  'behaviour'
);

my $f_nop = sub { $_[0] };

my %field_trans = (
  age                    => $f_age,
  also_match             => $f_match,
  behaviors              => $f_behave,
  clicks                 => $f_integer,
  connections            => $f_nop,
  creation_date          => $f_date,
  currently_using        => $f_or_list,
  custom_includes        => $f_nop,
  end_date               => $f_date,
  excluded_connections   => $f_nop,
  gender                 => $f_nop,
  generation             => $f_nop,
  id                     => $f_integer,
  impressions            => $f_integer,
  interest_expansion     => $f_nop,
  interests              => $f_or_list,
  job_title              => $f_or_list,
  landing_page           => $f_url,
  language               => $f_or_list,
  match                  => $f_match,
  multicultural_affinity => $f_nop,
  placements             => $f_or_list,
  politics               => $f_or_list,
  source                 => $f_nop,
  spend                  => $f_currency,
  sponsored              => $f_nop,
  targeting_custom       => $f_nop,
  targeting_location     => $f_location,
  text                   => $f_nop,
);

my $stash     = load_json(IN);
my $stash_out = [];

for my $rec (@$stash) {
  set_context($rec);

  my $out = {};

  while ( my ( $k, $v ) = each %$rec ) {
    my $xlate = $field_trans{$k} // report "Can't map: $k";
    $v = join " ", @$v if "ARRAY" eq ref $v;
    my $xv = $xlate->($v);
    if ( "HASH" eq ref $xv && !delete $xv->{_deep} ) {
      while ( my ( $hk, $hv ) = each %$xv ) {
        $out->{ join "_", $k, $hk } = $hv;
      }
    }
    else {
      $out->{$k} = $xv;
    }
  }

  push @$stash_out, $out;
}

#inspect( survey( $stash_out, 'targeting_location' ) );

save_json( OUT, $stash_out );

sub inspect {
  my $survey = shift;

  for my $key ( sort keys %$survey ) {
    say "=== $key ===";
    my $report = $survey->{$key};
    my @by_freq = map { $_->[0] } sort { $a->[1] <=> $b->[1] }
     map { [$_, scalar( @{ $report->{$_} } )] } keys %$report;
    for my $val (@by_freq) {
      printf "%4d %s\n", scalar( @{ $report->{$val} } ), $val;
    }
  }
}

sub survey {
  my ( $stash, @key ) = @_;

  my $survey = {};

  for my $rec (@$stash) {
    for my $key (@key) {
      next unless exists $rec->{$key};
      my $val = $rec->{$key};
      $val = JSON->new->canonical->encode($val) if ref $val;
      push @{ $survey->{$key}{$val} }, $rec->{source};
    }
  }

  return $survey;
}

sub set_context { $context = shift }

sub or_list {
  my $val = shift;
  $val =~ s/^[:]//;
  return grep { length } map { strip($_) } split /[,;]|\bor\b/, $val;
}

sub make_tag_matcher {
  my $tags = shift;
  my $initial = shift // "unknown";

  my $re = make_hash_re($tags);

  return sub {
    my $val  = shift;
    my @part = split /($re)/, $val;
    my $rec  = { _deep => 1 };
    my $kind = $initial;

    while (@part) {
      my $pv = shift @part;
      if ( length $pv ) {
        $pv =~ s/^[:.]\s*//;
        push @{ $rec->{$kind} }, or_list($pv);
      }
      last unless @part;
      my $kind_tag = shift @part;
      $kind = $tags->{$kind_tag} // report "Bad tag: $kind_tag";
    }

    return $rec;
  };
}

sub make_hash_re {
  my $map  = shift;
  my @keys = sort { length $b <=> length $a } keys %$map;
  my $alt  = join "|", map quotemeta, @keys;
  return qr{$alt};
}

sub strip {
  my $s = shift;
  for ($s) {
    s/^\s+//;
    s/[.\s]+$//;
    s/\s+/ /;
  }
  return $s;
}

sub tidy {
  my $s = shift;
  s/^\s+//, s/\s+$//, s/\s+/ / for $s;
  return $s;
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


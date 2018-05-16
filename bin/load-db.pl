#!/usr/bin/env perl

use v5.10;

use autodie;
use strict;
use warnings;

use DBI;

use Digest::MD5 qw( md5_hex );
use JSON ();
use Path::Class;

STDOUT->binmode(":utf8");

use constant HOST => 'localhost';
use constant USER => 'root';
use constant PASS => '';
use constant DB   => 'sma';

use constant SALT => "Facebook Ads";

my $db = dbh();

$db->do("TRUNCATE `$_`") for "advert_field", "field_value", "advert";

for my $src (@ARGV) {
  my $stash = load_json($src);
  for my $rec (@$stash) {
    say "Loading $rec->{id}";
    my %ins  = ();
    my $idx  = 0;
    my $uuid = make_uuid( advert => $rec->{id} );
    push @{ $ins{advert} }, { uuid => $uuid };
    for my $fv ( flatten($rec) ) {
      my ( $field, $val ) = @$fv;
      if ( $field =~ /^(.+)\[\]$/ ) {
        push @{ $ins{advert_field} },
         {advert_uuid => $uuid,
          field       => $1,
          value_uuid  => field_uuid( $db, $val ),
          index       => $idx++
         };
      }
      else {
        $ins{advert}[0]{$field} = $val;
      }
    }

    while ( my ( $table, $vals ) = each %ins ) {
      insert( $db, $table, @$vals );
    }
  }
}

$db->disconnect();

sub field_uuid {
  my ( $db, $val ) = @_;
  state %field_cache;

  return $field_cache{$val} //= do {
    my $uuid = make_uuid( field => $val );
    $db->do( "INSERT INTO `field_value` (`uuid`, `value`) VALUES (?, ?)",
      {}, $uuid, $val );
    $uuid;
  };
}

sub format_uuid {
  my $uuid = shift;
  return lc join '-', $1, $2, $3, $4, $5
   if $uuid =~ /^ ([0-9a-f]{8}) -?
                  ([0-9a-f]{4}) -?
                  ([0-9a-f]{4}) -?
                  ([0-9a-f]{4}) -?
                  ([0-9a-f]{12}) $/xi;
  die "Bad UUID";
}

sub make_uuid {
  return format_uuid( md5_hex( SALT, @_ ) );
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

sub insert {
  my ( $db, $table, @rows ) = @_;

  return unless @rows;

  my @cols = sort keys %{ $rows[0] };
  my $vals = '(' . join( ', ', ("?") x @cols ) . ')';

  $db->do(
    join( ' ',
      "INSERT INTO `$table` (",
      join( ', ', map "`$_`", @cols ),
      ") VALUES",
      join( ', ', ($vals) x @rows ) ),
    {},
    map { ( @{$_}{@cols} ) } @rows
  );
}

sub dbh {
  return DBI->connect(
    sprintf( 'DBI:mysql:database=%s;host=%s', DB, HOST ),
    USER, PASS, { RaiseError => 1 } );
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


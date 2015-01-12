#!/usr/bin/perl
use warnings;
use strict;
use Encode;
use Text::CSV;
use utf8;

binmode(STDIN, ':encoding(utf8)');
binmode(STDOUT, ':encoding(utf8)');
binmode(STDERR, ':encoding(utf8)');

my $fs_7z = "/tmp/fs-update/archives/apf_apn_ten-20150107T2034.7z";
my $work_path = "/tmp/fs-update";

my $unpack_path = $fs_7z;
$unpack_path =~ s/^.*\///;
$unpack_path =~ s/\.7z$//;
$unpack_path = "$work_path/$unpack_path";

unpack_7z($fs_7z, $unpack_path);

exit;
my @rows;
my $csv = Text::CSV->new({binary => 1})  # should set binary attribute.
	or die "Cannot use CSV: ".Text::CSV->error_diag();

open my $fh, "<:encoding(utf8)", "/tmp/fs_update/apf_apn_ten-20150107T2034/filelist-20150107T2034.csv" or die "test.csv: $!";
while (my $row = $csv->getline($fh)) {
	$row->[2] =~ m/Del/ or next; # 3rd field should match
	push @rows, $row;
}
$csv->eof or $csv->error_diag();
close $fh;

$csv->eol("\r\n");

foreach my $tmp (@rows) {
	print "$tmp->[0]/$tmp->[1]\n"
}

sub unpack_7z {
	my $f_7z = shift;
	my $d_tg = shift;

	print "Unpacking...";
	`rm -rf $d_tg`;
	`7z x -o"$d_tg" "$f_7z"`;
	print "\n";
}

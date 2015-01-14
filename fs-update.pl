#!/usr/bin/perl
use warnings;
use strict;
use Getopt::Long;
use Encode;
use Text::CSV;
use utf8;

binmode(STDIN,  ':encoding(utf8)');
binmode(STDOUT, ':encoding(utf8)');
binmode(STDERR, ':encoding(utf8)');

my $fs_root = '/media/10.1.42.140/機種統括/apf_apn_ten/apf_apn_ten_fs/';
my $work_path = '/tmp/fs-update';

my $exception = {
	warning => {
		Del => [
			'', # For folders on root.
		],
	},
	ignore => [
		'40_10_ソフト/soft',
	],
};

$| = 1;
my $check = 0;
my $file_7z = '';
my $extract = 0;
GetOptions (
    'c|check' => \$check,
    't|file=s' => \$file_7z,
    'x|extract' => \$extract,
);

my $chk_act = {
	None => {
		base => 1,
		diff => 0,
	},
	Del => {
		base => 1,
		diff => 0,
		deed => 'rm -rf BASE',
	},
	Modify => {
		base => 1,
		diff => 2,
		deed => 'cp -r DIFF BASE',
	},
	New => {
		base => 0,
		diff => 1,
		deed => 'cp -r DIFF BASE',
	},
};

my $check_ok = 'check_ok_TTAG.sh';

(-e $fs_root) or die "Cannot found `$file_7z'.\n";
(-e $work_path) or die "Cannot found `$file_7z'.\n";
(-e $file_7z) or die "Cannot found `$file_7z'.\n";

if ($check) {
	my $unpack_path = $file_7z;
	$unpack_path =~ s/^.*\///;
	$unpack_path =~ s/\.7z$//;
	my $time_tag = $unpack_path;
	$unpack_path = "$work_path/$unpack_path";
	$time_tag =~ s/.*-//;
	my $filelist_csv = "$unpack_path/filelist-${time_tag}.csv";
	$check_ok =~ s/TTAG/$time_tag/;

	`rm -rf $check_ok*`;

	if ($extract) {
		unpack_7z($file_7z, $unpack_path);
	}

	print 'Parsing csv ...';
	my %types;
	my $csv = Text::CSV->new({binary => 1})  # should set binary attribute.
		or die "Cannot use CSV: ".Text::CSV->error_diag();

	open my $fh, "<:encoding(utf8)", "$filelist_csv" or die "$filelist_csv: $!";
	my $row_nu = 0;
	while (my $row = $csv->getline($fh)) {
		if ($row_nu++) {
			my $type = $row->[2];
			if (!defined $types{$type}) {
				$types{$type} = [];
			}

			push @{$types{$type}}, [$row, $row_nu];
		}
	}
	$csv->eof or $csv->error_diag();
	close $fh;
	$csv->eol("\r\n");
	print "\n";

	my @actions;
	my $err_suffix = '';
	foreach my $type (keys %types) {
		print "Parsing $type...";
		foreach my $row (@{$types{$type}}) {
			my ($_rown, $_path, $_file) =
				($row->[1], $row->[0]->[0], $row->[0]->[1]);
			my $ret = item_check(\@actions, $fs_root, $unpack_path, 
				$type, $row->[0]->[0], $row->[0]->[1]);
			$err_suffix = '.need_fix' if $ret;
			$actions[-1] .= " # $_rown - $ret";
		}
		print "\n";
	}

	open my $ofh, "> $check_ok$err_suffix";
	binmode($ofh, ':encoding(utf8)');
	print $ofh "#!/bin/bash\n";
	print $ofh join "\n", @actions;
	close $ofh;
}
else {
	if (! -e $check_ok) {
		print "Run --check frist.\n";
	}
}

sub unpack_7z {
	my $f_7z = shift;
	my $d_tg = shift;

	print "Unpacking...";
	`rm -rf $d_tg`;
	`7z x -o"$d_tg" "$f_7z"`;
	print "\n";
}

sub item_check {
	my $_actn = shift;
	my $_base = shift;
	my $_diff = shift;
	my $_type = shift;
	my $_path = shift;
	my $_file = shift;

	my $base_file = "$_base/$_path/$_file";
	my $diff_file = "$_diff/$_path/$_file";

	my @err;
	if (defined $chk_act->{$_type}) {
		foreach my $ign (@{$exception->{ignore}}) {
			my $_path_file = $_file ? "$_path/${_file}" : $_path;
			$_path_file =~ s/^\/*//;
			$_path_file =~ s/\/*$//;
			if ($_path_file =~ m/^${ign}/) {
				push @err, 106; # Ignore file exists in csv.
			}
		}

		if (defined $exception->{warning}->{$_type}) {
			my $_path_file = $_file ? "$_path/${_file}" : $_path;
			$_path_file =~ s/^\/*//;
			$_path_file =~ s/\/*$//;

			foreach my $wtp (@{$exception->{warning}->{$_type}}) {
				if ($wtp eq '' && $_path_file !~ m{/}) {
					push @err, 107; # Warning on root folder.
				}

				if ($_path_file =~ m/^${wtp}/) {
					push @err, 108; # Warning on specify file/folder.
				}
			}
		}

		if ($chk_act->{$_type}->{base} && ! -e $base_file) {
			push @err, 101; # Base file no exists.
		}
		elsif (!$chk_act->{$_type}->{base} && -e $base_file) {
			push @err, 102; # Base file exists.
		}

		if ($chk_act->{$_type}->{diff} && ! -e $diff_file) {
			push @err, 103; # Diff file no exists.
		}
		elsif (!$chk_act->{$_type}->{diff} && -e $diff_file) {
			push @err, 104 if ($_file); # Diff file exists (except folder).
		}

		if ($chk_act->{$_type}->{base} && $chk_act->{$_type}->{diff}) {
			if ($_file) {
				my $diff_rst = `diff "$base_file" "$diff_file"`;
				if (!$diff_rst) {
					push @err, 105; # Base/Diff file no difference (except folder).
				}
			}
		}
	}
	else {
		push @err, 100; # Type no defined.
	}

	if (defined $chk_act->{$_type}->{deed}) {
		my $action = $chk_act->{$_type}->{deed};
		$action =~ s/DIFF/${diff_file}/g;
		$action =~ s/BASE/${base_file}/g;
		$action = @err ? "#W $action": $action;

		# print $action."\n";
		push @$_actn, $action;
	}
	else {
		push @$_actn, @err ? '#W ': '# ';
	}

	return @err ? join '+', @err : 0;
}

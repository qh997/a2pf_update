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
$| = 1;

my %conf = get_config('settings.conf');
my $fs_root = $conf{'fileserver-root'};
my $work_root = $0;
$work_root =~ s%.*/(.*)\.pl%$1%;
$work_root = $conf{'work-root'}.'/'.$work_root;
my $archive_root = $work_root.'/'.$conf{'zips-path'};
my $log_root = $work_root.'/'.$conf{'log-path'};

my $exception = {
	warning => {
		Del => [
			qr#^[^/]+$#, # For folders on root.
			qr#^[^/]+/[^/]+$#, # For folders on root.
		],
	},
	ignore => {
		ALL => [
			qr#^40_10_ソフト/soft/?$#,
		],
	},
};

my $chk_act = {
	None => {
		base => -1,
		diff => -1,
	},
	Del => {
		base => -1,
		diff => 0,
		deed => 'rm -rf \'BASE\'',
	},
	Modify => {
		base => -1,
		diff => 2,
		deed => 'mkdir -p \'BASE/../\'; cp -r \'DIFF\' \'BASE/../\'',
	},
	New => {
		base => -1,
		diff => 1,
		deed => 'mkdir -p \'BASE/../\'; cp -r \'DIFF\' \'BASE/../\'',
	},
};

my $check = 0;
my $file_7z = '';
GetOptions (
	'c|check' => \$check,
	'f|file=s' => \$file_7z,
);

`mkdir -p $log_root` if (! -d $log_root);
my $prefix_chkok = 'check_ok';
my $perfix_done = 'accomplished';

(-e $fs_root) or die "Cannot found `$fs_root'.\n";
(-e $work_root) or die "Cannot found `$work_root'.\n";

my @file_7zs;
if ($file_7z) {
	push @file_7zs, $file_7z;
}
else {
	push @file_7zs, get_7z_file($archive_root);
}

if (! @file_7zs) {
	print "There is nothing to do.\n";
	print "Or you can specify a file manually:\n";
	print "    `$0 -f example.7z -c -x'\n";
	exit;
}

my $still_w = 0;
my @act_files;
foreach $file_7z (@file_7zs) {
	my $check_ok = $log_root."/${prefix_chkok}_TTAG.sh";
	my $unpack_path = $file_7z;
	$unpack_path =~ s/^.*\///;
	print "Working on `$unpack_path'\n";
	$unpack_path =~ s/\.7z$//;
	my $time_tag = $unpack_path;
	$unpack_path = "$work_root/$unpack_path";
	$time_tag =~ s/.*-//;
	$check_ok =~ s/TTAG/$time_tag/;
	my $err_suffix = '.need_fix';

	if ($check) {
		my $filelist_csv = "$unpack_path/filelist-${time_tag}.csv";

		`rm -rf $check_ok*`;
		`rm -rf $unpack_path`;

		unpack_7z($file_7z, $unpack_path);

		print 'Parsing csv ...';
		my %types;
		my $csv = Text::CSV->new({binary => 1})  # should set binary attribute.
			or die "Cannot use CSV: ".Text::CSV->error_diag();

		open my $fh, "<:encoding(utf8)", "$filelist_csv" or die "\n$filelist_csv: $!";
		my $row_nu = 0;
		while (my $row = $csv->getline($fh)) {
			if ($row_nu++) {
				my $type = $row->[2];
				# next if $type eq 'None';
				# next if $type eq 'Del';
				# next if $type eq 'Modify';
				# next if $type eq 'New';
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
		my $_err_suffix = '';
		foreach my $type (keys %types) {
			print "Parsing $type...";
			foreach my $row (@{$types{$type}}) {
				my ($_rown, $_path, $_file) =
					($row->[1], $row->[0]->[0], $row->[0]->[1]);
				my $ret = item_check(\@actions, $fs_root, $unpack_path, 
					$type, $row->[0]->[0], $row->[0]->[1]);
				$_err_suffix = $err_suffix if $ret;
				$actions[-1] .= " # $_rown($type) - $ret";
			}
			print "\n";
		}

		open my $ofh, "> $check_ok$_err_suffix";
		binmode($ofh, ':encoding(utf8)');
		print $ofh "#!/bin/bash -ex\n";
		print $ofh join "\n", @actions;
		print $ofh "\n";
		close $ofh;

		if ($_err_suffix) {
			print " - ********** WARNING **********\n";
			print " - There are some warnings should be fixed.\n";
			print " - Frist check the script `vim $check_ok$err_suffix'.\n";
			print " -   Find the lines which start with `#W', and fix those warning lines.\n";
			print " - Second `mv $check_ok$err_suffix $check_ok'\n";
			print " - Then `$0'\n";
		}
	}
	else {
		if (-e "${check_ok}${err_suffix}") {
			print "The warnings are already fixed?\n";
			print "    `vim $check_ok$err_suffix'\n";
			print "Or you just forget run this command:\n";
			print "    `mv $check_ok$err_suffix $check_ok'\n";
			$still_w = 1;
		}
		elsif (! -e $check_ok) {
			print "Run `$0 --check' frist.\n";
			$still_w = 1;
		}
		else {
			push @act_files, $check_ok;
		}
	}

	print '=' x 57, "\n";
}

exit if $check;

if ($still_w) {
	print "\n";
	print " *************** FINAL WARNING **************\n";
	print " * There still detected something abnormal. *\n";
	print " * I cannot let you go on.                  *\n";
	print " * Please be sure to fix them.              *\n";
	print " ********************************************\n";
	exit;
}
else {
	print "OK, let's do it.\n";
	foreach my $act_f (@act_files) {
		chmod 0744, $act_f;

		print "\n\$ $act_f\n";
		my $ret_value = system("$act_f 2>&1 | tee cmd.log");
		chmod 0644, $act_f;
		my $ret = `cat cmd.log`;
		`rm -rf cmd.log`;

		system('sed', '-i', '1s/#!.*/# "DO NOT RUN THIS SCRIPT!!"/', "$act_f");
		system('sed', '-i', '2iexit', "$act_f");

		my $log_file = $act_f;
		$log_file =~ s%${prefix_chkok}%${perfix_done}%;
		$log_file =~ s%\.sh%.log%;
		rename $act_f, $log_file;

		open my $lfh, ">> $log_file";
		print $lfh "\n", '#' x 27;
		print $lfh " LOG ", '#' x 27, "\n";
		print $lfh $ret;
		close $lfh;
	}

	`chown -R nobody:nogroup "$fs_root"`;
	`chmod -R 777 "$fs_root"`;

	`mail-maker -s fs-update -f`;
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
		if (defined $exception->{ignore}->{ALL} || defined $exception->{ignore}->{$_type}) {
			my @_ign_list;
			push @_ign_list, @{$exception->{ignore}->{ALL}}
				if defined $exception->{ignore}->{ALL};
			push @_ign_list, @{$exception->{ignore}->{$_type}}
				if defined $exception->{ignore}->{$_type};

			foreach my $ign (@_ign_list) {
				my $_path_file = $_file ? "$_path/${_file}" : $_path;
				$_path_file =~ s/^\/*//;
				$_path_file =~ s/\/*$//;
				if ($_path_file =~ $ign) {
					push @err, 202; # Ignore file exists in csv.
				}
			}
		}

		if (defined $exception->{warning}->{$_type}) {
			my $_path_file = $_file ? "$_path/${_file}" : $_path;
			$_path_file =~ s/^\/*//;
			$_path_file =~ s/\/*$//;

			foreach my $wtp (@{$exception->{warning}->{$_type}}) {
				if ($_path_file =~ $wtp) {
					push @err, 201; # Warning on specify file/folder.
				}
			}
		}

		if ($chk_act->{$_type}->{base} != -1) {
			if ($chk_act->{$_type}->{base} && ! -e $base_file) {
				push @err, 101; # Base file no exists.
			}
			elsif (!$chk_act->{$_type}->{base} && -e $base_file) {
				push @err, 102; # Base file exists.
			}
		}

		if ($chk_act->{$_type}->{diff} != -1) {
			if ($chk_act->{$_type}->{diff} && ! -e $diff_file) {
				push @err, 103; # Diff file no exists.
			}
			elsif (!$chk_act->{$_type}->{diff} && -e $diff_file) {
				push @err, 104 if ($_file); # Diff file exists (except folder).
			}
		}

		if ($chk_act->{$_type}->{base} != -1 && $chk_act->{$_type}->{diff} != -1) {
			if ($chk_act->{$_type}->{base} && $chk_act->{$_type}->{diff}) {
				if ($_file) {
					my $diff_rst = `diff "$base_file" "$diff_file"`;
					if (!$diff_rst) {
						push @err, 105; # Base/Diff file no difference (except folder).
					}
				}
			}
		}
	}
	else {
		push @err, 100; # Type no defined.
	}

	if (defined $chk_act->{$_type}->{deed}) {
		my $action = $chk_act->{$_type}->{deed};
		$diff_file =~ s#'#'"'"'#;
		$base_file =~ s#'#'"'"'#;
		$action =~ s/DIFF/${diff_file}/g;
		$action =~ s/BASE/${base_file}/g;
		$action = @err ? "#W $action": $action;
		$action =~ s%[^/]+/+\.\./+%%g;

		# print $action."\n";
		push @$_actn, $action;
	}
	else {
		push @$_actn, @err ? '#W ': '# ';
	}

	return @err ? join '+', @err : 0;
}

sub get_config {
	my $config_file = shift;

	open my $CF, "< $config_file" or die 'cannot open file : '.$config_file;
	my @file_content = <$CF>;
	close $CF;

	my %configs;
	foreach my $line (@file_content) {
		chomp $line;

		next if $line =~ m/^\s*#/;
		next if $line !~ m/=/;

		if ($line =~ m{^\s*(.*?)\s*=\s*(.*)\s*$}) {
			$configs{$1} = $2;
		}
	}

	return %configs;
}

sub get_7z_file {
	my $arch_path = shift;

	my @arch_list = `ls $archive_root/* | sort -r`;
	if ($?) {
		return ();
	}

	my @todo_list;
	foreach my $_arch (@arch_list) {
		chomp $_arch;
		my $time_tag = $_arch;
		$time_tag =~ s/.*-//;
		$time_tag =~ s/\.7z$//;

		if (-f "${log_root}/${perfix_done}_${time_tag}.log") {
			last;
		}
		else {
			print "To be update: $_arch\n";
			unshift @todo_list, $_arch;
		}
	}

	print '-' x 57 ,"\n";
	return @todo_list;
}

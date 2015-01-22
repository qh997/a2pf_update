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

my $work_root = $0;
$work_root =~ s%.*/(.*)\.pl%$1%;
$work_root = $conf{'work-root'}.'/'.$work_root;
my $zips_root = $work_root.'/'.$conf{'zips-path'};
my $log_root = $work_root.'/'.$conf{'log-path'};

`mkdir -p -m 0755 $zips_root`;
`mkdir -p -m 0755 $log_root`;

my $check = 0;
GetOptions (
    'c|check' => \$check,
    'p|zips-path=s' => \$zips_root,
);

my $svn_repo = {
	doc => {
		url => $conf{'url-doc'},
		repo => '',
		ver => 0,
		verto => 0,
		zips => [],
	},
	src => {
		url => $conf{'url-src'},
		repo => '',
		ver => 0,
		verto => 0,
		zips => [],
	},
};

my @need_fix;
my $err_suffix = '.need_fix';
my $check_ok = 'check_ok_TYPE.sh';
if ($check) {
	foreach my $type (keys %$svn_repo) {
		my $_chk_ok = $check_ok;
		$_chk_ok =~ s/TYPE/$type/;
		`rm -rf $log_root/${_chk_ok}*`;
	}
}
else {
	my @acts;
	my $err = 0;
	foreach my $type (keys %$svn_repo) {
		my $_chk_ok = $check_ok;
		$_chk_ok =~ s/TYPE/$type/;
		$_chk_ok = "${log_root}/${_chk_ok}";

		if (-e "${_chk_ok}${err_suffix}") {
			$err |= 1;
		}
		elsif (! -e "${_chk_ok}") {
			$err |= 2;
		}
		else {
			push @acts, $_chk_ok;
		}
	}

	if ($err & 1) {
		print "Frist, you must fix the warnings.\n";
		print "Second, remove the suffix `${err_suffix}'.\n";
	}
	elsif ($err & 2) {
		print "Please run with -c|--check frist.\n";
	}
	else {
		print "OK, let's do it.\n";

		foreach my $act (@acts) {
			chmod 0744, $act;

			print "\n\$ $act\n";
			my $ret_value = system("$act 2>&1 | tee cmd.log");
			chmod 0644, $act;
			my $ret = `cat cmd.log`;
			`rm -rf cmd.log`;

			my $id = `cat $act | sed -n '2p'`;
			$id =~ s/^#\s+(\w+)\s+(\d+)\s+->\s+(\d+).*$/$1-$2-$3/;
			chomp $id;

			my $log_file = $act;
			$log_file =~ s%(.*/).*%$1%;
			$log_file .= "$id.log";
			rename $act, $log_file;

			open my $lfh, ">> $log_file";
			print $lfh "\n", '#' x 27;
			print $lfh " LOG ", '#' x 27, "\n";
			print $lfh $ret;
			close $lfh;
		}
	}

	exit;
}

(-e $work_root) or die "Cannot found `$work_root'.\n";
(-e $zips_root) or die "Cannot found `$zips_root'.\n";

foreach my $type (keys %$svn_repo) {
	$svn_repo->{$type}->{ver} = get_version($svn_repo->{$type}->{url});
	if ($svn_repo->{$type}->{ver} == 0) {
		print "ERROR - Cannot get the get the svn version of `$type'\n";
	}
}

opendir(my $adh, $zips_root) or die "can't opendir $zips_root: $!";
my @zips = grep {-f "$zips_root/$_"} readdir($adh);
closedir $adh;

foreach my $zip_file (@zips) {
	my $types = join '|', keys %$svn_repo;
	if ($zip_file !~ m/^($types)-incrementalbackup-\d{8}T\d{4}-(\d+)-(\d+)\.7z/) {
		warning("File name of `$zip_file' in path `$zips_root' are not meet the standard.");
	}
}

# Get the order for update.
foreach my $type (keys %$svn_repo) {
	my @t_zips = grep {/^($type)-incrementalbackup-\d{8}T\d{4}-(\d+)-(\d+)\.7z$/} @zips;

	while (1) {
		my $found = 0;
		my @faultage;
		foreach my $t_7z (@t_zips) {
			my $vir_ver = $svn_repo->{$type}->{'verto'}
				? $svn_repo->{$type}->{'verto'} : $svn_repo->{$type}->{'ver'};

			if ($t_7z =~ m/^${type}-incrementalbackup-\d{8}T\d{4}-(\d+)-(\d+)\.7z/) {
				my ($ver_beg, $ver_end) = ($1, $2);
				if ($vir_ver + 1 == $ver_beg) {
					push @{$svn_repo->{$type}->{zips}}, $t_7z;
					$svn_repo->{$type}->{'verto'} = $ver_end;
					$found = 1;
				}
				elsif ($vir_ver + 1 < $ver_beg) {
					push @faultage, $t_7z;
				}
			}
		}

		if (!$found) {
			grep {warning("$type Faultage: $_")} @faultage;
			last;
		}
	}
}

# Check md5sum and generate the command sscript.
foreach my $type (keys %$svn_repo) {
	my @actions;
	print "Prepare update $type:\n";

	$svn_repo->{$type}->{repo} = defined $conf{"repo-$type"}
		? $conf{"repo-$type"} : '';

	foreach my $zip_file (@{$svn_repo->{$type}->{zips}}) {
		my $sign = $zip_file;
		$sign =~ s/^.*\///;
		$sign =~ s/\.7z$//;

		unpack_7z("$zips_root/$zip_file", "$work_root/$sign");

		if (!md5sum_check("$work_root/$sign/$sign.md5")) {
			print "`$sign' md5sum check passed.\n";
			my $repo_root = $svn_repo->{$type}->{repo};
			my $action = "svnadmin load \"$repo_root\" < \"$work_root/$sign/$sign\"";

			if (!$repo_root || !-d $repo_root) {
				$action = '#W '.$action.' # repository error';
				warning("Cannot found repository`$repo_root' for $type.");
			}
			push @actions, $action;
		}
	}

	if (@actions) {
		my $chkok_file = $check_ok;
		$chkok_file =~ s/TYPE/$type/;
		$chkok_file = "$log_root/$chkok_file";
		$err_suffix = @need_fix ? '.need_fix' : '';

		print "Building `$chkok_file$err_suffix'.\n";
		open my $ofh, "> $chkok_file$err_suffix";
		binmode($ofh, ':encoding(utf8)');
		print $ofh "#!/bin/bash -ex\n";
		print $ofh "# $type ",$svn_repo->{$type}->{'ver'} + 1," -> $svn_repo->{$type}->{'verto'}\n";
		print $ofh join "\n", @actions;
		print $ofh "\n";
		close $ofh;

		print "\n";
	}
}

sub unpack_7z {
	my $f_7z = shift;
	my $d_tg = shift;

	print "Unpacking `$f_7z'...";
	`rm -rf $d_tg`;
	`7z x -o"$d_tg" "$f_7z"`;
	print "\n";
}

sub md5sum_check {
	my $md5_file = shift;
	my $md5_path = $md5_file;

	$md5_file =~ s%.*/%%;
	$md5_path =~ s%(.*)/.*%$1%;

	my $str_rst = `cd $md5_path; md5sum -c $md5_file`;
	my $rst = $?;

	warning("$md5_file check failed.") if $rst;

	return $rst;
}

sub get_version {
	my $url = shift;

	my @_ver = `svn log -l1 -q $conf{'svn-cer'} "$url"`;
	my $retval = $?;

	if ($retval) {
		return 0;
	}
	else {
		my $crt_vet = (split(/\|/, $_ver[1]))[0];
		$crt_vet =~ s/^\s+//;
		$crt_vet =~ s/\s+$//;
		$crt_vet =~ s/^r//;
		return "${crt_vet}"
	}
}

sub warning {
	my $str = shift;

	push @need_fix, $str;
	print "WARNING - $str\n";
}

sub get_config {
	my $config_file = shift;

	open my $CF, "< $config_file" or die 'cannot open file : '.$config_file;
	my @file_content = <$CF>;
	close $CF;

	my %configs;
	foreach my $line (@file_content) {
		chomp $line;

		if ($line =~ m{^\s*(.*?)\s*=\s*(.*)\s*$}) {
			$configs{$1} = $2;
		}
	}

	return %configs;
}

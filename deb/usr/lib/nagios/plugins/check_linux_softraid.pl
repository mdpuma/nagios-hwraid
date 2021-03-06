#!/usr/bin/perl -w
# vim:ts=4
#
# Check RAID status.  Look for any known types
# of RAID configurations, and check them all.
# Return CRITICAL if in a DEGRADED state, since
# if the whole array has failed you'll have already noticed it!
# Return UNKNOWN if there are no RAID configs that can be found.
#
# S Shipway, university of auckland

use strict;
use Getopt::Long;
use vars qw($opt_v $opt_d $opt_h $opt_W $opt_S);
my(%ERRORS) = ( OK=>0, WARNING=>1, CRITICAL=>2, UNKNOWN=>3, WARN=>1, CRIT=>2 );
my($message, $status);
my(@ignore);
#####################################################################
sub print_usage () {
	print "Usage: check_raid [list of devices to ignore]\n";
	print "       check_raid -v\n";
	print "       check_raid -h\n";
}

sub print_help () {
	print "check_raid, Revision: 0.1 \n";
	print "Copyright (c) 2004 S Shipway
This plugin reports the current server's RAID status
";
	print_usage();
}

#####################################################################
# return true if parameter is not in ignore list
sub valid($) {
	my($v) = $_[0];
	$v = lc $v;
	foreach ( @ignore ) { return 0 if((lc $_) eq $v); }
	return 1;
}
#####################################################################
sub check_metastat {
	my($l,$s,$d,$sd);

	open METASTAT,"/usr/sbin/metastat |" or return;
	while( $l = <METASTAT> ) {
		chomp $l;
		if($l =~ /^(\S+):/) { $d = $1; $sd = ''; next; }
		if($l =~ /Submirror \d+:\s+(\S+)/) { $sd = $1; next; }
		if($l =~ /State: (\S.+)/) { $s = $1; 
			if($sd and valid($sd) and valid($d)) {
				if($s =~ /Okay/i) {
					# no worries...
				} elsif($s =~ /Resync/i) {
					$status = $ERRORS{WARNING} if(!$status);
				} else {
					$status = $ERRORS{ERROR};
				}
				$message .= "$d:$sd:$s ";
			}
		}
	}
	close METASTAT;
}
sub check_megaide { 
	my($f,$l);
	my($s,$n);
	my($CMD);

	foreach $f ( glob('/proc/megaide/*/status') ) {
		if( -r $f ) { $CMD = "<$f"; }
		else { $CMD = "sudo cat $f |"; }
		open MEGAIDE,$CMD or next;
		while( $l = <MEGAIDE> ) {
			if( $l =~ /Status\s*:\s*(\S+).*Logical Drive.*:\s*(\d+)/i ) {
				($s,$n)=($1,$2);
				next if(!valid($n));
				if($s ne 'ONLINE') {
					$status = $ERRORS{CRITICAL};
					$message .= "Megaide:$n:$s ";
				} else {
					$message .= "Megaide:$n:$s ";
				}
				last;
			}
		}
		close MEGAIDE;
	}
}
sub check_mdstat {
	my($l);
	my($s,$n,$f,$sync);

	open MDSTAT,"</proc/mdstat" or return;
	while( $l = <MDSTAT> ) {
		# print("L:$l S:$s N: $n F: $f Syn: $sync\n");
		if( $l =~ /^(\S+)\s+:/ ) { $n = $1; $f = ''; $sync = ''; next; } # find md dev
		if( $l =~ /(\S+)\[\d+\]\(F\)/ ) { $f = $1; next; } # find failed
		if( $l =~ /\s*.*\[([U_]+)\]/ ) { $s = $1; next; }
    		if( $l =~ /.*\s([\d\.%]+)\s.*finish=(.*min)/ ) { $sync=":sync:$1:$2"; next; }
		if( $l =~ /^\s*$/ )
		{
			next if(!valid($n));
			if($s =~ /_/ ) {
				$status = $ERRORS{CRITICAL};
				$message .= "md:$n:$f:$s$sync ";
				# print("Msg:$message\n");
			} else {
				$status = $ERRORS{WARNING} 
				  if ($sync ne '' && $status != $ERRORS{CRITICAL});
				$message .= "md:$n:$s$sync ";
				# print("Msg:$message\n");
			}
		}
	}
	close MDSTAT;
}
sub check_lsraid {
	my($l);
	my($s,$n,$f);

	open LSRAID,"/sbin/lsraid -A -p |" or return;
	while( $l = <LSRAID> ) {
		chomp $l;
		if( $l =~ /\/dev\/(\S+) \S+ (\S+)/ ) {
			($n,$s) = ($1,$2);
			next if(!valid($n));
			if($s =~ /good|online/ ) { # no worries 
			} elsif($s =~ /sync/ ) { 
				$status = $ERRORS{WARNING} if(!$status); 
			} else { $status = $ERRORS{CRITICAL}; }
			$message .= "md:$n:$s ";
		}
	}
	close MDSTAT;
}
sub check_vg {
	my(@vg, $vg);
	my($l,@f);
	my($s,$n,$f);

	open LSVG,"/usr/sbin/lsvg |" or return;
	while( $l = <LSVG> ) { chomp $l; push @vg, $l; }
	close LSVG;
	foreach $vg ( @vg ) {
		next if(!valid($vg)); # skip entire VG
		open LSVG,"/usr/sbin/lsvg -l $vg |" or return;
		while( $l = <LSVG> ) { 
			@f = split " ",$l;
			($n,$s) = ($f[0],$f[5]);
			next if(!valid($n) or !$s);	
			next if( $f[3] eq $f[2] ); # not a mirrored LV
			if( $s =~ /open\/(\S+)/i ) {
				$s = $1;
				if( $s ne 'syncd' ) { $status = $ERRORS{CRITICAL}; }
				$message .= "lvm:$n:$s ";
			}
		}
		close LSVG;
	}
}
sub check_ips {
	my($l,@f);
	my($s,$n,$c);
	my($CMD);

	$CMD = "/usr/local/bin/ipssend getconfig 1 LD";
	$CMD = "sudo $CMD" if( $> );

	open IPS,"$CMD |" or return;
	while( $l = <IPS> ) { 
		chomp $l; 
		if( $l =~ /drive number (\d+)/i ) { $n = $1; next; }
		next if(!valid($n));	
		if( $l =~ /Status .*: (\S+)\s+(\S+)/ ) {
			($s,$c) = ($1,$2);
			if( $c =~ /SYN/i ) { # resynching
				$status = $ERRORS{WARNING} if(!$status);
			} elsif( $c !~ /OKY/i ) { # not OK
				$status = $ERRORS{CRITICAL};
			}
			$message .= "ips:$n:$s ";
		}
	}
	close IPS;
}
sub sudoers {
	my($f);

	$f = '/usr/local/etc/sudoers';
	$f = '/etc/sudoers' if(! -f $f ); 
	if(! -f "$f" ) { print "Unable to find sudoers file.\n"; return; }
	if(! -w "$f" ) { print "Unable to write to sudoers file.\n"; return; }

	print "Updating file $f\n";
	open SUDOERS, ">>$f";
	print SUDOERS "ALL  ALL=(root) NOPASSWD:/usr/local/bin/ipssend getconfig 1 LD\n" if( -f "/usr/local/bin/ipssend" );
	print SUDOERS "ALL  ALL=(root) NOPASSWD:/bin/cat /proc/megaide/0/status\n" if( -d "/proc/megaide/0" );
	print SUDOERS "ALL  ALL=(root) NOPASSWD:/bin/cat /proc/megaide/1/status\n" if( -d "/proc/megaide/1" );

	close SUDOERS;
	print "sudoers file updated.\n";
}
#####################################################################
$ENV{'BASH_ENV'}=''; 
$ENV{'ENV'}='';

Getopt::Long::Configure('bundling');
GetOptions
	("v"   => \$opt_v, "version"    => \$opt_v,
	 "h"   => \$opt_h, "help"       => \$opt_h,
	 "d" => \$opt_d, "debug" => \$opt_d,
	 "S" => \$opt_S, "sudoers" => \$opt_S,
	 "W" => \$opt_W, "warnonly" => \$opt_W );

if($opt_S) {
	sudoers;
	exit 0;
}

@ignore = @ARGV if(@ARGV);

if ($opt_v) {
	print "check_raid Revision: 0.1\n" ;
	exit $ERRORS{'OK'};
}
if ($opt_h) {print_help(); exit $ERRORS{'OK'};}
if($opt_W) {
	$ERRORS{CRITICAL} = $ERRORS{WARNING};
}

$status = $ERRORS{OK}; $message = '';

check_megaide if( -d "/proc/megaide" ); # Linux, hardware RAID
check_mdstat  if( -f "/proc/mdstat" ); # Linux, software RAID
check_lsraid  if( -x "/sbin/lsraid" ); #  Linux, software RAID
check_metastat if( -x "/usr/sbin/metastat" ); # Solaris, software RAID
check_vg      if( -x "/usr/sbin/lsvg" ); # AIX LVM
check_ips     if( -x "/usr/local/bin/ipssend"  ); # Serveraid

if( $message ) {
	if( $status == $ERRORS{OK} ) {
		print "OK: ";
	} elsif( $status == $ERRORS{WARNING} ) {
		print "WARNING: ";
	} elsif( $status == $ERRORS{CRITICAL} ) {
		print "CRITICAL: ";
	}
	print "$message\n";
} else {
	print "No RAID configuration found.\n";
}
exit $status;

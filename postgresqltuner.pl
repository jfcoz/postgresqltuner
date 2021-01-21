#!/usr/bin/env perl

# The postgresqltuner.pl is Copyright (C) 2016-2019 Julien Francoz <julien-postgresqltuner@francoz.net>,
# https://github.com/jfcoz/postgresqltuner
#
# new relase :
#   wget postgresqltuner.pl
#
# postgresqltuner.pl is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# postgresqltuner.pl is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with postgresqltuner.pl.  If not, see <http://www.gnu.org/licenses/>.
#

#todo: for each major parameter create a code block reserved to a PG version
#todo: thx to PG stats obtain the amount of active data, selects, updates, deletes... and mix/match it with PG parameters, esp. (WAL and cache)-related
#todo: not vacuum'ed tables (in need of it)

use strict;
use warnings;
use Config;

my $os={};
$os->{name}=$Config{osname};
$os->{arch}=$Config{archname};
$os->{version}=$Config{osvers};

#$SIG{__WARN__} = sub { die @_ };

my $nmmc=0; # needed missing modules count
$nmmc+=try_load("Getopt::Long",{});
$nmmc+=try_load("DBD::Pg",
	{
    '/usr/local/bin/cpan' => 'cpan DBD:Pg',
		'/etc/debian_version'=>'apt-get install -y libdbd-pg-perl',
		'/etc/redhat-release'=>'yum install -y perl-DBD-Pg'
	});
$nmmc+=try_load("DBI",
	{
    '/usr/local/bin/cpan' => 'cpan DBI',
		'/etc/debian_version'=>'apt-get install -y libdbi-perl',
		'/etc/redhat-release'=>'yum install -y perl-DBI'
	});
$nmmc+=try_load("Term::ANSIColor",
	{
    '/usr/local/bin/cpan' => 'cpan install Term::ANSIColor',
		'/etc/debian_version'=>'apt-get install -y perl-modules',
		'/etc/redhat-release'=>'yum install -y perl-Term-ANSIColor'
	});
if ($nmmc > 0) {
	die "# Please install any missing Perl module";
}

my $script_version="1.0.1";
my $script_name="postgresqltuner.pl";
my $min_s=60;
my $hour_s=60*$min_s;
my $day_s=24*$hour_s;

my $host=undef; # at declaration time assigning to undef seems useless to me (perl -e 'my $host; print "OK\n" if (! defined $host);' ) , is it necessary on a given environment?
my $username=undef;
my $password=undef;
my $database=undef;
my $port=undef;
my $pgpassfile=$ENV{HOME}.'/.pgpass';
my $help=0;
my $work_mem_per_connection_percent=150;
my @Ssh_opts=('BatchMode=yes');
my $ssh_user=undef;
my $ssd=0;
my $nocolor=0;
my $skip_ssh=0;
my $memory=undef;

# functions prototypes (the perl interpreter will enforce them)
# todo: enforce each and every non varargs function, iff jfcoz accepts it
sub preserve_only_digits($);
sub min_version($);

GetOptions (
	"host=s"      => \$host,
	"user=s"      => \$username,
	"username=s"  => \$username,
	"pass:s"      => \$password,
	"password:s"  => \$password,
	"db=s"        => \$database,
	"database=s"  => \$database,
	"port=i"      => \$port,
	"help"        => \$help,
	"wmp=i"       => \$work_mem_per_connection_percent,
	"sshopt=s"    => \@Ssh_opts,
	"sshuser=s"   => \$ssh_user,
	"ssd"         => \$ssd,
	"nocolor"     => \$nocolor,
	"skip-ssh"    => \$skip_ssh,
	"memory"      => \$memory,
	#todo: option --dedicated, refined as a percentage (100:full dedicated, 50: half...).  Refinement: dedication per resource (storage, RAM, CPU...)
	#todo: option --interactive
	) or usage(1);

$ENV{"ANSI_COLORS_DISABLED"}=1 if $nocolor;

print "$script_name version $script_version\n";
usage(0) if ($help);

# ssh options
my $ssh_opts='';
foreach my $ssh_opt (@Ssh_opts) {
	$ssh_opts.=' -o '.$ssh_opt;
}

# host
if (!defined($host)) {
	if (defined($ENV{PGHOST})) {
		$host=$ENV{PGHOST};
	} else {
		$host='/var/run/postgresql';
	}
}

# port
if (!defined($port)) {
	if (defined($ENV{PGPORT})) {
		$port=$ENV{PGPORT};
	} else {
		$port=5432;
	}
}

# database
if (!defined($database)) {
	if (defined($ENV{PGDATABASE})) {
		$database=$ENV{PGDATABASE};
	} else {
		$database='template1';
	}
}

# user
if (!defined($username)) {
	if (defined($ENV{PGUSER})) {
		$username=$ENV{PGUSER};
	} else {
		$username='postgres';
	}
}

# if needed, get password from ~/.pgpass
if (!defined($password)) {
	if (defined($ENV{PGPASSWORD})) {
		$password=$ENV{PGPASSWORD};
	} else {
		if (defined($ENV{PGPASSFILE})) {
			$pgpassfile=$ENV{PGPASSFILE};
		}
	}

	if (open(PGPASS,'<',$pgpassfile))
    {
		while (my $line=<PGPASS>) {
			chomp($line);
			next if $line =~ /^\s*#/;
			my ($pgp_host,$pgp_port,$pgp_database,$pgp_username,$pgp_password,$pgp_more)=split(/(?<!\\):/,$line); # split except after escape char
			next if (!defined($pgp_password) or defined($pgp_more)); # skip malformated line
			next if (!pgpass_match('host',$host,$pgp_host));
			next if (!pgpass_match('port',$port,$pgp_port));
			next if (!pgpass_match('database',$database,$pgp_database));
			next if (!pgpass_match('username',$username,$pgp_username));
			$password=pgpass_unescape($pgp_password);
			last;
		}
		close(PGPASS);
	}

	# default
	if (!defined($password)) {
		$password='';
	}
}

if (!defined($host)) {
	print STDERR "Missing host\n";
	print STDERR "\tset \$PGHOST environnement variable\n";
	print STDERR "or\tadd --host option\n";
	usage(1);
}

if (!defined($username)) {
	print STDERR "Missing username\n";
	print STDERR "\tset \$PGUSER environnement variable\n";
	print STDERR "or\tadd --user option\n";
	usage(1);
}

if (!defined($password)) {
	print STDERR "Missing password\n";
	print STDERR "\tconfigure ~/.pgpass\n";
	print STDERR "or\tset \$PGPASSWORD environnement variable\n";
	print STDERR "or\tadd --password option\n";
	usage(1);
}

sub usage {
	my $return=shift;
	print STDERR "usage: $script_name --host [ hostname | /var/run/postgresql ] [--user username] [--password password] [--database database] [--port port] [--wmp 150]\n";
	print STDERR "\t[--sshopt=Name=Value]...\n";
	print STDERR "\t[--ssd]\n";
	print STDERR "... if connection parameters can be read from \$PGHOST, \$PGPORT, \$PGDATABASE, \$PGUSER, \$PGPASSWORD\n";
	print STDERR "For security reasons, please provide any password ONLY in ~/.pgpass\n";
	print STDERR "\thost:port:database:username:password\n";
	print STDERR "  --wmp: average number of work_mem buffers per connection in percent (default 150)\n";
	print STDERR "  --sshopt: pass options to ssh (example --sshopt=Port=2200)\n";
	print STDERR "  --ssd: declare all physical storage units (used by PostgreSQL) as non rotational\n";
	print STDERR "  --nocolor: do not colorize my report\n";
	exit $return;
}

# OS command check
my $os_cmd_prefix='LANG=C LC_ALL=C ';
my $can_run_os_cmd=0;
if (! $skip_ssh) {
	if ($host =~ /^\//) {
		$os_cmd_prefix='';
	} elsif ($host =~ /^localhost$/) {
		$os_cmd_prefix='';
	} elsif ($host =~ /^127\.[0-9]+\.[0-9]+\.[0-9]+$/) {
		$os_cmd_prefix='';
	} elsif ($host =~ /^::1$/) {
		$os_cmd_prefix='';
	} elsif ($host =~ /^[a-zA-Z0-9._-]+$/) {
		if (defined($ssh_user)) {
			$os_cmd_prefix="ssh $ssh_opts $ssh_user\@$host ";
		} else {
			$os_cmd_prefix="ssh $ssh_opts $host ";
		}
	} else {
		die("Invalid host '$host'");
	}
	if (defined(os_cmd("true"))) {
		$can_run_os_cmd=1;
	print_report_ok("I can invoke executables");
	} else {
	print_report_bad("I CANNOT invoke executables, my report will be incomplete");
		add_advice("reporting","high","Please configure your .ssh/config to allow postgresqltuner.pl to connect via ssh to $host without password authentication.  This will allow it to collect more system informations");
	}
}

# Database connection
print "Connecting to $host:$port database $database as user '$username'...\n";
my $dbh = DBI->connect("dbi:Pg:dbname=$database;host=$host;port=$port;",$username,$password,{AutoCommit=>1,RaiseError=>1,PrintError=>0});

system("/usr/bin/env perl -e 'use Memoize' 1>/dev/null 2>/dev/null"); # is the Perl module 'Memoize' installed?
if ( ($? >> 8) == 0) {
  use Memoize;
	memoize('get_nonvolatile_setting');
}

#todo: this will be necessary when this script will analyze DB-related activity
#print_report_warn("I will analyze the database $database.  For more complete reports please re-run me on each database")
#	if ($database =~ '^template[0-9]+$');

# Collect data
my $users=select_all_hashref("select * from pg_user","usename");
my $i_am_super=$users->{$username}->{usesuper};
my $settings=select_all_hashref("select * from pg_settings","name");
my $rotational_storage=undef;
my @Extensions;
if (min_version('9.1')) {
	@Extensions=select_one_column("select extname from pg_extension");
} else {
	print_report_warn("pg_extension does not exist in PostgreSQL version ".get_nonvolatile_setting('server_version'));
}
my %advices;

if ($i_am_super) {
	print_report_ok("The user account used by me for reporting has superuser rights on this PostgreSQL instance");
} else {
	print_report_bad("The user account used by me for reporting does not have Postgres superuser rights.  My report will be incomplete");
	add_advice("reporting","high","Use an account with Postgres superuser privileges to get a more complete report");
}

# Report
print_header_1("OS information");

{
	if (! $can_run_os_cmd) {
		print_report_unknown("Unable to run OS commands on $host.  You will obtain no OS-related information");
	} else {
		print_report_info("OS: $os->{name} Version: $os->{version} Arch: $os->{arch}");

		# OS Memory
		if ($os->{name} eq 'darwin') {
			my $os_mem=os_cmd("top -l 1 -S -n 0");
			$os->{mem_used} = standard_units($os_mem =~ /PhysMem: (\d+)([GMK])/);
			$os->{mem_free} = standard_units($os_mem =~ /(\d+)([GMK]) unused\./);
			$os->{mem_total} = $os->{mem_free} + $os->{mem_used};
			$os->{swap_used} = standard_units($os_mem =~ /Swap:\W+(\d+)([GMK])/);
			$os->{swap_free} = standard_units($os_mem =~ /Swap:\W+\d+[GMK] \+ (\d+)([GMK]) free/);
			$os->{swap_total} = $os->{swap_free} + $os->{swap_used};
		} else {
			my $os_mem="";
			if ($os->{name} =~ 'bsd')
			{
				$os_mem=os_cmd("freecolor -ob");
			}
			else
			{
				$os_mem=os_cmd("free -b");
			}
			($os->{mem_total},$os->{mem_used},$os->{mem_free},$os->{mem_shared},$os->{mem_buffers},$os->{mem_cached})=($os_mem =~ /Mem:\s+([0-9]+)\s+([0-9]+)\s+([0-9]+)\s+([0-9]+)\s+([0-9]+)\s+([0-9]+)/);
			($os->{swap_total},$os->{swap_used},$os->{swap_free})=($os_mem =~ /Swap:\s+([0-9]+)\s+([0-9]+)\s+([0-9]+)/);
		}
		undef $os->{mem_total} if ( 0 == $os->{mem_total}); # paranoid
		print_report_info("OS total memory: ".format_size($os->{mem_total})) if (defined($os->{mem_total}));

		# Overcommit
		if ($os->{name} eq 'darwin') {
			print_report_unknown("No information on memory overcommitment on MacOS");
		} else {
			my $overcommit_memory=get_sysctl('vm.overcommit_memory');
			if ($overcommit_memory != 2) {
				print_report_bad("Memory overcommitment is allowed on the system.  This may lead the OOM Killer to kill at least one PostgreSQL process, DANGER!");
				add_advice('system','high',"set vm.overcommit_memory=2 in /etc/sysctl.conf and invoke  sysctl -p /etc/sysctl.conf  to enforce it.  This will disable memory overcommitment and avoid having a PostgreSQL process killed by the OOM killer");
				my $overcommit_ratio=get_sysctl('vm.overcommit_ratio'); # expressed as a percentage
				print_report_info("sysctl vm.overcommit_ratio=$overcommit_ratio");
				if ($overcommit_ratio <= 50) {
					print_report_bad("vm.overcommit_ratio is too low, you will not be able to use more than (${overcommit_ratio}/100)*RAM+SWAP for applications");
				} elsif ($overcommit_ratio > 90) {
					print_report_bad("vm.overcommit_ratio is too high, you need to keep free memory");
				}
			} else {
				print_report_ok("vm.overcommit_memory is adequate: no memory overcommitment");
			}
		}

		# Hardware
		my $hypervisor=undef;
		if ($os->{name} ne 'darwin') {
			my $systemd = os_cmd('systemd-detect-virt --vm');
			if (defined($systemd)) {
				if ($systemd =~ m/(\S+)/) {
					$hypervisor = $1 if ($1 ne 'none');
				}
			} else {
				my @dmesg=os_cmd("dmesg");# the ring buffer used by dmesg forgets any sufficiently 'ancient' logline.  But let's try!
        if ((scalar @dmesg) > 1) { # on any recent Linux kernel dmesg is reserved to root.  Any other user obtains "dmesg: read kernel buffer failed: Operation not permitted".  We may try to use "sudo dmesg" but it will probably fail and may trip some alarm or pollute a log.  We may explore by invoking "sudo -nl dmesg", then forfeit if the exitcode is 1 or otherwise search for \<dmesg\> in the produced lines, it may be useful if the system admin sudo-enables the 'postgres' user to run "dmesg"
          foreach my $line (@dmesg) {
            if ($line =~ /vmware/i) {
              $hypervisor='VMware';
              last;
            } elsif ($line =~ /kvm/i) {
              $hypervisor='KVM';
              last;
            } elsif ($line =~ /xen/i) {
              $hypervisor='XEN';
              last;
            } elsif ($line =~ /vbox/i) {
              $hypervisor='VirtualBox';
              last;
            } elsif ($line =~ /hyper-v/i) {
              $hypervisor='Hyper-V';
              last;
            }
          }
				}
			}
		}
		if (defined($hypervisor)) {
			print_report_info("Running under a $hypervisor hypervisor");
		} else {
			print_report_info("Running (probably) directly on a physical machine");
		}

		# I/O scheduler
		my %active_schedulers;
		if ($os->{name} eq 'darwin') {
			print_report_unknown("No I/O scheduler information on MacOS");
		} else {
			my $storage_units_list=os_cmd("ls /sys/block/");
			if (!defined $storage_units_list) {
				print_report_unknown("Unable to explore storage unit(s) system attributes");
			} else {
				foreach my $unit (split(/\n/,$storage_units_list)) {
					next if ($unit eq '.' or $unit eq '..');
					next if ($unit =~ /^sr/); # exclude cdrom

					# Scheduler
					my $unit_schedulers=os_cmd("cat /sys/block/$unit/queue/scheduler");
					if (! defined($unit_schedulers)) {
						print_report_unknown("Unable to identify the scheduler used for the storage unit $unit");
					} else {
						chomp($unit_schedulers);
						next if ($unit_schedulers eq 'none');
						foreach my $scheduler (split(/ /,$unit_schedulers)) {
							if ($scheduler =~ /^\[([a-z-]+)\]$/) {
								$active_schedulers{$1}++;
							}
						}
					}

					# Detect SSD or rotational disks
					my $unit_is_rotational=1; # Default
					if ($ssd) {
						$unit_is_rotational=0;
					} else {
						my $unit_is_rotational=os_cmd("cat /sys/block/$unit/queue/rotational");
						if (!defined($unit_is_rotational)) {
							print_report_unknown("Unable to identify if the storage unit $unit is rotational");
						} else {
							chomp($unit_is_rotational);
						}
					}
					$rotational_storage+=$unit_is_rotational;
				}
			}
			print_report_info("Currently used I/O scheduler(s): ".join(',',keys(%active_schedulers)));
		}
		if (defined($hypervisor) && defined($rotational_storage) && $rotational_storage>0) {
			print_report_warn("If PostgreSQL runs in a virtual machine, I cannot know the underlying physical storage type. Use the --ssd arg if the VM only uses SSD storage");
			add_advice("storage","high","Use the --ssd arg if PostgreSQL only uses a SSD storage");
		}
		if (defined($hypervisor) && $active_schedulers{'cfq'}) {
			print_report_bad("The CFQ scheduler is inadequate on a virtual machine (because the hypervisor and/or underlying kernel is already in charge of the I/O scheduling)");
			add_advice("system","high","Configure your virtual machine system to use the noop or deadline io scheduler:\necho deadline > /sys/block/sdX/queue/scheduler\nupdate your kernel parameters line with elevator=deadline to restore this parameter after each reboot");
		}
	}
}

print_header_1("General instance informations");

## PostgreSQL version
{
  print_header_2("PostgreSQL version");
  my $version=get_nonvolatile_setting('server_version');
  if ($version=~/(devel|rc|beta)/) {
    print_report_bad("You are using PostreSQL version $version which is a Development Snapshot, Beta or Release Candidate");
    add_advice("version","high","If this instance is a production server, then only use stable versions");
  }
  my $pg_upgrade="Upgrade to the latest stable PostgreSQL version";
  my $pg_supportdates="Check https://www.postgresql.org/support/versioning/ for upstream support dates";
  if (min_version('13.0')) {
    print_report_ok("You are using the latest PostreSQL major version ($version)");
  } elsif (min_version('12.0')) {
    print_report_ok($pg_upgrade);
    add_advice("version","low",$pg_upgrade);
  } elsif (min_version('11.0')) {
    print_report_ok($pg_upgrade);
    add_advice("version","low",$pg_upgrade);
  } elsif (min_version('10.0')) {
    print_report_warn($pg_upgrade);
    add_advice("version","low",$pg_upgrade);
    add_advice("version","low",$pg_supportdates);
  } elsif (min_version('9.5')) {
    print_report_warn($pg_upgrade);
    add_advice("version","medium",$pg_upgrade);
    add_advice("version","medium",$pg_supportdates);
  } elsif (min_version('8.1')) {
    print_report_bad("You are using PostreSQL version $version, which is unsupported upstream");
    add_advice("version","high",$pg_upgrade);
    add_advice("version","high",$pg_supportdates);
  } else {
    print_report_bad("You are using PostreSQL version $version, which is very old and not supported by this script");
    add_advice("version","high",$pg_upgrade);
  }
}

## Uptime
{
	print_header_2("Uptime");
	my $uptime=select_one_value("select extract(epoch from now()-pg_postmaster_start_time())");
	print_report_info("Service uptime: ".format_epoch_to_time($uptime));
	if ($uptime < $day_s) {
		print_report_warn("Uptime less than 1 day.  This report may be inaccurate");
	}
}

## Database count (except template)
{
	print_header_2("Databases");
	my @Databases=select_one_column("SELECT datname FROM pg_database WHERE NOT datistemplate AND datallowconn;");
	print_report_info("Database count (except templates): ".scalar(@Databases));
	print_report_info("Database list (except templates): @Databases");
}

## Extensions
{
	print_header_2("Extensions");
	print_report_info("Number of activated extensions: ".scalar(@Extensions));
	print_report_info("Activated extensions: @Extensions");
	if (grep(/pg_stat_statements/,@Extensions)) {
		print_report_ok("Extension pg_stat_statements is enabled");
	} else {
		print_report_warn("Extension pg_stat_statements is disabled in database $database");
		add_advice("extension","low","Enable pg_stat_statements in database $database to collect statistics on all queries (not only those longer than log_min_duration_statement)");
	}
}

## Users
{
	print_header_2("Users");
	my @ExpiringSoonUsers = select_one_column("select usename from pg_user where valuntil < now()+interval'7 days'");
	if (@ExpiringSoonUsers > 0) {
		print_report_warn("Some user account will expire in less than 7 days: ".join(',',@ExpiringSoonUsers));
	} else {
		print_report_ok("No user account will expire in less than 7 days");
	}
	if ($i_am_super) {
		my @BadPasswordUsers = select_one_column("select usename from pg_shadow where passwd='md5'||md5(usename||usename)");
		if (@BadPasswordUsers > 0) {
			print_report_warn("Some user account password is the username: ".join(',',@BadPasswordUsers));
		} else {
			print_report_ok("No user with password=username");
		}
	} else {
		print_report_warn("Unable to check users passwords, please use a super user instead");
	}
	my $password_encryption=get_nonvolatile_setting('password_encryption');
	if ($password_encryption eq 'off') {
		print_report_bad("Password encryption is disabled by default.  Passwords will not be encrypted until explicitely asked");
	} else {
		print_report_ok("Password encryption enabled");
	}
}

## Connections and Memory
{
	print_header_2("Connection information");
	# max_connections
	my $max_connections=get_nonvolatile_setting('max_connections');
	print_report_info("max_connections: $max_connections");

	# current connections + ratio
	my $current_connections=select_one_value("select count(1) from pg_stat_activity");
	my $current_connections_percent=$current_connections*100/$max_connections;
	print_report_info("Current used connections: $current_connections (".format_percent($current_connections_percent).")");
	if ($current_connections_percent > 70) {
		print_report_warn("You are using more than 70% of the connections slots.  Increase max_connections to avoid saturation of connection slots");
	} elsif ($current_connections_percent > 90) {
		print_report_bad("You are using more than 90% of the connection slots.  Increase max_connections to avoid saturation of connection slots");
	}
	# superuser_reserved_connections
	my $superuser_reserved_connections=get_nonvolatile_setting("superuser_reserved_connections");
	my $superuser_reserved_connections_ratio=$superuser_reserved_connections*100/$max_connections;
	if ($superuser_reserved_connections == 0) {
		print_report_bad("No connection slot is reserved for the superuser.  In case of connection saturation you will not be able to connect to investigate or kill connections");
	} else {
		print_report_info("$superuser_reserved_connections connections are reserved for super user (".format_percent($superuser_reserved_connections_ratio).")");
	}
	if ($superuser_reserved_connections_ratio > 20) {
		print_report_warn(format_percent($superuser_reserved_connections_ratio)." of connections are reserved for super user.  This is too much and may limit other users connections");
	}
	# average connection age
	my $connection_age_average=select_one_value("select extract(epoch from avg(now()-backend_start)) as age from pg_stat_activity");
	print_report_info("Average connection age: ".format_epoch_to_time($connection_age_average));
	if ($connection_age_average < 1 * $min_s) {
		print_report_bad("The average connection age is less than 1 minute.  Use a connection pooler to limit new connections/second");
	} elsif ($connection_age_average < 10 * $min_s) {
		print_report_warn("The average connection age is less than 10 minutes.  Use a connection pooler to limit new connections/second");
	}
	# pre_auth_delay
	my $pre_auth_delay=get_nonvolatile_setting('pre_auth_delay');
	$pre_auth_delay=~s/s//;
	if ($pre_auth_delay > 0) {
		print_report_bad("pre_auth_delay=$pre_auth_delay: this is a developer feature for debugging and decrease connection delay of $pre_auth_delay seconds");
	}
	# post_auth_delay
	my $post_auth_delay=get_nonvolatile_setting('post_auth_delay');
	$post_auth_delay=~s/s//;
	if ($post_auth_delay > 0) {
		print_report_bad("post_auth_delay=$post_auth_delay: this is a developer feature for debugging and decrease connection delay of $post_auth_delay seconds");
	}

	print_header_2("Memory usage");
	# work_mem
	my $work_mem=get_nonvolatile_setting('work_mem');
	my $work_mem_total=$work_mem*$work_mem_per_connection_percent/100*$max_connections;
	print_report_info("Configured work_mem: ".format_size($work_mem));
	print_report_info("Using an average ratio of work_mem buffers by connection of $work_mem_per_connection_percent% (use --wmp to change it)");
	print_report_info("Total work_mem (per connection): ".format_size($work_mem*$work_mem_per_connection_percent/100));
	my $shared_buffers=get_nonvolatile_setting('shared_buffers');
	# shared_buffers
	print_report_info("shared_buffers: ".format_size($shared_buffers));
	# track activity
	my $max_processes=get_nonvolatile_setting('max_connections')+get_nonvolatile_setting('autovacuum_max_workers');
	if (min_version('9.4')) {
		$max_processes+=get_nonvolatile_setting('max_worker_processes');
	}
	my $track_activity_size=get_nonvolatile_setting('track_activity_query_size')*$max_processes;
	print_report_info("Track activity reserved size: ".format_size($track_activity_size));
	# maintenance_work_mem
	my $maintenance_work_mem=get_nonvolatile_setting('maintenance_work_mem');
	my $autovacuum_max_workers=get_nonvolatile_setting('autovacuum_max_workers');
	my $maintenance_work_mem_total=$maintenance_work_mem*$autovacuum_max_workers;
	if ($maintenance_work_mem<=64*1024*1024) {
		print_report_warn("maintenance_work_mem is less or equal to its default value.  Increase it to reduce maintenance tasks duration");
	} else {
		print_report_info("maintenance_work_mem=".format_size($maintenance_work_mem));
	}
	# total
	my $max_memory=$shared_buffers+$work_mem_total+$maintenance_work_mem_total+$track_activity_size;

	print_report_info("Max memory usage:\n\t\t  shared_buffers (".format_size($shared_buffers).")\n\t\t+ max_connections * work_mem * average_work_mem_buffers_per_connection ($max_connections * ".format_size($work_mem)." * $work_mem_per_connection_percent / 100 = ".format_size($max_connections*$work_mem*$work_mem_per_connection_percent/100).")\n\t\t+ autovacuum_max_workers * maintenance_work_mem ($autovacuum_max_workers * ".format_size($maintenance_work_mem)." = ".format_size($autovacuum_max_workers*$maintenance_work_mem).")\n\t\t+ track activity size (".format_size($track_activity_size).")\n\t\t= ".format_size($max_memory));
	# effective_cache_size
	my $effective_cache_size=get_nonvolatile_setting('effective_cache_size');
	print_report_info("effective_cache_size: ".format_size($effective_cache_size));
	# total database size
	my $all_databases_size=select_one_value("select sum(pg_database_size(datname)) from pg_database");
	print_report_info("Cumulated size of all databases: ".format_size($all_databases_size));
	# shared_buffer usage
	my $shared_buffers_usage=$all_databases_size/$shared_buffers;
	if ($shared_buffers_usage < 0.7) { # todo: may shared_buffers also contain various non-data, for example indexes?  In such a case the total (cumulated) database size is only one parameter here.  The question now is: do shared_buffers cache anything other than tables contents, especially does it caches indices (indexes)?  I experimented while exploring thanks to pg_buffercache and it seems (PG11) that index-only access indeed load shared_buffers, however PG may be loading some/each data (corresponding to a conditon-satisfying index hit)?).  If it doesn't it may be part of the reason why maxing shared_buffers at 40% of the RAM is realistic, as (even if shared_buffer is more efficient than the kernel when it comes to caching DB data) a fair kernel buffercache containing some intensively-used indices (indexes) pages is far better than having no cached index.  It seems that shared_buffers only caches data
		print_report_warn("shared_buffer is too big for the total databases size, uselessly using memory");
	}
  if ($effective_cache_size < $shared_buffers) {
		print_report_warn("effective_cache_size < shared_buffer.  This is inadequate, as effective_cache_size value must be (shared buffers) + (size in bytes of the kernel's storage buffercache that will be used for PostgreSQL data files)");
  }
  my $buffercache_declared_size = $effective_cache_size - $shared_buffers;
  if ( $buffercache_declared_size < 4000000000) {
    print_report_warn("The declared buffercache size ( effective_cache_size - shared_buffers ) is less than 4GB.  effective_cache_size value is probably inadequate.  It must be (shared buffers) + (size in bytes of the kernel's storage buffercache that will be used for PostgreSQL data files)");
  }

	# ratio of total RAM
	if (! defined($os->{mem_total})) {
		if (defined($memory)) {
			$os->{mem_total} = $memory;
		}
	}
	if (! defined($os->{mem_total})) {
		print_report_unknown("OS total mem unknown: unable to analyse PostgreSQL memory usage");
	} else {
#todo: shared_buffers MAX: 40% RAM
		my $percent_postgresql_max_memory=$max_memory*100/$os->{mem_total};
		print_report_info("PostgreSQL maximum amount of memory used: ".format_percent($percent_postgresql_max_memory)." of system RAM");
		if ($percent_postgresql_max_memory > 100) {
			print_report_bad("PostgreSQL may try to use more than the amount of RAM.  Add more RAM or reduce PostgreSQL memory requirements");
		} elsif ($percent_postgresql_max_memory > 80) {
			print_report_warn("PostgreSQL may try to use more than 80% of the amount of RAM");
		} elsif ($percent_postgresql_max_memory < 60) {
			print_report_info("PostgreSQL will not use more than 60% of the amount of RAM.  On a dedicated host you may increase PostgreSQL shared_buffers, as it may improve performance");
		} else {
			print_report_ok("The potential max memory usage of PostgreSQL is adequate if the host is dedicated to PostgreSQL");
		}
		print_report_warn("PostgreSQL may try to use more than 40% of the amount of RAM for shared_buffers.  This is probably too much, reduce shared_buffers")
			if ( $shared_buffers / $os->{mem_total} > .4);
		# track activity ratio
		my $track_activity_ratio=$track_activity_size*100/$os->{mem_total};
		if ($track_activity_ratio > 1) {
			print_report_warn("Track activity reserved size is more than 1% of your RAM");
			add_advice("track_activity","low","Your track activity reserved size is too high.  Reduce track_activity_query_size and/or max_connections");
		}
		# total ram usage with effective_cache_size
		my $percent_mem_usage=($max_memory+$effective_cache_size-$shared_buffers)*100/$os->{mem_total};
		print_report_info("max memory usage + effective_cache_size - shared_buffers is ".format_percent($percent_mem_usage)." of the amount of RAM");
		if ($percent_mem_usage < 60 and $shared_buffers_usage > 1) {
			print_report_warn("Increase shared_buffers to let PostgreSQL directly use more memory, especially if the machine is dedicated to PostgreSQL");
		} elsif ($percent_mem_usage > 90) {
			print_report_warn("The sum of max_memory and effective_cache_size is too high, the planner may create bad plans because the system buffercache will probably be smaller than expected, especially if the machine is NOT dedicated to PostgreSQL");
		}
	}
	# Hugepages
	print_header_2("Huge Pages");
  if (($os->{name} ne 'linux') && ($os->{name} ne 'freebsd')) { # not sure about FreeBSD
		print_report_unknown("No Huge Pages on this OS");
	} else {
		my $nr_hugepages=get_sysctl('vm.nr_hugepages');
		if (!defined $nr_hugepages || $nr_hugepages == 0) {
			print_report_warn("No Huge Pages available on the system");
			last;
		}
		if (get_nonvolatile_setting('huge_pages') eq 'on') {
			print_report_warn("huge_pages=on, therefore PostgreSQL needs Huge Pages and will not start if the kernel doesn't provide them");
		}
    elsif	(get_nonvolatile_setting('huge_pages') eq 'try') {
			print_report_info("huge_pages=on, therefore PostgreSQL will try to use Huge Pages, if they are enabled");
		}
    else {
      add_advice("hugepages","medium","Enable huge_pages to enhance memory allocation performance, and if necessary also enable them at OS level");
    }
    my $os_huge=os_cmd("grep ^Huge /proc/meminfo");
		($os->{HugePages_Total})=($os_huge =~ /HugePages_Total:\s+([0-9]+)/);
		($os->{HugePages_Free})=($os_huge =~ /HugePages_Free:\s+([0-9]+)/);
		($os->{Hugepagesize})=($os_huge =~ /Hugepagesize:\s+([0-9]+)/);
		print_report_info("Hugepagesize is ".$os->{Hugepagesize}." kB");
		print_report_info("HugePages_Total ".$os->{HugePages_Total}." pages");
		print_report_info("HugePages_Free ".$os->{HugePages_Free}." pages");

		my $pg_pid=select_one_value("SELECT pg_backend_pid();");
		my $peak=os_cmd("grep ^VmPeak /proc/".$pg_pid."/status | awk '{ print \$2 }'");
		chomp($peak);
		my $suggesthugepages=$peak/$os->{Hugepagesize};
		print_report_info("Suggested number of Huge Pages: ".int($suggesthugepages + 0.5)." (Consumption peak: ".$peak." / Huge Page size: ".$os->{Hugepagesize}.")");
		if ($os->{HugePages_Total} < int($suggesthugepages + 0.5)) {
			add_advice("hugepages","medium","set vm.nr_hugepages=".int($suggesthugepages + 0.5)." in /etc/sysctl.conf and invoke  sysctl -p /etc/sysctl.conf  to reload it.  This will allocate Huge Pages (it may require a system reboot)");
		}

		if ($os->{Hugepagesize} == 2048) {
			add_advice("hugepages","low","Change Huge Pages size from 2MB to 1GB if the machine is dedicated to PostgreSQL");
		}
	}
}

## Logs
{
	print_header_2("Logs");
	# log hostname
	my $log_hostname=get_nonvolatile_setting('log_hostname');
	if ($log_hostname eq 'on') {
		print_report_bad("log_hostname is on: this will decrease connection performance (because PostgreSQL has to do DNS lookups)");
	} else {
		print_report_ok("log_hostname is off: no reverse DNS lookup latency");
	}

	# log_min_duration_statement
	my $log_min_duration_statement=get_nonvolatile_setting('log_min_duration_statement');
	$log_min_duration_statement=~s/ms//;
	if ($log_min_duration_statement == -1 ) {
		print_report_warn("Log of long queries deactivated.  It will be more difficult to optimize query performance");
	} elsif ($log_min_duration_statement < 1000 ) {
		print_report_bad("log_min_duration_statement=$log_min_duration_statement: any request during less than 1 sec will be written in log.  It may be storage-intensive (I/O and space)");
	} else {
		print_report_ok("Long queries will be logged");
	}

	# log_statement
	my $log_statement=get_nonvolatile_setting('log_statement');
	if ($log_statement eq 'all') {
		print_report_bad("log_statement=all is very storage-intensive and only usefull for debuging");
	} elsif ($log_statement eq 'mod') {
		print_report_warn("log_statement=mod is storage-intensive");
	} else {
		print_report_ok("log_statement=$log_statement");
	}
}

## Two-phase commit
{
	print_header_2("Two-phase commit");
	if (min_version('9.2')) {
		my $prepared_xact_count=select_one_value("select count(1) from pg_prepared_xacts");
		if ($prepared_xact_count == 0) {
			print_report_ok("Currently there is no two-phase commit transaction");
		} else {
			print_report_warn("Currently $prepared_xact_count two-phase commit prepared transactions exist.  If they stay for too long they may lock objects for too long");
			my $prepared_xact_lock_count=select_one_value("select count(1) from pg_locks where transactionid in (select transaction from pg_prepared_xacts)");
			if ($prepared_xact_lock_count > 0) {
				print_report_bad("Two-phase commit transactions have $prepared_xact_lock_count locks!");
			} else {
				print_report_ok("No locks for theses $prepared_xact_count transactions");
			}
		}
	} else {
		print_report_warn("This PostgreSQL version does not support two-phase commit");
	}
}

## Autovacuum
{
	print_header_2("Autovacuum");
	if (get_nonvolatile_setting('autovacuum') eq 'on') {
		print_report_ok('autovacuum is activated');
		my $autovacuum_max_workers=get_nonvolatile_setting('autovacuum_max_workers');
		print_report_info("autovacuum_max_workers: $autovacuum_max_workers");
	} else {
		print_report_bad('autovacuum is not activated.  This is bad except if you known what you do');
	}
}

## Checkpoint
{
	print_header_2("Checkpoint");
	my $checkpoint_completion_target=get_nonvolatile_setting('checkpoint_completion_target'); # no dimension
  my $checkpoint_warning=get_nonvolatile_setting('checkpoint_warning'); # unit: s
  $checkpoint_warning=~s/s$//;
  my $checkpoint_timeout=get_nonvolatile_setting('checkpoint_timeout'); # unit: s
  $checkpoint_timeout=~s/s$//;
  print_report_warn("checkpoint_warning value is 0.  This is rarely adequate") if ( 0 == $checkpoint_warning );
  if ($checkpoint_completion_target == 0) {
    print_report_bad("checkpoint_completion_target value is 0.  This is absurd");
  }
  else {
    my $msg_CCT="checkpoint_completion_target is low.  Some checkpoints may abruptly overload the storage with write commands for a long time, slowing running queries down.  To avoid such temporary overload you may balance checkpoint writes using a higher value";
    if ($checkpoint_completion_target < 0.5) {
      print_report_warn("Checkpoint_completion_target ($checkpoint_completion_target) is lower than its default value (0.5)");
      add_advice("checkpoint","high", $msg_CCT);
    } elsif ($checkpoint_completion_target >= 0.5 and $checkpoint_completion_target <= 0.7) {
      print_report_warn("checkpoint_completion_target ($checkpoint_completion_target) is low");
      add_advice("checkpoint","medium", $msg_CCT);
    } elsif ($checkpoint_completion_target > 0.7 and $checkpoint_completion_target <= 0.9) {
      print_report_ok("checkpoint_completion_target ($checkpoint_completion_target) OK");
    } elsif ($checkpoint_completion_target > 0.9 and $checkpoint_completion_target < 1) {
      print_report_warn("checkpoint_completion_target($checkpoint_completion_target) is too near to 1");
      add_advice("checkpoint","medium", "Reduce checkpoint_completion_target");
    } else {
      print_report_bad("checkpoint_completion_target too high ($checkpoint_completion_target)");
    }
    my $checkpoint_dirty_writing_time_window=$checkpoint_timeout * $checkpoint_completion_target;
		print_report_warn("(checkpoint_timeout / checkpoint_completion_target) is probably too low")
			if ($checkpoint_dirty_writing_time_window < 10);
    if (min_version('9.5')) { # too much work for us, given all settings and PG versions.  For now let's neglect 'old' PG versions
      my $max_wal_size=get_nonvolatile_setting('max_wal_size'); # Maximum size to let the WAL grow to between automatic WAL checkpoints
			my $average_w=$max_wal_size/$checkpoint_dirty_writing_time_window;
			my $aw_msg="Given those settings PostgreSQL may (depending on its workload) ask the kernel to write (to the storage) up to " . format_size($max_wal_size) . " in a timeframe lasting " . $checkpoint_dirty_writing_time_window . " seconds <=> " . format_size($average_w) . " bytes/second during this timeframe.  You may want to check that your storage is able to cope with this, along with all other I/O (non-writing queries, other software...) operations potentially active during this timeframe.  If this seems inadequate check max_wal_size, checkpoint_timeout and checkpoint_completion_target";
			($average_w < ($ssd ? 2e8 : 3e7)) ? print_report_info($aw_msg) : print_report_warn($aw_msg);
    }
  }
}

## Storage
{
	print_header_2("Storage");
	my $fsync=get_nonvolatile_setting('fsync');
	my $wal_sync_method=get_nonvolatile_setting('wal_sync_method');
	if ($fsync eq 'on') {
		print_report_ok("fsync is on");
	} else {
		print_report_bad("fsync is off.  You may lose data after a crash, DANGER!");
		add_advice("storage","high","set fsync to on!");
	}
	if ($os->{name} eq 'darwin') {
		if ($wal_sync_method ne 'fsync_writethrough') {
			print_report_bad("wal_sync_method is $wal_sync_method.  Settings other than fsync_writethrough may lead to loss of data after a crash, DANGER!");
			add_advice("storage","high","set wal_sync_method to fsync_writethrough to on.  Otherwise, the write-back cache may prevent recovery after a crash");
		} else {
			print_report_ok("wal_sync_method is $wal_sync_method");
		}
	}
	if (get_nonvolatile_setting('synchronize_seqscans') eq 'on') {
		print_report_ok("synchronize_seqscans is on");
	} else {
		print_report_warn("synchronize_seqscans is off");
		add_advice("seqscan","medium","set synchronize_seqscans to synchronize seqscans and reduce I/O load");
	}
}

## WAL / PITR
{
	print_header_2("WAL");
	if (min_version('9.0')) {
		my $wal_level=get_nonvolatile_setting('wal_level');
		if ($wal_level eq 'minimal') {
			print_report_bad("The \'minimal\' wal_level does not allow PITR backup and recovery");
			add_advice("backup","high","Configure your wal_level to a level which allows PITR backup and recovery");
		}
	} else {
		print_report_warn("wal_level not supported, please upgrade PostgreSQL");
	}
}

## Planner
{
	print_header_2("Planner");
	# Modified cost settings
	my @ModifiedCosts=select_one_column("select name from pg_settings where name like '%cost%' and setting<>boot_val;");
	if (@ModifiedCosts > 0) {
		print_report_warn("Some I/O cost settings are not set to their default value: ".join(',',@ModifiedCosts).".  This may lead the planner to create suboptimal plans");
	} else {
		print_report_ok("I/O cost settings are set at their default values");
	}

	# random vs seq page cost on SSD
	if (!defined($rotational_storage)) {
		print_report_unknown("I have no information about the rotational/SSD storage: I'm unable to check random_page_cost and seq_page_cost settings");
	} else {
		if ($rotational_storage == 0 and get_nonvolatile_setting('random_page_cost')>get_nonvolatile_setting('seq_page_cost')) {
			print_report_warn("With SSD storage, set random_page_cost=seq_page_cost to help the planner prefer index scans");
			add_advice("planner","medium","Set random_page_cost=seq_page_cost on SSD storage");
		} elsif ($rotational_storage > 0 and get_nonvolatile_setting('random_page_cost')<=get_nonvolatile_setting('seq_page_cost')) {
			print_report_bad("Without SSD storage, the random_page_cost value must be superior than the seq_page_cost value");
			add_advice("planner","high","If you don't use SSD storage then set random_page_cost to 2-4 times more than seq_page_cost/  Reduce the factor if you use multiple rotating disks");
		}
	}

	# disabled plan functions
	my @DisabledPlanFunctions=select_one_column("select name,setting from pg_settings where name like 'enable_%' and setting='off';");
	if (@DisabledPlanFunctions > 0) {
		print_report_bad("Some plan features are disabled: ".join(',',@DisabledPlanFunctions));
	} else {
		print_report_ok("All plan features are enabled");
	}

}

# Database information
print_header_1("Database information for database $database");

## Database size
{
	print_header_2("Database size");
	my $sum_total_relation_size=select_one_value("select sum(pg_total_relation_size(schemaname||'.'||quote_ident(tablename))) from pg_tables");
	print_report_info("Database $database total size: ".format_size($sum_total_relation_size));
	if (min_version('9.0')) {
		my $sum_table_size=select_one_value("select sum(pg_table_size(schemaname||'.'||quote_ident(tablename))) from pg_tables");
		my $sum_index_size=$sum_total_relation_size-$sum_table_size;
		#print_report_debug("sum_total_relation_size: $sum_total_relation_size");
		#print_report_debug("sum_table_size: $sum_table_size");
		#print_report_debug("sum_index_size: $sum_index_size");
		my $table_percent=$sum_table_size*100/$sum_total_relation_size;
		my $index_percent=$sum_index_size*100/$sum_total_relation_size;
		print_report_info("Database $database tables size: ".format_size($sum_table_size)." (".format_percent($table_percent).")");
		print_report_info("Database $database indexes size: ".format_size($sum_index_size)." (".format_percent($index_percent).")");
	}
}

## Tablespace location
{
	print_header_2("Tablespace location");
	if (min_version('9.2')) {
		my $tablespaces_in_pgdata=select_all_hashref("select spcname,pg_tablespace_location(oid) from pg_tablespace where pg_tablespace_location(oid) like (select setting from pg_settings where name='data_directory')||'/%'",'spcname');
		if (keys(%{$tablespaces_in_pgdata}) == 0) {
			print_report_ok("No tablespace in PGDATA");
		} else {
			print_report_bad("Some tablespaces defined in PGDATA: ".join(' ',keys(%{$tablespaces_in_pgdata})));
			add_advice('tablespaces','high','Some tablespaces are in PGDATA.  Move them outside of this folder');
		}
	} else {
		print_report_unknown("This check is only possible with PostgreSQL version 9.2 and above");
	}
}

## Shared buffer usage
{
	print_header_2("Shared buffer hit rate");
	### Heap hit rate
	{
		my $shared_buffer_heap_hit_rate=select_one_value("select sum(heap_blks_hit)*100/(sum(heap_blks_read)+sum(heap_blks_hit)+1) from pg_statio_all_tables ;");
		print_report_info("shared_buffer_heap_hit_rate: ".format_percent($shared_buffer_heap_hit_rate));
	}
	### TOAST hit rate
	{
		my $shared_buffer_toast_hit_rate=select_one_value("select sum(toast_blks_hit)*100/(sum(toast_blks_read)+sum(toast_blks_hit)+1) from pg_statio_all_tables ;");
		print_report_info("shared_buffer_toast_hit_rate: ".format_percent($shared_buffer_toast_hit_rate));
	}
	# Tidx hit rate
	{
		my $shared_buffer_tidx_hit_rate=select_one_value("select sum(tidx_blks_hit)*100/(sum(tidx_blks_read)+sum(tidx_blks_hit)+1) from pg_statio_all_tables ;");
		print_report_info("shared_buffer_tidx_hit_rate: ".format_percent($shared_buffer_tidx_hit_rate));
	}
	# Idx hit rate
	{
		my $shared_buffer_idx_hit_rate=select_one_value("select sum(idx_blks_hit)*100/(sum(idx_blks_read)+sum(idx_blks_hit)+1) from pg_statio_all_tables ;");
		print_report_info("shared_buffer_idx_hit_rate: ".format_percent($shared_buffer_idx_hit_rate));
		if ($shared_buffer_idx_hit_rate > 99.99) {
			print_report_info("This is too high.  If this PostgreSQL instance was recently used as it usually is and was not stopped since, then you may reduce shared_buffer"); # todo: even on a dedicated server, because it may benefit to the kernel's buffercache
		} elsif ($shared_buffer_idx_hit_rate>98) {
			print_report_ok("This is very good (if this PostgreSQL instance was recently used as it usually is, and was not stopped since)");
			# todo: however it is not so good if PG is on a non-dedicated machine and not heavily used: it wastes RAM
		} elsif ($shared_buffer_idx_hit_rate>90) {
			print_report_warn("This is quite good.  Increase shared_buffer memory to increase hit rate");
		} else {
			print_report_bad("This is too low.  Increase shared_buffer memory to increase hit rate");
		}
	}
}

## Indexes
{
	print_header_2("Indexes");
	# Invalid indexes
	{
		my @Invalid_indexes=select_one_column("SELECT
                                            concat(n.nspname, '.', c.relname) as index
                                          FROM
                                            pg_catalog.pg_class c,
                                            pg_catalog.pg_namespace n,
                                            pg_catalog.pg_index i
                                          WHERE
                                            i.indisvalid = false AND
                                            i.indexrelid = c.oid AND
                                            c.relnamespace = n.oid;");
		if (@Invalid_indexes > 0) {
			print_report_bad("List of invalid index in the database: ". join(',', @Invalid_indexes));
			add_advice("index","high","Please check/reindex any invalid index");
		} else {
			print_report_ok("No invalid index");
		}
	}
	# Unused indexes
	{
		my @Unused_indexes;
		if (min_version('9.0')) {
			@Unused_indexes=select_one_column("select relname||'.'||indexrelname from pg_stat_user_indexes where idx_scan=0 and not exists (select 1 from pg_constraint where conindid=indexrelid) ORDER BY relname, indexrelname");
		} else {
			@Unused_indexes=select_one_column("select relname||'.'||indexrelname from pg_stat_user_indexes where idx_scan=0 ORDER BY relname, indexrelname");
		}
		if (@Unused_indexes > 0) {
			print_report_warn(@Unused_indexes . " indexes were not used since the last statistics run");
			add_advice("index","medium","You have unused indexes in the database since the last statistics run.  Please remove them if they are rarely or not used"); # this is especially useful if the table is frequently updated (insert/delete, or updates hitting indexed columns).  todo: checking this?
		} else {
			print_report_ok("No unused indexes");
		}
	}
}

## Procedures
{
	print_header_2("Procedures");
	# Procedures with default cost
	{
		my @Default_cost_procs=select_one_column("select n.nspname||'.'||p.proname from pg_catalog.pg_proc p left join pg_catalog.pg_namespace n on n.oid = p.pronamespace where pg_catalog.pg_function_is_visible(p.oid) and n.nspname not in ('pg_catalog','information_schema','sys') and p.prorows<>1000 and p.procost<>10 and p.proname not like 'uuid_%' and p.proname != 'pg_stat_statements_reset'");
		if (@Default_cost_procs > 0) {
			print_report_warn(@Default_cost_procs . " user procedures do not have custom cost and rows settings");
			add_advice("proc","low","You have custom procedures with default cost and rows setting.  Reconfigure them with specific values to help the planner");
		} else {
			print_report_ok("No procedures with default costs");
		}
	}
}

$dbh->disconnect();

print_advices();

exit(0);


sub preserve_only_digits($) {
	my $str=shift;
	return 0 if (!defined $str);
	$str=~/(\d+)/; # neglect any non-num ('devel', 'RC', 'beta', 'Debian'...)
	return (defined $1) ? $1 : 0;
}

sub min_version($) {
	my $min_version=shift;
#	die("This script has a bug.  min_version called without minor version, line ". [caller(0)]->[2]) # commented out: let's use prototypes!
#		if (!defined $min_version);
	my $cur_version=get_nonvolatile_setting('server_version');
	my ($min_major,$min_minor)=split(/\./,$min_version);
	my ($cur_major,$cur_minor)=split(/\./,$cur_version);
	die "This script has a bug" if (!defined $cur_major or !defined $cur_minor);
	$cur_major=preserve_only_digits($cur_major);
	$cur_minor=preserve_only_digits($cur_minor);
	return 1 if ($cur_major > $min_major);
	return ($cur_minor >= $min_minor) if ($cur_major == $min_major);
	return 0;
}

# execute SELECT query, return result as hashref on key
sub select_all_hashref {
	my ($query,$key)=@_;
	if (!defined($query) or !defined($key)) {
		print { $nocolor ? *STDOUT : *STDERR } "ERROR: Missing query or key\n";
		exit 1;
	}
	my $sth = $dbh->prepare($query);
	$sth->execute();
	return $sth->fetchall_hashref($key);
}

# execute SELECT query, return only one value
sub select_one_value {
	my ($query)=@_;
	if (!defined($query)) {
		print { $nocolor ? *STDOUT : *STDERR } "ERROR: Missing query\n";
		exit 1;
	}
	my $sth = $dbh->prepare($query);
	$sth->execute();
	if (my $result=$sth->fetchrow_arrayref()) {
		return @{$result}[0];
	} else {
		return undef;
	}
}

# execute SELECT query, return only one column as array
sub select_one_column {
	my ($query)=@_;
	if (!defined($query)) {
		print { $nocolor ? *STDOUT : *STDERR } "ERROR: Missing query\n";
		exit 1;
	}
	my $sth = $dbh->prepare($query);
	$sth->execute();
	my @Result;
	while (my $result=$sth->fetchrow_arrayref()) {
		push(@Result,@{$result}[0]);
	}
	return @Result;
}

sub print_report_ok		{ print_report('ok', shift); }
sub print_report_warn		{ print_report('warn', shift); }
sub print_report_bad		{ print_report('bad',	shift); }
sub print_report_info		{ print_report('info', shift); }
sub print_report_todo		{ print_report('todo', shift); }
sub print_report_unknown	{ print_report('unknown', shift); }
sub print_report_debug		{ print_report('debug',	shift); }

sub print_report {
	my ($type,$message)=@_;
	if ($type eq "ok") {
		print STDOUT color('green')  ."[OK]      ".color('reset').$message."\n";
	} elsif ($type eq "warn") {
		print STDOUT color('yellow') ."[WARN]    ".color('reset').$message."\n";
	} elsif ($type eq "bad") {
		print { $nocolor ? *STDOUT : *STDERR } color('red')    ."[BAD]     ".color('reset').$message."\n";
	} elsif ($type eq "info") {
		print { $nocolor ? *STDOUT : *STDERR } color('white')  ."[INFO]    ".color('reset').$message."\n";
	} elsif ($type eq "todo") {
		print { $nocolor ? *STDOUT : *STDERR } color('magenta')."[TODO]    ".color('reset').$message."\n";
	} elsif ($type eq "unknown") {
		print STDOUT color('cyan')   ."[UNKNOWN] ".color('reset').$message."\n";
	} elsif ($type eq "debug") {
		print { $nocolor ? *STDOUT : *STDERR } color('magenta')."[DEBUG]   ".color('reset').$message."\n";
	} else {
		die("This script has a bug.  Unknown report type ($type) line ". [caller(0)]->[2]);
	}
}

sub print_header_1 { print_header(1,shift); }
sub print_header_2 { print_header(2,shift); }

sub print_header {
	my ($level,$title)=@_;
	my $sep='';
	if ($level == 1) {
		print color('white');
		$sep='=';
	} elsif ($level == 2) {
		print color('white');
		$sep='-';
	} else {
		warn("Unknown level $level for title $title");
	}
	print $sep x 5 ."  $title  ". $sep x 5;
	print color('reset');
	print "\n";
}

sub get_setting {
	my $name=shift;
	if (!defined($settings->{$name})) {
		print { $nocolor ? *STDOUT : *STDERR } "ERROR: the setting $name does not exist in this PostgreSQL version, please upgrade\n";
		die "Aborting";
	} else {
    return standard_units($settings->{$name}->{setting}, $settings->{$name}->{unit});
  }
}

sub get_nonvolatile_setting {
  return get_setting(shift);
}

sub standard_units {
  my $value=shift;
  my $unit=shift;
  return $value         if !$unit;
  return $value*1024    if $unit eq 'kB' or $unit eq 'K';
  return $value*8*1024  if $unit eq '8kB';
  return $value*16*1024 if $unit eq '16kB';
  return $value*1024*1024 if $unit eq 'M' or $unit eq 'MB';
  return $value*1024*1024*1024 if $unit eq 'G' or $unit eq 'GB';
  return $value*1024*1024*1024*1024 if $unit eq 'T' or $unit eq 'TB';
  return $value*1024*1024*1024*1024*1024 if $unit eq 'P' or $unit eq 'PB';
  return $value.'s'     if $unit eq 's';
  return $value.'ms'    if $unit eq 'ms';
}

sub format_size {
	my $size=shift;
        my @units=('B','KB','MB','GB','TB','PB');
        my $unit_index=0;
        return 0 if !defined($size);
        while ($size>1024) {
                $size=$size/1024;
                $unit_index++;
        }
        return sprintf("%.2f %s",$size,$units[$unit_index]);
}

sub format_percent {
	my $value=shift;
	return sprintf("%.2f%%",$value);
}

sub format_epoch_to_time {
	my $epoch=shift;
	my $time='';
	if ($epoch > $day_s) {
		my $days=sprintf("%d",$epoch/$day_s);
		$epoch=$epoch%$day_s;
		$time.=$days.'d';
	}
	if ($epoch > $hour_s) {
		my $hours=sprintf("%d",$epoch/$hour_s);
		$epoch=$epoch%$hour_s;
		$time.=' '.sprintf("%02d",$hours).'h';
	}
	if ($epoch > $min_s) {
		my $mins=sprintf("%d",$epoch/$min_s);
		$epoch=$epoch%$min_s;
		$time.=' '.sprintf("%02d",$mins).'m';
	}
	$time.=' '.sprintf("%02d",$epoch).'s';
	return $time;
}

sub os_cmd {
	my $command=$os_cmd_prefix.shift;
	local $SIG{__WARN__} = sub {};
	my $result=`$command 2>&1`;
	if ( $? == 0 ) {
		return $result;
	} else {
		warn("Command $command failed");
		return undef;
	}
}

sub try_load {
	my ($mod,$package_cmd)=@_;
	eval("use $mod");
	if ($@) {
		print { $nocolor ? *STDOUT : *STDERR } "# Missing Perl module '$mod'. Please install it\n";
		for my $check (keys %$package_cmd) {
			print $package_cmd->{$check}."\n" if -f $check;
		}
		return 1;
	} else {
		return 0;
	}
}

sub get_sysctl {
	my $name=shift;
	$name=~s/\./\//g;
	my $value=os_cmd("cat /proc/sys/$name");
	if (!defined($value)) {
		print_report_unknown("Unable to read sysctl $name");
		return undef;
	} else {
		chomp($value);
		return $value;
	}
}

sub add_advice {
	my ($category,$priority,$advice)=@_;
  $priority='high' if ($priority eq 'urgent');
	die("This script has a bug.  Unknown priority '$priority', line ". [caller(0)]->[2]) if ($priority !~ /(high|medium|low)/);
	die("This script has a bug.  No advice text, line ". [caller(0)]->[2]) if (! defined $advice);
	push(@{$advices{$category}{$priority}},$advice);
}

sub print_advices {
	print "\n";
	print_header_1("Configuration advice");
	my $advice_count=0;
	foreach my $category (sort(keys(%advices))) {
		print_header_2($category);
		foreach my $priority (sort(keys(%{$advices{$category}}))) {
			if ($priority eq "high") {
        print color("red")
      } elsif ( $priority eq "medium") {
        print color("yellow")
      } elsif ( $priority eq "low" ) {
        print color("magenta")
      }
			foreach my $advice (@{$advices{$category}{$priority}}) {
				print "[".uc($priority)."] $advice\n";
				$advice_count++;
			}
			print color("reset");
		}
	}
	if ($advice_count == 0) {
		print color("green")."Everything is OK".color("reset")."\n";
	}
}

sub pgpass_match {
	my ($type,$var,$pgp_var)=@_;
	$pgp_var=pgpass_unescape($pgp_var);
	return 1 if $pgp_var eq '*';
	return 1 if $pgp_var eq $var;
	return 1 if $type eq 'host' and $pgp_var eq 'localhost' and $var=~m/^\//; # allow sockets if host=localhost
	return 0;
}

sub pgpass_unescape {
	my ($value)=@_;
	$value=~s/\\(.)/$1/g;
	return $value;
}

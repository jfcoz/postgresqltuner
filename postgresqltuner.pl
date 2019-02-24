#!/usr/bin/env perl

# The postgresqltuner.pl is Copyright (C) 2016 Julien Francoz <julien-postgresqltuner@francoz.net>,
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
	print STDERR "# Please install theses Perl modules\n";
	exit 1;
}

my $script_version="1.0.1";
my $script_name="postgresqltuner.pl";
my $min_s=60;
my $hour_s=60*$min_s;
my $day_s=24*$hour_s;

my $host=undef;
my $username=undef;
my $password=undef;
my $database=undef;
my $port=undef;
my $pgpassfile=$ENV{HOME}.'/.pgpass';
my $help=0;
my $work_mem_per_connection_percent=150;
my @Ssh_opts=('BatchMode=yes');
my $ssd=0;
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
        "ssd"         => \$ssd,
) or usage(1);

print "$script_name version $script_version\n";
if ($help) {
	usage(0);
}

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

	if (open(PGPASS,'<',$pgpassfile)) {
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
	print STDERR "If available connection informations can be read from \$PGHOST, \$PGPORT, \$PGDATABASE, \$PGUSER, \$PGPASSWORD\n";
	print STDERR "For security reasons, prefer usage of password in ~/.pgpass\n";
	print STDERR "\thost:port:database:username:password\n";
	print STDERR "  --wmp: average number of work_mem buffers per connection in percent (default 150)\n";
	print STDERR "  --sshopt: pass options to ssh (example --sshopt=Port=2200)\n";
	print STDERR "  --ssd: force storage detection as non rotational drives\n";
	exit $return;
}

# OS command check
print "Checking if OS commands is available on $host...\n";
my $os_cmd_prefix='LANG=C LC_ALL=C ';
my $can_run_os_cmd=0;
if ($host =~ /^\//) {
	$os_cmd_prefix='';
} elsif ($host =~ /^localhost$/) {
	$os_cmd_prefix='';
} elsif ($host =~ /^127\.[0-9]+\.[0-9]+\.[0-9]+$/) {
	$os_cmd_prefix='';
} elsif ($host =~ /^[a-zA-Z0-9.-]+$/) {
	$os_cmd_prefix="ssh $ssh_opts $host ";
} else {
	die("Invalid host $host");
}
if (defined(os_cmd("true"))) {
	$can_run_os_cmd=1;
        print_report_ok("OS command OK");
} else {
        print_report_bad("Unable to run OS command, report will be incomplete");
	add_advice("report","urgent","Please configure your .ssh/config to allow postgresqltuner.pl to connect via ssh to $host without password authentication. This will allow to collect more system informations");
}

# Database connection
print "Connecting to $host:$port database $database with user $username...\n";
my $dbh = DBI->connect("dbi:Pg:dbname=$database;host=$host;port=$port;",$username,$password,{AutoCommit=>1,RaiseError=>1,PrintError=>0});

# Collect datas
my $users=select_all_hashref("select * from pg_user","usename");
my $i_am_super=$users->{$username}->{usesuper};
my $settings=select_all_hashref("select * from pg_settings","name");
my $rotational_disks=undef;
my @Extensions;
if (min_version('9.1')) {
	@Extensions=select_one_column("select extname from pg_extension");
} else {
	print_report_warn("pg_extension does not exists in ".get_setting('server_version'));
}
my %advices;

if ($i_am_super) {
	print_report_ok("User used for report have super rights");
} else {
	print_report_bad("User used for report does not have super rights. Report will be incomplete");
	add_advice("report","urgent","Use an account with super privileges to get a more complete report");
}

# Report
print_header_1("OS information");

{
	if (! $can_run_os_cmd) {
		print_report_unknown("Unable to run OS commands on $host. For now you will not have OS information");
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
			my $os_mem=os_cmd("free -b");
			($os->{mem_total},$os->{mem_used},$os->{mem_free},$os->{mem_shared},$os->{mem_buffers},$os->{mem_cached})=($os_mem =~ /Mem:\s+([0-9]+)\s+([0-9]+)\s+([0-9]+)\s+([0-9]+)\s+([0-9]+)\s+([0-9]+)/);
			($os->{swap_total},$os->{swap_used},$os->{swap_free})=($os_mem =~ /Swap:\s+([0-9]+)\s+([0-9]+)\s+([0-9]+)/);
		}
		print_report_info("OS total memory: ".format_size($os->{mem_total}));

		# Overcommit
		if ($os->{name} eq 'darwin') {
			print_report_unknown("No information on memory overcommitment on MacOS.");
		} else {
			my $overcommit_memory=get_sysctl('vm.overcommit_memory');
			if ($overcommit_memory != 2) {
				print_report_bad("Memory overcommitment is allowed on the system. This can lead to OOM Killer killing some PostgreSQL process, which will cause a PostgreSQL server restart (crash recovery)");
				add_advice('sysctl','urgent','set vm.overcommit_memory=2 in /etc/sysctl.conf and run sysctl -p to reload it. This will disable memory overcommitment and avoid postgresql killed by OOM killer.');
				my $overcommit_ratio=get_sysctl('vm.overcommit_ratio');
				print_report_info("sysctl vm.overcommit_ratio=$overcommit_ratio");
				if ($overcommit_ratio <= 50) {
					print_report_bad("vm.overcommit_ratio is too small, you will not be able to use more than $overcommit_ratio*RAM+SWAP for applications");
				} elsif ($overcommit_ratio > 90) {
					print_report_bad("vm.overcommit_ratio is too high, you need to keep free space for the kernel");
				}
			} else {
				print_report_ok("vm.overcommit_memory is good : no memory overcommitment");
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
				my @dmesg=os_cmd("dmesg");
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
		if (defined($hypervisor)) {
			print_report_info("Running in $hypervisor hypervisor");
		} else {
			print_report_info("Running on physical machine");
		}

		# I/O scheduler
		my %active_schedulers;
		if ($os->{name} eq 'darwin') {
			print_report_unknown("No I/O scheduler information on MacOS");
		} else {
			my $disks_list=os_cmd("ls /sys/block/");
			if (!defined $disks_list) {
				print_report_unknown("Unable to identify disks");
			} else {
				foreach my $disk (split(/\n/,$disks_list)) {
					next if ($disk eq '.' or $disk eq '..');
					next if ($disk =~ /^sr/); # exclude cdrom

					# Scheduler
					my $disk_schedulers=os_cmd("cat /sys/block/$disk/queue/scheduler");
					if (! defined($disk_schedulers)) {
						print_report_unknown("Unable to identify scheduler for disk $disk");
					} else {
						chomp($disk_schedulers);
						next if ($disk_schedulers eq 'none');
						foreach my $scheduler (split(/ /,$disk_schedulers)) {
							if ($scheduler =~ /^\[([a-z]+)\]$/) {
								$active_schedulers{$1}++;
							}
						}
					}

					# Detect SSD or rotational disks
					my $disk_is_rotational=1; # Default
					if ($ssd) {
						$disk_is_rotational=0;
					} else {
						my $disk_is_rotational=os_cmd("cat /sys/block/$disk/queue/rotational");
						if (!defined($disk_is_rotational)) {
							print_report_unknown("Unable to identify if disk $disk is rotational");
						} else {
							chomp($disk_is_rotational);
						}
					}
					$rotational_disks+=$disk_is_rotational;
				}
			}
			print_report_info("Currently used I/O scheduler(s) : ".join(',',keys(%active_schedulers)));
		}
		if (defined($hypervisor) && defined($rotational_disks) && $rotational_disks>0) {
			print_report_warn("On virtual machines, /sys/block/DISK/queue/rotational is not accurate. Use the --ssd arg if the VM in running on a SSD storage");
			add_advice("report","urgent","Use the --ssd arg if the VM in running on a SSD storage");
		}
		if (defined($hypervisor) && $active_schedulers{'cfq'}) {
			print_report_bad("CFQ scheduler is bad on virtual machines (hypervisor and/or storage is already dooing I/O scheduling)");
			add_advice("system","urgent","Configure your system to use noop or deadline io scheduler when on virtual machines :\necho deadline > /sys/block/sdX/queue/scheduler\nupdate your kernel parameters line with elevator=deadline to keep this parameter at next reboot");
		}
	}
}

print_header_1("General instance informations");

## Version
{
	print_header_2("Version");
	my $version=get_setting('server_version');
	if ($version=~/rc/) {
		print_report_bad("You are using version $version which is a Release Candidate : do not use in production");
		add_advice("version","urgent","Use a stable version (not a Release Candidate)");
	}
	if (min_version('10')) {
		print_report_ok("You are using last $version");
	} elsif (min_version('9.0')) {
		print_report_warn("You are using version $version which is not the latest version");
		add_advice("version","low","Upgrade to last version");
	} elsif (min_version('8.0')) {
		print_report_bad("You are using version $version which is very old");
		add_advice("version","medium","Upgrade to last version");
	} else {
		print_report_bad("You are using version $version which is very old and is not supported by this script");
		add_advice("version","high","Upgrade to last version");
	}
}

## Uptime
{
	print_header_2("Uptime");
	my $uptime=select_one_value("select extract(epoch from now()-pg_postmaster_start_time())");
	print_report_info("Service uptime : ".format_epoch_to_time($uptime));
	if ($uptime < $day_s) {
		print_report_warn("Uptime is less than 1 day. $script_name result may not be accurate");
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
	print_report_info("Number of activated extensions : ".scalar(@Extensions));
	print_report_info("Activated extensions : @Extensions");
	if (grep(/pg_stat_statements/,@Extensions)) {
		print_report_ok("Extension pg_stat_statements is enabled");
	} else {
		print_report_warn("Extensions pg_stat_statements is disabled in database $database");
		add_advice("extension","low","Enable pg_stat_statements in database $database to collect statistics on all queries (not only queries longer than log_min_duration_statement in logs)");
	}
}

## Users
{
	print_header_2("Users");
	my @ExpiringSoonUsers = select_one_column("select usename from pg_user where valuntil < now()+interval'7 days'");
	if (@ExpiringSoonUsers > 0) {
		print_report_warn("some users account will expire in less than 7 days : ".join(',',@ExpiringSoonUsers));
	} else {
		print_report_ok("No user account will expire in less than 7 days");
	}
	if ($i_am_super) {
		my @BadPasswordUsers = select_one_column("select usename from pg_shadow where passwd='md5'||md5(usename||usename)");
		if (@BadPasswordUsers > 0) {
			print_report_warn("some users account have the username as password : ".join(',',@BadPasswordUsers));
		} else {
			print_report_ok("No user with password=username");
		}
	} else {
		print_report_warn("Unable to check users password, please use a super user instead");
	}
	my $password_encryption=get_setting('password_encryption');
	if ($password_encryption eq 'off') {
		print_report_bad("Password encryption is disable by default. Password will not be encrypted until explicitely asked");
	} else {
		print_report_ok("Password encryption is enabled");
	}
}
## Connections and Memory
{
	print_header_2("Connection information");
	# max_connections
	my $max_connections=get_setting('max_connections');
	print_report_info("max_connections: $max_connections");

	# current connections + ratio
	my $current_connections=select_one_value("select count(1) from pg_stat_activity");
	my $current_connections_percent=$current_connections*100/$max_connections;
	print_report_info("current used connections: $current_connections (".format_percent($current_connections_percent).")");
	if ($current_connections_percent > 70) {
		print_report_warn("You are using more than 70% or your connection. Increase max_connections before saturation of connection slots");
	} elsif ($current_connections_percent > 90) {
		print_report_bad("You are using more that 90% or your connection. Increase max_connections before saturation of connection slots");
	}
	# superuser_reserved_connections
	my $superuser_reserved_connections=get_setting("superuser_reserved_connections");
	my $superuser_reserved_connections_ratio=$superuser_reserved_connections*100/$max_connections;
	if ($superuser_reserved_connections == 0) {
		print_report_bad("No connection slot is reserved for superuser. In case of connection saturation you will not be able to connect to investigate or kill connections");
	} else {
		print_report_info("$superuser_reserved_connections are reserved for super user (".format_percent($superuser_reserved_connections_ratio).")");
	}
	if ($superuser_reserved_connections_ratio > 20) {
		print_report_warn(format_percent($superuser_reserved_connections_ratio)." of connections are reserved for super user. This is too much and can limit other users connections");
	}
	# average connection age
	my $connection_age_average=select_one_value("select extract(epoch from avg(now()-backend_start)) as age from pg_stat_activity");
	print_report_info("Average connection age : ".format_epoch_to_time($connection_age_average));
	if ($connection_age_average < 1 * $min_s) {
		print_report_bad("Average connection age is less than 1 minute. Use a connection pooler to limit new connection/seconds");
	} elsif ($connection_age_average < 10 * $min_s) {
		print_report_warn("Average connection age is less than 10 minutes. Use a connection pooler to limit new connection/seconds");
	}
	# pre_auth_delay
	my $pre_auth_delay=get_setting('pre_auth_delay');
	$pre_auth_delay=~s/s//;
	if ($pre_auth_delay > 0) {
		print_report_bad("pre_auth_delay=$pre_auth_delay : this is a developer feature for debugging and decrease connection delay of $pre_auth_delay seconds");
	}
	# post_auth_delay
	my $post_auth_delay=get_setting('post_auth_delay');
	$post_auth_delay=~s/s//;
	if ($post_auth_delay > 0) {
		print_report_bad("post_auth_delay=$post_auth_delay : this is a developer feature for debugging and decrease connection delay of $post_auth_delay seconds");
	}

	print_header_2("Memory usage");
	# work_mem
	my $work_mem=get_setting('work_mem');
	my $work_mem_total=$work_mem*$work_mem_per_connection_percent/100*$max_connections;
	print_report_info("configured work_mem: ".format_size($work_mem));
	print_report_info("Using an average ratio of work_mem buffers by connection of $work_mem_per_connection_percent% (use --wmp to change it)");
	print_report_info("total work_mem (per connection): ".format_size($work_mem*$work_mem_per_connection_percent/100));
	my $shared_buffers=get_setting('shared_buffers');
	# shared_buffers
	print_report_info("shared_buffers: ".format_size($shared_buffers));
	# track activity
	my $max_processes=get_setting('max_connections')+get_setting('autovacuum_max_workers');
	if (min_version('9.4')) {
		$max_processes+=get_setting('max_worker_processes');
	}
	my $track_activity_size=get_setting('track_activity_query_size')*$max_processes;
	print_report_info("Track activity reserved size : ".format_size($track_activity_size));
	# maintenance_work_mem
	my $maintenance_work_mem=get_setting('maintenance_work_mem');
	my $autovacuum_max_workers=get_setting('autovacuum_max_workers');
	my $maintenance_work_mem_total=$maintenance_work_mem*$autovacuum_max_workers;
	if ($maintenance_work_mem<=64*1024*1024) {
		print_report_warn("maintenance_work_mem is less or equal default value. Increase it to reduce maintenance tasks time");
	} else {
		print_report_info("maintenance_work_mem=".format_size($maintenance_work_mem));
	}
	# total
	my $max_memory=$shared_buffers+$work_mem_total+$maintenance_work_mem_total+$track_activity_size;
	print_report_info("Max memory usage :\n\t\t  shared_buffers (".format_size($shared_buffers).")\n\t\t+ max_connections * work_mem * average_work_mem_buffers_per_connection ($max_connections * ".format_size($work_mem)." * $work_mem_per_connection_percent / 100 = ".format_size($max_connections*$work_mem*$work_mem_per_connection_percent/100).")\n\t\t+ autovacuum_max_workers * maintenance_work_mem ($autovacuum_max_workers * ".format_size($maintenance_work_mem)." = ".format_size($autovacuum_max_workers*$maintenance_work_mem).")\n\t\t+ track activity size (".format_size($track_activity_size).")\n\t\t= ".format_size($max_memory));
	# effective_cache_size
	my $effective_cache_size=get_setting('effective_cache_size');
	print_report_info("effective_cache_size: ".format_size($effective_cache_size));
	# total database size
	my $all_databases_size=select_one_value("select sum(pg_database_size(datname)) from pg_database");
	print_report_info("Size of all databases : ".format_size($all_databases_size));
	# shared_buffer usage
	my $shared_buffers_usage=$all_databases_size/$shared_buffers;
	if ($shared_buffers_usage < 0.7) {
		print_report_warn("shared_buffer is too big for the total databases size, memory is lost");
	}
	# ratio of total RAM
	if (! defined($os->{mem_total})) {
		print_report_unknown("OS total mem unknown : unable to analyse PostgreSQL memory usage");
	} else {
		my $percent_postgresql_max_memory=$max_memory*100/$os->{mem_total};
		print_report_info("PostgreSQL maximum memory usage: ".format_percent($percent_postgresql_max_memory)." of system RAM");
		if ($percent_postgresql_max_memory > 100) {
			print_report_bad("Max possible memory usage for PostgreSQL is more than system total RAM. Add more RAM or reduce PostgreSQL memory");
		} elsif ($percent_postgresql_max_memory > 80) {
			print_report_warn("Max possible memory usage for PostgreSQL is more than 90% of system total RAM.");
		} elsif ($percent_postgresql_max_memory < 60) {
			print_report_warn("Max possible memory usage for PostgreSQL is less than 60% of system total RAM. On a dedicated host you can increase PostgreSQL buffers to optimize performances.");
		} else {
			print_report_ok("Max possible memory usage for PostgreSQL is good");
		}
		# track activity ratio
		my $track_activity_ratio=$track_activity_size*100/$os->{mem_total};
		if ($track_activity_ratio > 1) {
			print_report_warn("Track activity reserved size is more than 1% of your RAM");
			add_advice("track_activity","low","Your track activity reserved size is too high. Reduce track_activity_query_size and/or max_connections");
		}
		# total ram usage with effective_cache_size
		my $percent_mem_usage=($max_memory+$effective_cache_size)*100/$os->{mem_total};
		print_report_info("max memory+effective_cache_size is ".format_percent($percent_mem_usage)." of total RAM");
		if ($percent_mem_usage < 60 and $shared_buffers_usage > 1) {
			print_report_warn("Increase shared_buffers and/or effective_cache_size to use more memory");
		} elsif ($percent_mem_usage > 90) {
			print_report_warn("the sum of max_memory and effective_cache_size is too high, the planer can find bad plans if system cache is smaller than expected");
		}
	}

}

## Logs
{
	print_header_2("Logs");
	# log hostname
	my $log_hostname=get_setting('log_hostname');
	if ($log_hostname eq 'on') {
		print_report_bad("log_hostname is on : this will decrease connection performance due to reverse DNS lookup");
	} else {
		print_report_ok("log_hostname is off : no reverse DNS lookup latency");
	}

	# log_min_duration_statement
	my $log_min_duration_statement=get_setting('log_min_duration_statement');
	$log_min_duration_statement=~s/ms//;
	if ($log_min_duration_statement == -1 ) {
		print_report_warn("log of long queries is desactivated. It will be more difficult to optimize query performances");
	} elsif ($log_min_duration_statement < 1000 ) {
		print_report_bad("log_min_duration_statement=$log_min_duration_statement : all requests of more than 1 sec will be written in log. It can be disk intensive (I/O and space)");
	} else {
		print_report_ok("long queries will be logged");
	}

	# log_statement
	my $log_statement=get_setting('log_statement');
	if ($log_statement eq 'all') {
		print_report_bad("log_statement=all : this is very disk intensive and only usefull for debug");
	} elsif ($log_statement eq 'mod') {
		print_report_warn("log_statement=mod : this is disk intensive");
	} else {
		print_report_ok("log_statement=$log_statement");
	}
}

## Two phase commit
{
	print_header_2("Two phase commit");
	if (min_version('9.2')) {
		my $prepared_xact_count=select_one_value("select count(1) from pg_prepared_xacts");
		if ($prepared_xact_count == 0) {
			print_report_ok("Currently no two phase commit transactions");
		} else {
			print_report_warn("There are currently $prepared_xact_count two phase commit prepared transactions. If they are too long they can lock objects.");
			my $prepared_xact_lock_count=select_one_value("select count(1) from pg_locks where transactionid in (select transaction from pg_prepared_xacts)");
			if ($prepared_xact_lock_count > 0) {
				print_report_bad("Two phase commit transactions have $prepared_xact_lock_count locks !");
			} else {
				print_report_ok("No locks for theses $prepared_xact_count transactions");
			}
		}
	} else {
		print_report_warn("This version does not yet support two phase commit");
	}
}

## Autovacuum
{
	print_header_2("Autovacuum");
	if (get_setting('autovacuum') eq 'on') {
		print_report_ok('autovacuum is activated.');
		my $autovacuum_max_workers=get_setting('autovacuum_max_workers');
		print_report_info("autovacuum_max_workers: $autovacuum_max_workers");
	} else {
		print_report_bad('autovacuum is not activated. This is bad except if you known what you do.');
	}
}

## Checkpoint
{
	print_header_2("Checkpoint");
	my $checkpoint_completion_target=get_setting('checkpoint_completion_target');
	if ($checkpoint_completion_target < 0.5) {
		print_report_bad("checkpoint_completion_target($checkpoint_completion_target) is lower than default (0.5)");
		add_advice("checkpoint","urgent","Your checkpoint completion target is too low. Put something nearest from 0.8/0.9 to balance your writes better during the checkpoint interval");
	} elsif ($checkpoint_completion_target >= 0.5 and $checkpoint_completion_target <= 0.7) {
		print_report_warn("checkpoint_completion_target($checkpoint_completion_target) is low");
		add_advice("checkpoint","medium","Your checkpoint completion target is too low. Put something nearest from 0.8/0.9 to balance your writes better during the checkpoint interval");
	} elsif ($checkpoint_completion_target >= 0.7 and $checkpoint_completion_target <= 0.9) {
		print_report_ok("checkpoint_completion_target($checkpoint_completion_target) OK");
	} elsif ($checkpoint_completion_target > 0.9 and $checkpoint_completion_target < 1) {
		print_report_warn("checkpoint_completion_target($checkpoint_completion_target) is too near to 1");
		add_advice("checkpoint","medium","Your checkpoint completion target is too high. Put something nearest from 0.8/0.9 to balance your writes better during the checkpoint interval");
	} else {
		print_report_bad("checkpoint_completion_target too high ($checkpoint_completion_target)");
	}
}

## Disk access
{
	print_header_2("Disk access");
	my $fsync=get_setting('fsync');
	my $wal_sync_method=get_setting('wal_sync_method');
	if ($fsync eq 'on') {
		print_report_ok("fsync is on");
	} else {
		print_report_bad("fsync is off. You can loss data in case of crash");
		add_advice("checkpoint","urgent","set fsync to on. You can loose data in case of database crash !");
	}
	if ($os->{name} eq 'darwin') {
		if ($wal_sync_method ne 'fsync_writethrough') {
			print_report_bad("wal_sync_method is $wal_sync_method. Settings other than fsync_writethrough can lead to loss of data in case of crash");
			add_advice("disk access","urgent","set wal_sync_method to fsync_writethrough to on. Otherwise, the disk write cache may prevent recovery after a crash.");
		} else {
			print_report_ok("wal_sync_method is $wal_sync_method");
		}
	}
	if (get_setting('synchronize_seqscans') eq 'on') {
		print_report_ok("synchronize_seqscans is on");
	} else {
		print_report_warn("synchronize_seqscans is off");
		add_advice("seqscan","medium","set synchronize_seqscans to synchronize seqscans and reduce disks I/O");
	}
}

## WAL / PITR
{
	print_header_2("WAL");
	if (min_version('9.0')) {
		my $wal_level=get_setting('wal_level');
		if ($wal_level eq 'minimal') {
			print_report_bad("The wal_level minimal does not allow PITR backup and recovery");
			add_advice("backup","urgent","Configure your wal_level to a level which allow PITR backup and recovery");
		}
	} else {
		print_report_warn("wal_level is not supported on ".get_setting('server_version'));
	}
}

## Planner
{
	print_header_2("Planner");
	# Modified costs settings
	my @ModifiedCosts=select_one_column("select name from pg_settings where name like '%cost%' and setting<>boot_val;");
	if (@ModifiedCosts > 0) {
		print_report_warn("some costs settings are not the defaults : ".join(',',@ModifiedCosts).". This can have bad impacts on performance. Use at your own risks");
	} else {
		print_report_ok("costs settings are defaults");
	}

	# random vs seq page cost on SSD
	if (!defined($rotational_disks)) {
		print_report_unknown("Information about rotational/SSD disk is unknown : unable to check random_page_cost and seq_page_cost tuning");
	} else {
		if ($rotational_disks == 0 and get_setting('random_page_cost')>get_setting('seq_page_cost')) {
			print_report_warn("With SSD storage, set random_page_cost=seq_page_cost to help planer use more index scan");
			add_advice("planner","medium","Set random_page_cost=seq_page_cost on SSD disks");
		} elsif ($rotational_disks > 0 and get_setting('random_page_cost')<=get_setting('seq_page_cost')) {
			print_report_bad("Without SSD storage, random_page_cost must be more than seq_page_cost");
			add_advice("planner","urgent","Set random_page_cost to 2-4 times more than seq_page_cost without SSD storage");
		}
	}

	# disabled plan fonctions
	my @DisabledPlanFunctions=select_one_column("select name,setting from pg_settings where name like 'enable_%' and setting='off';");
	if (@DisabledPlanFunctions > 0) {
		print_report_bad("some plan features are disabled : ".join(',',@DisabledPlanFunctions));
	} else {
		print_report_ok("all plan features are enabled");
	}

}

# Database information
print_header_1("Database information for database $database");

## Database size
{
	print_header_2("Database size");
	my $sum_total_relation_size=select_one_value("select sum(pg_total_relation_size(schemaname||'.'||quote_ident(tablename))) from pg_tables");
	print_report_info("Database $database total size : ".format_size($sum_total_relation_size));
	if (min_version('9.0')) {
		my $sum_table_size=select_one_value("select sum(pg_table_size(schemaname||'.'||quote_ident(tablename))) from pg_tables");
		my $sum_index_size=$sum_total_relation_size-$sum_table_size;
		#print_report_debug("sum_total_relation_size: $sum_total_relation_size");
		#print_report_debug("sum_table_size: $sum_table_size");
		#print_report_debug("sum_index_size: $sum_index_size");
		my $table_percent=$sum_table_size*100/$sum_total_relation_size;
		my $index_percent=$sum_index_size*100/$sum_total_relation_size;
		print_report_info("Database $database tables size : ".format_size($sum_table_size)." (".format_percent($table_percent).")");
		print_report_info("Database $database indexes size : ".format_size($sum_index_size)." (".format_percent($index_percent).")");
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
			print_report_bad("Some tablespaces are in PGDATA : ".join(' ',keys(%{$tablespaces_in_pgdata})));
			add_advice('tablespaces','urgent','Some tablespaces are in PGDATA. Move them outside of this folder.');
		}
	} else {
		print_report_unknown("This check is not supported before 9.2");
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
			print_report_info("shared buffer idx hit rate too high. You can reducte shared_buffer if you need");
		} elsif ($shared_buffer_idx_hit_rate>98) {
			print_report_ok("Shared buffer idx hit rate is very good");
		} elsif ($shared_buffer_idx_hit_rate>90) {
			print_report_warn("Shared buffer idx hit rate is quite good. Increase shared_buffer memory to increase hit rate");
		} else {
			print_report_bad("Shared buffer idx hit rate is too low. Increase shared_buffer memory to increase hit rate");
		}
	}
}

## Indexes
{
	print_header_2("Indexes");
	# Invalid indexes
	{
		my @Invalid_indexes=select_one_column("select relname from pg_index join pg_class on indexrelid=oid where indisvalid=false");
		if (@Invalid_indexes > 0) {
			print_report_bad("There are invalid indexes in the database : @Invalid_indexes");
			add_advice("index","urgent","You have invalid indexes in the database. Please check/rebuild them");
		} else {
			print_report_ok("No invalid indexes");
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
			print_report_warn("Some indexes are unused since last statistics: @Unused_indexes");
			add_advice("index","medium","You have unused indexes in the database since last statistics. Please remove them if they are never use");
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
		my @Default_cost_procs=select_one_column("select n.nspname||'.'||p.proname from pg_catalog.pg_proc p left join pg_catalog.pg_namespace n on n.oid = p.pronamespace where pg_catalog.pg_function_is_visible(p.oid) and n.nspname not in ('pg_catalog','information_schema') and p.prorows<>1000 and p.procost<>10");
		if (@Default_cost_procs > 0) {
			print_report_warn("Some user procedures does not have custom cost and rows settings : @Default_cost_procs");
			add_advice("proc","low","You have custom procedures with default cost and rows setting. Please reconfigure them with specific values to help the planer");
		} else {
			print_report_ok("No procedures with default costs");
		}
	}
}

$dbh->disconnect();

print_advices();

exit(0);




sub min_version {
	my $min_version=shift;
	my $cur_version=get_setting('server_version');
	$cur_version=~s/rc.*//; # clean RC
	my ($min_major,$min_minor)=split(/\./,$min_version);
	my ($cur_major,$cur_minor)=split(/\./,$cur_version);
	if ($cur_major > $min_major) {
		return 1;
	} elsif ($cur_major == $min_major) {
		if (defined($min_minor)) {
			if ($cur_minor >= $min_minor) {
				return 1;
			} else {
				return 0;
			}
		} else {
			return 1;
		}
	}
	return 0;
}

# execute SELECT query, return result as hashref on key
sub select_all_hashref {
	my ($query,$key)=@_;
	if (!defined($query) or !defined($key)) {
		print STDERR "ERROR : Missing query or key\n";
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
		print STDERR "ERROR : Missing query\n";
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
		print STDERR "ERROR : Missing query\n";
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

sub print_report_ok		{ print_report('ok'	,shift); }
sub print_report_warn		{ print_report('warn'	,shift); }
sub print_report_bad		{ print_report('bad'	,shift); }
sub print_report_info		{ print_report('info'	,shift); }
sub print_report_todo		{ print_report('todo'	,shift); }
sub print_report_unknown	{ print_report('unknown',shift); }
sub print_report_debug		{ print_report('debug'	,shift); }

sub print_report {
	my ($type,$message)=@_;
	if ($type eq "ok") {
		print STDOUT color('green')  ."[OK]      ".color('reset').$message."\n";
	} elsif ($type eq "warn") {
		print STDOUT color('yellow') ."[WARN]    ".color('reset').$message."\n";
	} elsif ($type eq "bad") {
		print STDERR color('red')    ."[BAD]     ".color('reset').$message."\n";
	} elsif ($type eq "info") {
		print STDOUT color('white')  ."[INFO]    ".color('reset').$message."\n";
	} elsif ($type eq "todo") {
		print STDERR color('magenta')."[TODO]    ".color('reset').$message."\n";
	} elsif ($type eq "unknown") {
		print STDOUT color('cyan')   ."[UNKNOWN] ".color('reset').$message."\n";
	} elsif ($type eq "debug") {
		print STDERR color('magenta')."[DEBUG]   ".color('reset').$message."\n";
	} else {
		print STDERR "ERROR: bad report type $type\n";
		exit 1;
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
		print STDERR "ERROR: setting $name does not exists\n";
		exit 1;
	} else {
    return standard_units($settings->{$name}->{setting}, $settings->{$name}->{unit});
  }
}
sub standard_units {
  my $value=shift;
  my $unit=shift;
  return $value         if !$unit;
  return $value*1024    if $unit eq 'kB' || $unit eq 'K';
  return $value*8*1024  if $unit eq '8kB';
  return $value*16*1024 if $unit eq '16kB';
  return $value*1024*1024 if $unit eq 'M';
  return $value*1024*1024*1024 if $unit eq 'G';
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
		print STDERR "# Missing Perl module '$mod'. Please install it\n";
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
	die("unknown priority $priority") if ($priority !~ /(urgent|medium|low)/);
	push(@{$advices{$category}{$priority}},$advice);
}

sub print_advices {
	print "\n";
	print_header_1("Configuration advices");
	my $advice_count=0;
	foreach my $category (sort(keys(%advices))) {
		print_header_2($category);
		foreach my $priority (sort(keys(%{$advices{$category}}))) {
			print color("red")     if $priority eq "urgent";
			print color("yellow")  if $priority eq "medium";
			print color("magenta") if $priority eq "low";
			foreach my $advice (@{$advices{$category}{$priority}}) {
				print "[".uc($priority)."] $advice\n";
				$advice_count++;
			}
			print color("reset");
		}
	}
	if ($advice_count == 0) {
		print color("green")."Everything is good".color("reset")."\n";
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

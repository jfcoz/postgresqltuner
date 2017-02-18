#!/usr/bin/perl -w

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
my $nmmc=0; # needed missing modules count
$nmmc+=try_load("Getopt::Long",{});
$nmmc+=try_load("DBD::Pg",
	{
		'/etc/debian_version'=>'apt-get install -y libdbd-pg-perl',
		'/etc/redhat-release'=>'yum install -y perl-DBD-Pg'
	});
$nmmc+=try_load("DBI",
	{
		'/etc/debian_version'=>'apt-get install -y libdbi-perl',
		'/etc/redhat-release'=>'yum install -y perl-DBI'
	});
$nmmc+=try_load("Term::ANSIColor",
	{
		'/etc/debian_version'=>'apt-get install -y perl-modules',
		'/etc/redhat-release'=>'yum install -y perl-DBI'
	});
if ($nmmc > 0) {
	print STDERR "# Please install theses Perl modules\n";
	exit 1;
}

my $script_version="0.0.5";
my $script_name="postgresqltuner.pl";
my $min_s=60;
my $hour_s=60*$min_s;
my $day_s=24*$hour_s;
my $os_cmd_prefix='';

my $host='/var/run/postgresql';
my $username='postgres';
my $password='';
my $database="template1";
my $port=5432;
my $help=0;
GetOptions (
	"host=s"        => \$host,
	"user=s"        => \$username,
	"username=s"    => \$username,
	"pass=s"        => \$password,
	"password=s"    => \$password,
	"db=s"          => \$database,
	"database=s"    => \$database,
	"port=i"        => \$port,
	"help"          => \$help,
) or usage(1);

print "$script_name version $script_version\n";
if ($help) {
	usage(0);
}

usage(1) if (!defined($host) or !defined($username) or !defined($password));

sub usage {
	my $return=shift;
	print STDERR "usage: $script_name --host [ hostname | /var/run/postgresql ] [--user username] [--password password] [--database database] [--port port]\n";
	exit $return;
}

print "Connecting to $host:$port database $database with user $username...\n";
my $dbh = DBI->connect("dbi:Pg:dbname=$database;host=$host",$username,$password,{AutoCommit=>1,RaiseError=>1,PrintError=>0});

# Collect datas
my $users=select_all_hashref("select * from pg_user","usename");
my $i_am_super=$users->{$username}->{usesuper};
my $settings=select_all_hashref("select * from pg_settings","name");
my @Extensions=select_one_column("select extname from pg_extension");
my $os={};
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
	if ($host =~ /^\//) {
		$os_cmd_prefix='';
	} elsif ($host =~ /^localhost$/) {
		$os_cmd_prefix='';
	} elsif ($host =~ /^127\.[0-9]+\.[0-9]+\.[0-9]+$/) {
		$os_cmd_prefix='';
	} elsif ($host =~ /^[a-zA-Z0-9.-]+$/) {
		$os_cmd_prefix="ssh $host ";
	} else {
		die("Invalid host $host");
	}
	if (! defined(os_cmd("true"))) {
		print_report_unknown("Unable to connect via ssh to $host. Please configure your ssh client to allow to connect to $host with key authentication, and accept key at first connection. For now you will not have OS information");
		add_advice("report","urgent","Please configure your .ssh/config to allow postgresqltuner.pl to connect via ssh to $host without password authentication. This will allow to collect more system informations");
	} else {
		# OS version
		my $os_version=os_cmd("cat /etc/issue");
		$os_version=~s/\n//g;
		print_report_info("OS: $os_version");
		# OS Memory
		my $os_mem=os_cmd("free -b");
		($os->{mem_total},$os->{mem_used},$os->{mem_free},$os->{mem_shared},$os->{mem_buffers},$os->{mem_cached})=($os_mem =~ /Mem:\s+([0-9]+)\s+([0-9]+)\s+([0-9]+)\s+([0-9]+)\s+([0-9]+)\s+([0-9]+)/);
		($os->{swap_total},$os->{swap_used},$os->{swap_free})=($os_mem =~ /Swap:\s+([0-9]+)\s+([0-9]+)\s+([0-9]+)/);
		print_report_info("OS total memory: ".format_size($os->{mem_total}));
		# Overcommit
		my $overcommit_memory=get_sysctl('vm.overcommit_memory');
		if ($overcommit_memory != 2) {
			print_report_bad("Memory overcommitment is allowed on the system. This can lead to OOM Killer killing some PostgreSQL process, which will cause a PostgreSQL server restart (crash recovery)");
			add_advice('sysctl','urgent','set vm.overcommit_memory=2 in /etc/sysctl.conf and run sysctl -p to reload it. This will disable memory overcommitment and avoid postgresql killed by OOM killer.');
			my $overcommit_ratio=get_sysctl('vm.overcommit_ratio');
			print_report_info("sysctl vm.overcommit_ratio=$overcommit_ratio");
			if ($overcommit_ratio < 50) {
				print_report_bad("vm.overcommit_memory is too small, you will not be able to use more than $overcommit_ratio*RAM+SWAP for applications");
			} elsif ($overcommit_ratio > 90) {
				print_report_bad("vm.overcommit_ratio is too high, you need to keep free space for the kernel");
			}
		} else {
			print_report_ok("vm.overcommit_memory is good : no memory overcommitment");
		}
		# Hardware
		my $hypervisor='';
		my @dmesg=os_cmd("dmesg");
		foreach my $line (@dmesg) {
			if ($line =~ /vmware/i) {
				$hypervisor='VMware';
				last;
			} elsif ($line =~ /kvm/i) {
				$hypervisor='KVM';
				last;
			} elsif ($line =~ /xen/i) {
				$hypervisor='XEM';
				last;
			} elsif ($line =~ /vbox/i) {
				$hypervisor='VirtualBox';
				last;
			} elsif ($line =~ /hyper-v/i) {
				$hypervisor='Hyper-V';
				last;
			}
		}
		if ($hypervisor) {
			print_report_info("Running in $hypervisor hypervisor");
		} else {
			print_report_info("Running on physical machine");
		}
		# I/O scheduler
		my $schedulers=os_cmd("cat /sys/block/*/queue/scheduler");
		my %active_schedulers;
		foreach my $line (split(/\n/,$schedulers)) {
			next if ($line eq 'none');
			foreach my $scheduler (split(/ /,$line)) {
				if ($scheduler =~ /^\[([a-z]+)\]$/) {
					$active_schedulers{$1}++;
				}
			}
		}
		print_report_info("Currently used I/O scheduler(s) : ".join(',',keys(%active_schedulers)));
		if ($hypervisor && $active_schedulers{'cfq'}) {
			print_report_bad("CFQ scheduler is bad on virtual machines (hypervisor and/or storage is already dooing I/O scheduling)");
			add_advice("system","urgent","Configure your system to use noop or deadline io scheduler when on virtual machines :\necho deadline > /sys/block/sdX/queue/scheduler\nupdate your kernel parameters line with elevator=deadline to keep this parameter at next reboot");
		}
	}
}

print_header_1("General instance informations");

my ($v1,$v2,$v3);
## Version
{
	print_header_2("Version");
	my $version=get_setting('server_version');
	($v1,$v2,$v3)=split(/\./,$version);
	if ($v1<9) {
		print_report_bad("You are using version $version which is very old");
	} elsif ($v1 == 9 and $v2 < 6) {
		print_report_warn("You are using version $version which is not the latest version");
	} elsif ($v1 == 9 and $v2 == 6) {
		print_report_ok("You are using last $version");
	} else {
		print_report_bad("Version $version is unknown to $script_name $script_version : you may use an old version of this script");
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
		my @BadPasswordUsers = select_one_column("select usename from pg_shadow where passwd=concat('md5',md5(concat(usename,usename)))");
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
	print_report_info("work_mem (per connection): ".format_size($work_mem));
	my $shared_buffers=get_setting('shared_buffers');
	# shared_buffers
	print_report_info("shared_buffers: ".format_size($shared_buffers));
	my $max_memory=$shared_buffers+$max_connections*$work_mem;
	print_report_info("Max memory usage (shared_buffers + max_connections*work_mem): ".format_size($max_memory));
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
		# total ram usage with effective_cache_size
		my $percent_mem_usage=($max_memory+$effective_cache_size)*100/$os->{mem_total};
		print_report_info("max memory+effective_cache_size is ".format_percent($percent_mem_usage)." of total RAM");
		if ($percent_mem_usage < 60 and $shared_buffers_usage > 1) {
			print_report_warn("Increase shared_buffers and/or effective_cache_size to use more memory");
		} elsif ($percent_mem_usage > 90) {
			print_report_warn("the sum of shared_buffers and effective_cache_size is too high, the planer can find bad plans if system cache is smaller than expected");
		}
	}

	# maintenance_work_mem
	my $maintenance_work_mem=get_setting('maintenance_work_mem');
	if ($maintenance_work_mem<=64*1024*1024) {
		print_report_warn("maintenance_work_mem is less or equal default value. Increase it to reduce maintenance tasks time");
	} else {
		print_report_info("maintenance_work_mem=".format_size($maintenance_work_mem));
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
	if (($v1>=9) and ($v2>=2)) {
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
	if ($fsync eq 'on') {
		print_report_ok("fsync is on");
	} else {
		print_report_bad("fsync is off. You can loss data in case of crash");
		add_advice("checkpoint","urgent","set fsync to on. You can loose data in case of database crash !");
	}
}

## WAL / PITR
{
	print_header_2("WAL");
	my $wal_level=get_setting('wal_level');
	if ($wal_level eq 'minimal') {
		print_report_bad("The wal_level minimal does not allow PITR backup and recovery");
		add_advice("backup","urgent","Configure your wal_level to a level which allow PITR backup and recovery");
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
	my $sum_total_relation_size=select_one_value("select sum(pg_total_relation_size(schemaname||'.'||tablename)) from pg_tables");
	my $sum_table_size=select_one_value("select sum(pg_table_size(schemaname||'.'||tablename)) from pg_tables");
	my $sum_index_size=$sum_total_relation_size-$sum_table_size;
	#print_report_debug("sum_total_relation_size: $sum_total_relation_size");
	#print_report_debug("sum_table_size: $sum_table_size");
	#print_report_debug("sum_index_size: $sum_index_size");
	my $table_percent=$sum_table_size*100/$sum_total_relation_size;
	my $index_percent=$sum_index_size*100/$sum_total_relation_size;
	print_report_info("Database $database total size : ".format_size($sum_total_relation_size));
	print_report_info("Database $database tables size : ".format_size($sum_table_size)." (".format_percent($table_percent).")");
	print_report_info("Database $database indexes size : ".format_size($sum_index_size)." (".format_percent($index_percent).")");
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
}


$dbh->disconnect();

print_advices();

exit(0);


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
		return $settings->{$name}->{setting}         if !$settings->{$name}->{unit};
		return $settings->{$name}->{setting}*1024    if $settings->{$name}->{unit} eq 'kB';
		return $settings->{$name}->{setting}*8*1024  if $settings->{$name}->{unit} eq '8kB';
		return $settings->{$name}->{setting}*16*1024 if $settings->{$name}->{unit} eq '16kB';
		return $settings->{$name}->{setting}.'s'     if $settings->{$name}->{unit} eq 's';
		return $settings->{$name}->{setting}.'ms'    if $settings->{$name}->{unit} eq 'ms';
	}
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
	if (open(my $ctl,"</proc/sys/$name")) {
		my $value=<$ctl>;
		close($ctl);
		chomp($value);
		return $value;
	} else {
		print_report_warn("Unable to open sysctl $name");
		return undef;
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
		foreach my $priority (sort(keys($advices{$category}))) {
			print color("red")     if $priority eq "urgent";
			print color("yellow")  if $priority eq "medium";
			print color("magenta") if $priority eq "low";
			foreach my $advice (@{$advices{$category}{$priority}}) {
				print "$advice\n";
				$advice_count++;
			}
			print color("reset");
		}
	}
	if ($advice_count == 0) {
		print color("green")."Everything is good".color("reset")."\n";
	}
}

#!/usr/bin/perl -w

# Copyright 2016 Julien Francoz <julien-postgresqltuner@francoz.net>

use strict;
use Getopt::Long;
use DBI;
use Term::ANSIColor;

my $script_version="0.0.2";
my $script_name="postgresqltuner.pl";

my $host='/var/run/postgresql';
my $username='';
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
my $settings=db_select_all_hashref("select * from pg_settings","name");


# Report

#use Data::Dumper; print Dumper($settings);

## Version
{
	my $version=get_setting('server_version');
	my ($v1,$v2,$v3)=split(/\./,$version);
	if ($v1<9) {
		report_bad("You are using version $version which is very old");
	} elsif ($v1 == 9 and $v2 < 6) {
		report_warn("You are using version $version which is not the latest version");
	} elsif ($v1 == 9 and $v2 == 6) {
		report_ok("You are using last $version");
	} else {
		report_bad("Version $version is unknown to $script_name $script_version : you may use an old version of this script");
	}
}

## Uptime
{
	my $uptime=db_select_one_value("select now()-pg_postmaster_start_time()");
	report_info("Service uptime : $uptime");
	if ($uptime !~ /day/) {
		report_warn("Uptime is less than 1 day. $script_name result may not be accurate");
	}
}

## Database size
{
	my $sum_total_relation_size=db_select_one_value("select sum(pg_total_relation_size(schemaname||'.'||tablename)) from pg_tables");
	my $sum_relation_size=db_select_one_value("select sum(pg_relation_size(schemaname||'.'||tablename)) from pg_tables");
	my $sum_index_size=$sum_total_relation_size-$sum_relation_size;
	my $relation_percent=$sum_relation_size*100/$sum_total_relation_size;
	my $index_percent=$sum_index_size*100/$sum_total_relation_size;
	report_info("Database total size : ".size_pretty($sum_total_relation_size));
	report_info("Database tables size : ".size_pretty($sum_relation_size)." (".percent_format($relation_percent)."%)");
	report_info("Database indexes size : ".size_pretty($sum_index_size)." (".percent_format($index_percent)."%)");
}

## Connections and Memory
{
	my $max_connections=get_setting('max_connections');
	report_info("max_connections: $max_connections");
	my $current_connections=db_select_one_value("select count(1) from pg_stat_activity");
	my $current_connections_percent=$current_connections*100/$max_connections;
	report_info("current used connections: $current_connections (".percent_format($current_connections_percent)."%)");
	if ($current_connections_percent > 70) {
		report_warn("You are using more than 70% or your connection. Increase max_connections before saturation of connection slots");
	} elsif ($current_connections_percent > 90) {
		report_bad("You are using more that 90% or your connection. Increase max_connections before saturation of connection slots");
	}
	my $connection_age_average=db_select_one_value("select extract(epoch from avg(now()-backend_start)) as age from pg_stat_activity");
	report_info("Average connection age : ".epoch_to_time($connection_age_average));
	if ($connection_age_average < 60) {
		report_bad("Average connection age is less than 60 seconds. Use a connection pooler to limit new connection/seconds");
	} elsif ($connection_age_average < 600) {
		report_warn("Average connection age is less than 600 seconds. Use a connection pooler to limit new connection/seconds");
	}
	report_todo("calculate connections/sec from pid variation");
	my $work_mem=get_setting('work_mem');
	report_info("work_mem (per connection): ".size_pretty($work_mem));
	my $shared_buffers=get_setting('shared_buffers');
	report_info("shared_buffers: ".size_pretty($shared_buffers));
	my $max_memory=$shared_buffers+$max_connections*$work_mem;
	report_info("Max memory usage (shared_buffers + max_connections*work_mem): ".size_pretty($max_memory));
	report_todo("compare to system memory");
}

## Shared buffer usage
{
	### Heap hit rate
	{
		my $shared_buffer_heap_hit_rate=db_select_one_value("select sum(heap_blks_hit)*100/(sum(heap_blks_read)+sum(heap_blks_hit)+1) from pg_statio_all_tables ;");
		report_info("shared_buffer_heap_hit_rate: $shared_buffer_heap_hit_rate");
	}
	### TOAST hit rate
	{
		my $shared_buffer_toast_hit_rate=db_select_one_value("select sum(toast_blks_hit)*100/(sum(toast_blks_read)+sum(toast_blks_hit)+1) from pg_statio_all_tables ;");
		report_info("shared_buffer_toast_hit_rate: $shared_buffer_toast_hit_rate");
	}
	# Tidx hit rate
	{
		my $shared_buffer_tidx_hit_rate=db_select_one_value("select sum(tidx_blks_hit)*100/(sum(tidx_blks_read)+sum(tidx_blks_hit)+1) from pg_statio_all_tables ;");
		report_info("shared_buffer_tidx_hit_rate: $shared_buffer_tidx_hit_rate");
	}
	# Idx hit rate
	{
		my $shared_buffer_idx_hit_rate=db_select_one_value("select sum(idx_blks_hit)*100/(sum(idx_blks_read)+sum(idx_blks_hit)+1) from pg_statio_all_tables ;");
		report_info("shared_buffer_idx_hit_rate: $shared_buffer_idx_hit_rate");
		if ($shared_buffer_idx_hit_rate > 99.99) {
			report_info("shared buffer idx hit rate too high. You can reducte shared_buffer if you need");
		} elsif ($shared_buffer_idx_hit_rate>98) {
			report_ok("Shared buffer idx hit rate is very good");
		} elsif ($shared_buffer_idx_hit_rate>90) {
			report_warn("Shared buffer idx hit rate is quite good. Increase shared_buffer memory to increase hit rate");
		} else {
			report_bad("Shared buffer idx hit rate is too low. Increase shared_buffer memory to increase hit rate");
		}
	}
}

## Autovacuum
{
	if (get_setting('autovacuum') eq 'on') {
		report_ok('autovacuum is activated.');
	} else {
		report_bad('autovacuum is not activated. This is bad except if you known what you do.');
	}
}

## Checkpoint
{
	my $checkpoint_completion_target=get_setting('checkpoint_completion_target');
	if ($checkpoint_completion_target < 0.5) {
		report_warn("checkpoint_completion_target($checkpoint_completion_target) is lower that default(0,5)");
	} elsif ($checkpoint_completion_target >= 0.5 and $checkpoint_completion_target <= 0.9) {
		report_ok("checkpoint_completion_target($checkpoint_completion_target) OK");
	} elsif ($checkpoint_completion_target > 0.9 and $checkpoint_completion_target < 1) {
		report_warn("checkpoint_completion_target($checkpoint_completion_target) is too near to 1");
	} else {
		report_bad("checkpoint_completion_target too high ($checkpoint_completion_target)");
	}
}
	
## File
{
	my $fsync=get_setting('fsync');
	if ($fsync eq 'on') {
		report_ok("fsync is on");
	} else {
		report_bad("fsync is off. You can loss data in case of crash");
	}
}

## PITR
{
	my $wal_level=get_setting('wal_level');
	if ($wal_level eq 'minimal') {
		report_bad("The wal_level minimal does not allow PITR backup and recovery");
	}
}

#report_ok('ok');
#report_warn('warning');
#report_bad('bad');
#report_unknown('unknown');



$dbh->disconnect();


# execute SELECT query, return result as hashref on key
sub db_select_all_hashref {
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
sub db_select_one_value {
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
sub report_ok      { print_report('ok'     ,shift); }
sub report_warn    { print_report('warn'   ,shift); }
sub report_bad     { print_report('bad'    ,shift); }
sub report_info    { print_report('info'   ,shift); }
sub report_todo    { print_report('todo'   ,shift); }
sub report_unknown { print_report('unknown',shift); }

sub print_report {
	my ($type,$message)=@_;
	if ($type eq "ok") {
		print color('green');
		print "[OK]      ";
		print color('reset');
	} elsif ($type eq "warn") {
		print color('yellow');
		print "[WARN]    ";
		print color('reset');
	} elsif ($type eq "bad") {
		print color('red');
		print "[BAD]     ";
		print color('reset');
	} elsif ($type eq "info") {
		print color('blue');
		print "[INFO]    ";
		print color('reset');
	} elsif ($type eq "todo") {
		print color('magenta');
		print "[TODO]    ";
		print color('reset');
	} elsif ($type eq "unknown") {
		print color('cyan');
		print "[UNKNOWN] ";
		print color('reset');
	} else {
		print STDERR "ERROR: bad report type $type\n";
		exit 1;
	}
	print "$message\n";
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

sub size_pretty {
	my $size=shift;
        my @units=('','K','M','G','T','P');
        my $unit_index=0;
        return 0 if !defined($size);
        while ($size>1024) {
                $size=$size/1024;
                $unit_index++;
        }
        return sprintf("%.2f %s",$size,$units[$unit_index]);
}

sub percent_format {
	my $value=shift;
	return sprintf("%.2f",$value);
}

sub epoch_to_time {
	my $epoch=shift;
	my $time='';
	if ($epoch > 86400) {
		my $days=sprintf("%d",$epoch/86400);
		$epoch=$epoch%86400;
		$time.=$days.'d';
	}
	if ($epoch > 3600) {
		my $hours=sprintf("%d",$epoch/3600);
		$epoch=$epoch%3600;
		$time.=' '.sprintf("%02d",$hours).'h';
	}
	if ($epoch > 60) {
		my $mins=sprintf("%d",$epoch/60);
		$epoch=$epoch%60;
		$time.=' '.sprintf("%02d",$mins).'m';
	}
	$time.=' '.sprintf("%02d",$epoch).'s';
	return $time;
}

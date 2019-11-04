# postgresqltuner.pl

[![Build Status](https://travis-ci.org/jfcoz/postgresqltuner.svg?branch=master)](https://travis-ci.org/jfcoz/postgresqltuner)
[![Donate](https://liberapay.com/assets/widgets/donate.svg)](https://liberapay.com/CoCoZ/donate)

`postgresqltuner.pl` is a simple script to analyse your PostgreSQL database. It is inspired by [mysqltuner.pl](https://github.com/major/MySQLTuner-perl)

## Demo

Sample output:
~~~
postgresqltuner.pl version 1.0.1
Checking if OS commands are available on /var/run/postgresql...
[OK]      I can run OS commands
Connecting to /var/run/postgresql:5432 database template1 with user postgres...
[OK]      The user acount used for reporting has superuser rights on this PostgreSQL instance
=====  OS information  =====
[INFO]    OS: linux Version: 4.9.0 Arch: x86_64-linux-gnu-thread-multi
[INFO]    OS total memory: 94.36 GB
[OK]      vm.overcommit_memory is good: no memory overcommitment
[INFO]    Running (probably) directly on a physical machine
[INFO]    Currently used I/O scheduler(s): mq-deadline
=====  General instance informations  =====
-----  Version  -----
[OK]      You are using the latest major version (11.5 (Debian 11.5-1+deb10u1)) of PostreSQL
-----  Uptime  -----
[INFO]    Service uptime:  01h 41m 13s
[WARN]    Uptime less than 1 day.  My report may be inaccurate
-----  Databases  -----
[INFO]    Database count (except templates): 3
[INFO]    Database list (except templates): postgres wikistats adrenalib
-----  Extensions  -----
[INFO]    Number of activated extensions: 1
[INFO]    Activated extensions: plpgsql
[WARN]    Extension pg_stat_statements is disabled in database template1
-----  Users  -----
[OK]      No user account will expire in less than 7 days
[OK]      No user with password=username
[OK]      Password encryption enabled
-----  Connection information  -----
[INFO]    max_connections: 20
[INFO]    Current used connections: 8 (40.00%)
[INFO]    2 connections are reserved for super user (10.00%)
[INFO]    Average connection age:  01h 08m 18s
-----  Memory usage  -----
[INFO]    Configured work_mem: 128.00 MB
[INFO]    Using an average ratio of work_mem buffers by connection of 150% (use --wmp to change it)
[INFO]    Total work_mem (per connection): 192.00 MB
[INFO]    shared_buffers: 40.00 GB
[INFO]    Track activity reserved size: 0.00 B
[INFO]    maintenance_work_mem=2.00 GB
[INFO]    Max memory usage:
		  shared_buffers (40.00 GB)
		+ max_connections * work_mem * average_work_mem_buffers_per_connection (20 * 128.00 MB * 150 / 100 = 3.75 GB)
		+ autovacuum_max_workers * maintenance_work_mem (2 * 2.00 GB = 4.00 GB)
		+ track activity size (0.00 B)
		= 47.75 GB
[INFO]    effective_cache_size: 85.00 GB
[INFO]    Cumulated size of all databases: 2.17 TB
[INFO]    PostgreSQL maximum amount of memory used: 50.60% of system RAM
[WARN]    PostgreSQL will not use more than 60% of the amount of RAM.  On a dedicated host you may increase PostgreSQL shared_buffers, as it may improve performances.
[INFO]    max memory+effective_cache_size (less shared_buffers) is 98.29% of the amount of RAM
[WARN]    The sum of max_memory and effective_cache_size is too high, the planner may create bad plans because the system buffercache will probably be smaller than expected, especially if the machine is NOT dedicated to PostgreSQL
-----  Huge Pages  -----
[OK]      huge_pages enabled in PostgreSQL
[INFO]    Hugepagesize is 2048 kB
[INFO]    HugePages_Total 21000 pages
[INFO]    HugePages_Free 18004 pages
[INFO]    Suggested number of Huge Pages: 21001 (Consumption peak: 43009080 / Huge Page size: 2048)
-----  Logs  -----
[OK]      log_hostname is off: no reverse DNS lookup latency
[WARN]    Log of long queries deactivated.  It will be more difficult to optimize query performance
[OK]      log_statement=none
-----  Two-phase commit  -----
[OK]      Currently no two-phase commit transactions
-----  Autovacuum  -----
[OK]      autovacuum is activated.
[INFO]    autovacuum_max_workers: 2
-----  Checkpoint  -----
[OK]      checkpoint_completion_target(0.9) OK
-----  Disk access  -----
[BAD]     fsync is off.  You may lose data after a crash, DANGER!
[OK]      synchronize_seqscans is on
-----  WAL  -----
-----  Planner  -----
[OK]      I/O cost settings are set at their default values
[BAD]     Some plan features are disabled: enable_partitionwise_aggregate,enable_partitionwise_join
=====  Database information for database template1  =====
-----  Database size  -----
[INFO]    Database template1 total size: 8.02 MB
[INFO]    Database template1 indexes size: 4.91 MB (61.21%)
[INFO]    Database template1 indexes size: 3.11 MB (38.79%)
-----  Tablespace location  -----
[OK]      No tablespace in PGDATA
-----  Shared buffer hit rate  -----
[INFO]    shared_buffer_heap_hit_rate: 99.98%
[INFO]    shared_buffer_toast_hit_rate: 97.31%
[INFO]    shared_buffer_tidx_hit_rate: 98.97%
[INFO]    shared_buffer_idx_hit_rate: 99.95%
[OK]      This is very good (if this PostgreSQL instance was recently used as it usually is, and was not stopped since)
-----  Indexes  -----
[OK]      No invalid index
[OK]      No unused indexes
-----  Procedures  -----
[OK]      No procedures with default costs

=====  Configuration advice  =====
-----  checkpoint  -----
[URGENT] set fsync to on!
-----  extension  -----
[LOW] Enable pg_stat_statements in database template1 to collect statistics on all queries (not only those longer than log_min_duration_statement)
-----  hugepages  -----
[LOW] Change Huge Pages size from 2MB to 1GB
[MEDIUM] set vm.nr_hugepages=21001 in /etc/sysctl.conf and run sysctl -p to reload it.  This will allocate Huge Pages (it may require a system reboot).
~~~

## To use it

### Install it

It needs Perl with various modules, mainly `DBD::Pg`

- On Debian or a derivative:
```
apt-get install libdbd-pg-perl libdbi-perl perl-modules
```
- On Fedora or a derivative:
```
yum install perl-DBD-Pg perl-DBI perl-Term-ANSIColor
```

- On MacOS with Homebrew:
```
brew install perl
cpan DBD-pg
```

Download the script.  Invoke one of:
```
wget -O postgresqltuner.pl postgresqltuner.pl
wget -O postgresqltuner.pl https://postgresqltuner.pl
curl -Lo postgresqltuner.pl postgresqltuner.pl
curl -Lo postgresqltuner.pl https://postgresqltuner.pl
```

Set permissions:
```
chmod +x postgresqltuner.pl
```

Then invoke on the command line, as the "postgres" user, either:
- By connecting to the PostgreSQL server via TCP:
```
postgresqltuner.pl --host=dbhost --database=testdb --user=username --password=qwerty
```
- ... or via an Unix socket:
```
postgres$ postgresqltuner.pl --host=/var/run/postgresql  # PostgreSQL socket directory
```

If available, postgresqltuner.pl will use standard PostgreSQL variables like `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSERNAME`, and password from the `~/.pgpass` file.


### With Docker

Invoke on the command-line either:
 - via the plain network:
```
docker run -it --rm jfcoz/postgresqltuner --host=dbhost --user=username --password=pass --database=testdb
```
 - ... or via ssh:
```
docker run -it --rm -v $HOME/.ssh:/root/.ssh jfcoz/postgresqltuner --host=dbhost --user=username --password=pass --database=testdb
```
 - ... or via a docker link:
```
docker run -it --rm --link your-postgresql-container:dbhost jfcoz/postgresqltuner --host=dbhost --user=username --password=pass --database=testdb
```

### SSH

When using postgresqltuner.pl to inspect a remote PostgreSQL instance, it will use ssh to collect OS informations. You should configure ssh to connect to the remote host with private key authentication.

You can provide adequate options to ssh:

- ... as commend-line options:
```
--sshopt=Port=2200 --sshopt=IdentityFile=...
```

- or in the configuration file "~/.ssh/config":
```
Host my-database-host
	IdentityFile=...
	Port=2200
```

### PostgreSQL passwords

For better security use a `~/.pgpass` file containing passwords, so no password will be saved in your shell history nor visible in a process complete name. [.pgpass documentation](https://www.postgresql.org/docs/current/static/libpq-pgpass.html)
```
host:port:database:username:password
```

## Options

- Average number of work_mem buffer per connection:

A complex query can use many work_mem buffers. You can configure the average number of work_mem buffers per connection (in percent):
```
--wmp 300
```
The default in 150%

- SSD storage:

If the PostgreSQL instance runs in an hypervisor or with SSD storage, I cannot detect it accurately.
```
--ssd
```
Allow to specify that storage is on SSD

--nocolor
The report will not be colorized.  Useful to save it in a file by using shell redirection.

## Special FreeBSD settings

FreeBSD has support for virtual memory over-commit, using vm.overcommit configuration setting.
This setting is configured via /etc/sysctl.conf.

Change 'vm.overcommit: 0 ' to 'vm.overcommit: 1'.

Also, install [freecolor](https://kukunotes.wordpress.com/2014/11/17/freebsd-view-memory-usage/).

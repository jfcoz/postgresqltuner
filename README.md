# postgresqltuner.pl

[![Build Status](https://travis-ci.org/jfcoz/postgresqltuner.svg?branch=master)](https://travis-ci.org/jfcoz/postgresqltuner)
[![Donate](https://liberapay.com/assets/widgets/donate.svg)](https://liberapay.com/CoCoZ/donate)

`postgresqltuner.pl` is a simple script to analyse your PostgreSQL database. It is inspired by [mysqltuner.pl](https://github.com/major/MySQLTuner-perl)

## Demo

Here is a sample output :

~~~
postgresqltuner.pl version 0.0.8
Connecting to /var/run/postgresql:5432 database testdb with user postgres...
[OK]      User used for report have super rights
=====  OS information  =====
[INFO]    OS: Debian GNU/Linux 8 \n \l
[INFO]    OS total memory: 15.52 GB
[OK]      vm.overcommit_memory is good : no memory overcommitment
[INFO]    Running on physical machine
[INFO]    Currently used I/O scheduler(s) : cfq
=====  General instance informations  =====
-----  Version  -----
[WARN]    You are using version 9.4.8 which is not the latest version
-----  Uptime  -----
[INFO]    Service uptime : 101d 21h 53m 03s
-----  Databases  -----
[INFO]    Database count (except templates): 2
[INFO]    Database list (except templates): postgres testdb
-----  Extensions  -----
[INFO]    Number of activated extensions : 1
[INFO]    Activated extensions : plpgsql
[WARN]    Extensions pg_stat_statements is disabled
-----  Users  -----
[OK]      No user account will expire in less than 7 days
[OK]      No user with password=username
[OK]      Password encryption is enabled
-----  Connection information  -----
[INFO]    max_connections: 100
[INFO]    current used connections: 6 (6.00%)
[INFO]    3 are reserved for super user (3.00%)
[INFO]    Average connection age : 1d 11h 31m 18s
-----  Memory usage  -----
[INFO]    configured work_mem: 4.00 MB
[INFO]    Using an average ratio of work_mem buffers by connection of 150% (use --wmp to change it)
[INFO]    total work_mem (per connection): 6.00 MB
[INFO]    shared_buffers: 128.00 MB
[INFO]    Track activity reserved size : 111.00 KB
[WARN]    maintenance_work_mem is less or equal default value. Increase it to reduce maintenance tasks time
[INFO]    Max memory usage :
                  shared_buffers (128.00 MB)
                + max_connections * work_mem * average_work_mem_buffers_per_connection (100 * 4.00 MB * 150 / 100 = 600.00 MB)
                + autovacuum_max_workers * maintenance_work_mem (3 * 64.00 MB = 192.00 MB)
                + track activity size (111.00 KB)
                = 920.11 MB
[INFO]    effective_cache_size: 4.00 GB
[INFO]    Size of all databases : 41.87 GB
[INFO]    PostgreSQL maximum memory usage: 5.79% of system RAM
[WARN]    Max possible memory usage for PostgreSQL is less than 60% of system total RAM. On a dedicated host you can increase PostgreSQL buffers to optimize performances.
[INFO]    max memory+effective_cache_size is 31.57% of total RAM
[WARN]    Increase shared_buffers and/or effective_cache_size to use more memory
-----  Logs  -----
[OK]      log_hostname is off : no reverse DNS lookup latency
[WARN]    log of long queries is desactivated. It will be more difficult to optimize query performances
[OK]      log_statement=none
-----  Two phase commit  -----
[OK]      Currently no two phase commit transactions
-----  Autovacuum  -----
[OK]      autovacuum is activated.
[INFO]    autovacuum_max_workers: 3
-----  Checkpoint  -----
[WARN]    checkpoint_completion_target(0.5) is low
-----  Disk access  -----
[OK]      fsync is on
[OK]      synchronize_seqscans is on
-----  WAL  -----
[BAD]     The wal_level minimal does not allow PITR backup and recovery
-----  Planner  -----
[OK]      costs settings are defaults
[OK]      all plan features are enabled
=====  Database information for database testdb  =====
-----  Database size  -----
[INFO]    Database testdb total size : 41.86 GB
[INFO]    Database testdb tables size : 13.07 GB (31.22%)
[INFO]    Database testdb indexes size : 28.79 GB (68.78%)
-----  Shared buffer hit rate  -----
[INFO]    shared_buffer_heap_hit_rate: 94.11%
[INFO]    shared_buffer_toast_hit_rate: 23.73%
[INFO]    shared_buffer_tidx_hit_rate: 97.41%
[INFO]    shared_buffer_idx_hit_rate: 96.33%
[WARN]    Shared buffer idx hit rate is quite good. Increase shared_buffer memory to increase hit rate
-----  Indexes  -----
[OK]      No invalid indexes
[WARN]    Some indexes are unused since last statistics: hosts_owner_idx
-----  Procedures  -----
[OK]      No procedures with default costs

=====  Configuration advices  =====
-----  backup  -----
Configure your wal_level to a level which allow PITR backup and recovery
-----  checkpoint  -----
Your checkpoint completion target is too low. Put something nearest from 0.8/0.9 to balance your writes better during the checkpoint interval
-----  extension  -----
Enable pg_stat_statements to collect statistics on all queries (not only queries longer than log_min_duration_statement in logs)
-----  index  -----
You have unused indexes in the database since last statistics. Please remove them if they are never use
~~~

## Use it

### Install it

need perl with module `DBD::Pg`

- On Debian or derivated :
```
apt-get install libdbd-pg-perl
```
- On Fedora or deriavated :
```
yum install perl-DBD-Pg
```

Download :

```
wget -O postgresqltuner.pl postgresqltuner.pl
wget -O postgresqltuner.pl https://postgresqltuner.pl
curl -o postgresqltuner.pl postgresqltuner.pl
curl -o postgresqltuner.pl https://postgresqltuner.pl
```

Add permissions :
```
chmod +x postgresqltuner.pl
```

And run script :
- Via network :
```
postgresqltuner.pl --host=dbhost --database=testdb --user=username --password=qwerty
```
- Via unix socket as postgres sytem user :
```
postgres$ postgresqltuner.pl --host=/var/run/postgresql  # PostgreSQL socket directory
```

### With docker

 - Via network :
```
docker run -it --rm jfcoz/postgresqltuner --host=dbhost --user=username --password=pass --database=testdb
```
 - Via network with ssh access :
```
docker run -it --rm -v $HOME/.ssh:/root/.ssh jfcoz/postgresqltuner --host=dbhost --user=username --password=pass --database=testdb
```
 - Via docker link :
```
docker run -it --rm --link your-postgresql-container:dbhost jfcoz/postgresqltuner --host=dbhost --user=username --password=pass --database=testdb
```

### SSH

When using it remotly, postgresqltuner.pl will use ssh to collect OS informations. You must configure ssh to connect to remote host with private key authentication.

## Options

- Average number of work_mem buffer per connection :

A query can use many work_mem buffers depending on the query complexity. You can configure the average number of work_mem buffers per connection (in percent):
```
--wmp 300
```
The default in 150%

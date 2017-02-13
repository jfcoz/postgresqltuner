# postgresqltuner.pl

[![Build Status](https://travis-ci.org/jfcoz/postgresqltuner.svg?branch=master)](https://travis-ci.org/jfcoz/postgresqltuner)

`postgresqltuner.pl` is a simple script to analyse your PostgreSQL database. It is inspired by [mysqltuner.pl](https://github.com/major/MySQLTuner-perl)

## Demo

Here is a sample output :

```
$ postgresqltuner.pl --host=dbhost --database=testdb --user=username --password=qwerty
postgresqltuner.pl version 0.0.3
Connecting to dbhost:5432 database testdb with user username...
=====  OS information  =====
[INFO]    OS: Debian GNU/Linux 8 \n \l
[INFO]    OS total memory: 15.52 G
[INFO]    Running on physical machine
[INFO]    Currently used I/O scheduler(s) : cfq
=====  General instance informations  =====
-----  Version  -----
[WARN]    You are using version 9.4.8 which is not the latest version
-----  Uptime  -----
[INFO]    Service uptime : 108d 01h 13m 13s
-----  Databases  -----
[INFO]    Database count (except templates): 2
[INFO]    Database list (except templates): postgres testdb
-----  Extensions  -----
[INFO]    Number of activated extensions : 1
[INFO]    Activated extensions : plpgsql
-----  Users  -----
[OK]      No user account will expire in less than 7 days
[OK]      No user with password=username
[OK]      Password encryption is enabled
-----  Connection information  -----
[INFO]    max_connections: 100
[INFO]    current used connections: 7 (7.00%)
[INFO]    3 are reserved for super user (3.00%)
[INFO]    Average connection age : 5d 01h 15m 45s
-----  Memory usage  -----
[INFO]    work_mem (per connection): 4.00 M
[INFO]    shared_buffers: 128.00 M
[INFO]    Max memory usage (shared_buffers + max_connections*work_mem): 528.00 M
[INFO]    effective_cache_size: 4.00 GB
[INFO]    Size of all databases : 37.77 GB
[INFO]    PostgreSQL maximum memory usage: 3.32 of system RAM
[WARN]    Max possible memory usage for PostgreSQL is less than 60% of system total RAM. On a dedicated host you can increase PostgreSQL buffers to optimize performances.
[INFO]    max memory+effective_cache_size is 29.10% of total RAM
[WARN]    Increase shared_buffers and/or effective_cache_size to use more memory
[WARN]    maintenance_work_mem is less or equal default value. Increase it to reduce maintenance tasks time
-----  Logs  -----
[OK]      log_hostname is off : no reverse DNS lookup latency
[WARN]    log of long queries is desactivated. It will be more difficult to optimize query performances
[OK]      log_statement=none
-----  Two phase commit  -----
[OK]      Currently no two phase commit transactions
-----  Autovacuum  -----
[OK]      autovacuum is activated.
-----  Checkpoint  -----
[WARN]    checkpoint_completion_target(0.5) is low
-----  Disk access  -----
[OK]      fsync is on
-----  WAL  -----
[BAD]     The wal_level minimal does not allow PITR backup and recovery
=====  Database information for database testdb  =====
-----  Database size  -----
[INFO]    Database testdb total size : 34.47 G
[INFO]    Database testdb tables size : 9.75 G (28.28%)
[INFO]    Database testdb indexes size : 24.72 G (71.72%)
-----  Shared buffer hit rate  -----
[INFO]    shared_buffer_heap_hit_rate: 93.74
[INFO]    shared_buffer_toast_hit_rate: 29.60
[INFO]    shared_buffer_tidx_hit_rate: 98.08
[INFO]    shared_buffer_idx_hit_rate: 96.71
[WARN]    Shared buffer idx hit rate is quite good. Increase shared_buffer memory to increase hit rate
-----  Indexes  -----
[OK]      No invalid indexes
```

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

## SSH

When using it remotly, postgresqltuner.pl will use ssh to collect OS informations. You must configure ssh to connect to remote host with private key authentication.


# postgresqltuner.pl

[![Build Status](https://travis-ci.org/jfcoz/postgresqltuner.svg?branch=master)](https://travis-ci.org/jfcoz/postgresqltuner)

`postgresqltuner.pl` is a simple script to analyse your PostgreSQL database. It is inspired by [mysqltuner.pl](https://github.com/major/MySQLTuner-perl)

## Demo

Here is a sample output :

```
$ postgresqltuner.pl --host=dbhost --database=testdb --user=username --password=qwerty
postgresqltuner.pl version 0.0.2
Connecting to dbhost:5432 database testdb with user username...
[WARN]    You are using version 9.4.8 which is not the latest version
[INFO]    Service uptime : 106 days 10:44:08.001241
[INFO]    Database total size : 34.33 G
[INFO]    Database tables size : 9.75 G (28.40%)
[INFO]    Database indexes size : 24.58 G (71.60%)
[INFO]    max_connections: 100
[INFO]    current used connections: 7 (7.00%)
[INFO]    Average connection age : 4d 13h 06m 25s
[INFO]    work_mem (per connection): 4.00 M
[INFO]    shared_buffers: 128.00 M
[INFO]    Max memory usage (shared_buffers + max_connections*work_mem): 528.00 M
[INFO]    shared_buffer_heap_hit_rate: 93.7644996086213728
[INFO]    shared_buffer_toast_hit_rate: 29.8449959991758043
[INFO]    shared_buffer_tidx_hit_rate: 98.0854342955825639
[INFO]    shared_buffer_idx_hit_rate: 96.6900803829844404
[WARN]    Shared buffer idx hit rate is quite good. Increase shared_buffer memory to increase hit rate
[OK]      autovacuum is activated.
[OK]      checkpoint_completion_target(0.5) OK
[OK]      fsync is on
[BAD]     The wal_level minimal does not allow PITR backup and recovery
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

Dowload and run script :
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


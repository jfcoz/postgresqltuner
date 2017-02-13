# postgresqltuner.pl

[![Build Status](https://travis-ci.org/jfcoz/postgresqltuner.svg?branch=master)](https://travis-ci.org/jfcoz/postgresqltuner)

`postgresqltuner.pl` is a simple script to analyse your PostgreSQL database. It is inspired by [mysqltuner.pl](https://github.com/major/MySQLTuner-perl)

## Demo

Here is a sample output :
![postgresqltuner.pl](https://github.com/jfcoz/postgresqltuner/blob/master/documentation/postgresqltuner.png)

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


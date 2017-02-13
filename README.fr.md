# postgresqltuner.pl

[![Build Status](https://travis-ci.org/jfcoz/postgresqltuner.svg?branch=master)](https://travis-ci.org/jfcoz/postgresqltuner)

`postgresqltuner.pl` est un script Perl pour vous aider à analyser la configuration de votre serveur PostgreSQL. Il est inspiré par [mysqltuner.pl](https://github.com/major/MySQLTuner-perl)

## Démonstration

Voici un exemple de son exécution :
![postgresqltuner.pl](https://github.com/jfcoz/postgresqltuner/blob/master/documentation/postgresqltuner.png)

## Utilisation

### Installation

Pré-requis : module Perl `DBD::Pg`

- Sur Debian et dérivées :
```
apt-get install libdbd-pg-perl
```
- Sur Fedora et dérivées :
```
yum install perl-DBD-Pg
```

Téléchargement :

```
wget -O postgresqltuner.pl postgresqltuner.pl
wget -O postgresqltuner.pl https://postgresqltuner.pl
curl -o postgresqltuner.pl postgresqltuner.pl
curl -o postgresqltuner.pl https://postgresqltuner.pl
```

Lancement :
- Connexion par le réseau :
```
postgresqltuner.pl --host=dbhost --database=testdb --user=username --password=qwerty
```
- Connexion via le socket unix en tant qu'utilisateur système postgres :
```
postgres$ postgresqltuner.pl --host=/var/run/postgresql  # PostgreSQL socket directory
```

### Avec Docker

 - Connexion par le réseau :
```
docker run -it --rm jfcoz/postgresqltuner --host=dbhost --user=username --password=pass --database=testdb
```
 - Connexion par le réseau avec accès SSH :
```
docker run -it --rm -v $HOME/.ssh:/root/.ssh jfcoz/postgresqltuner --host=dbhost --user=username --password=pass --database=testdb
```
 - Connexion via un lien Docker :
```
docker run -it --rm --link your-postgresql-container:dbhost jfcoz/postgresqltuner --host=dbhost --user=username --password=pass --database=testdb
```

## SSH

En cas d'utilisation à distance, postgresqltuner.pl utilise SSH pour se connecter au serveur et collecter quelques informations sur l'OS. Il faut pour ça configurer SSH pour que postgresqltuner.pl puisse se connecter au serveur avec une authentification par clef.


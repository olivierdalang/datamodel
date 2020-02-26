[![Build Status](https://travis-ci.org/QGEP/datamodel.svg?branch=master)](https://travis-ci.org/QGEP/datamodel)

The QGEP Datamodel
==================

This repository contains a bare QGEP datamodel. This is an SQL implementation
of the VSA-DSS datamodel (including SIA405 Waste water). It ships with SQL scripts required
to setup an empty PostgreSQL/PostGIS database to use as basis for the QGEP
project.

The latest release can be downloaded here: https://github.com/QGEP/datamodel/releases/

Ordinary data tables (qgep\_od.)
---------------------------

These tables contain the business data. In these tables the information which
is maintained by organizations can be found.

Value Lists (qgep\_vl.)
------------------

These tables contain value lists which are referenced by qgep_od. tables. The value
lists contain additional information in different languages about the values.

Information Schema (qgep\_sys.is\_)
-------------------------

These tables contain meta information about the schema.

Views (vw\_)
------------

The VSA-DSS model is built in an object relational way. Its PostgreSQL
implementation does not make use of object inheritance and instead uses a pure
relational approach. For base classes (like od\_wastewater\_structure) there
are multiple child classes (like qgep\_od.manhole or gep\_od.special\_structure) which
are linked with the same `obj_id` to the parent object.

For easier usage views are provided which give access to the merged attributes
of child and parent classes. These views are prefixed with `vw_` and all come
with INSERT, UPDATE and DELETE rules which allow changing data directly on the
view.

E.g. The view `vw_manhole` merges all the attributes of the tables `od_manhole`
and `od_wastewater_structure`.

QGEP Views (vw\_qgep\_\*)
-------------------------

These Views are handcrafted specifically for QGEP data entry. They normally
join data from various tables. They also come with INSERT, UPDATE and DELETE
rules but some attributes may be read-only (aggregated from multiple tables,
calculated otherwise).

Functions
---------

The functions are mainly used to create cached data required for symbology.
They are often triggered for changes on specific tables and then executed only
to update information on specific roles.

Installation instructions
=========================

Detailed instructions can be found in the [QGEP documentation](http://qgep.github.io/docs/).
This is only a short summary for reference.

Preparation:
------------

 * Create new database (e.g. `qgeptest`)
 * Create a service in a pg\_service definition (e.g. `pg_qgep`)

Installation:
-------------

 * `export PG_SERVICE=pg_qgep`
 * Run `scripts/db_setup.sh`

Using Docker (for dev):
----------------

This sets up four different databases :

- *release* : installs the demo data from the release 1.4
- *release_struct* : installs structure (empty model) from the release 1.4
- *build* : installs the structure using installation scripts
- *build_pum* : installs the demo data through successive pum migrations

```bash
# prepare
docker-compose build

# (re)set postgis
docker-compose up --build --renew-anon-volumes -d postgis

# create the datamodel
docker-compose run datamodel [release | release_struct | build | build_pum | other_arbitrary_command ]
```

Example usage:
```bash
# get the release structure
docker-compose run datamodel release_struct

# build the model from scratch
docker-compose run datamodel build

# migrate the release structure using pum upgrade
docker-compose run datamodel pum upgrade -t qgep_sys.pum_info -p qgep_release_struct -d delta -v int SRID 2056

# check the results is the same than the build using pum check
docker-compose run datamodel pum check -p1 qgep_build -p2 qgep_release_struct -o check-results
```

Running tests:
```bash
# build the model from scratch
docker-compose run datamodel build

# run the tests
docker-compose run -e PGSERVICE=qgep_build datamodel nosetests --exe -e test_import.py -e test_geometry.py
```
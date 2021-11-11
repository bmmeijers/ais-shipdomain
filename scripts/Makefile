database = database
host = dbhost
all:
	python3 ais_reader.py | psql -a -d $(database) -h $(host)
	psql -a -d $(database) -h $(host) -f vessel_cargo_type.sql
	psql -a -d $(database) -h $(host) -f vessel_dimensions.sql
	psql -a -d $(database) -h $(host) -f one_month.sql

database = database
host = dbhost
all:
	python3 ais_reader.py | psql -a -d $(database) -h $(host)
	psql -a -d $(database) -h $(host) -f vessel_cargo_type.sql
	psql -a -d $(database) -h $(host) -f vessel_dimensions.sql
	psql -a -d $(database) -h $(host) -f one_month.sql
	rm -rf ./work/
	mkdir ./work/
	python3 prepare_workflow.py
	chmod 755 *.sh
	./rasterize.sh
	./contouring.sh
	./shipdomains.sh
	ogr2ogr -f "ESRI Shapefile" ./work/shipdomain_contours.shp ./work/shipdomain_contours.csv

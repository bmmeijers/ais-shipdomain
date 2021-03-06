import argparse

# FIXME:
# - connection parameters via sys.argv
# - suffix of tablename is hardcoded

# connection parameters
DBNAME = 'database'
DBHOST = 'dbhost'
WORKING_FOLDER = './work/' # include backslash!

def parse_aspects():
# all? -- no where clause!
# only container shiptypes
# excluding small ships from the co-occurences (e.g. tug boats)?

    # FIXME: Later we can make combinations - loa__large && approach_angle__crossing
#    aspects_txt = """
#       aspect            | name           | where clause
#       all               | all            |
#       shiptype          | only_cargo     | own_ship__shiptype between 70 and 79
#       shiptype          | towing         | own_ship__shiptype in (31, 32)
#       shiptype          | tug            | own_ship__shiptype in (52)
#       time_of_day       | day            | extract(hour from "own_ship__ts") < 19 and extract(hour from "own_ship__ts") >= 7
#       time_of_day       | night          | extract(hour from "own_ship__ts") >= 19 or extract(hour from "own_ship__ts") < 7
#       loa               | small          | own_ship__dims_length <= 157.0
#       loa               | large          | own_ship__dims_length > 157.0
#       approach_angle    | crossing       | encounter__encounter_type = 3
#       approach_angle    | head_on        | encounter__encounter_type = 1
#       approach_angle    | takeover       | encounter__encounter_type = 2
#       relative_velocity | low            | encounter__relative_velocity <= 14.4
#       relative_velocity | high           | encounter__relative_velocity > 14.4
#       own_velocity      | low            | own_ship__speed < 56
#       own_velocity      | medium         | own_ship__speed >= 56 and own_ship__speed < 102
#       own_velocity      | high           | own_ship__speed >= 102
#    """
    aspects_txt = """
       aspect            | name           | where clause
       all               | all            |
    """
    # skip first line, and iter over lines, making a tuple for each line
    return [tuple(map(lambda x: x.strip(), line.split('|')))
            for line in aspects_txt.strip().split('\n')[1:]]


def rasterize(aspect, name, where):
    view_name = f"ais_shipdomain_{aspect}__{name}"
    if where:
        where_clause = f"where {where}"
    else:
        where_clause = ""
    # TABLESAMPLE BERNOULLI (0.5)

    # gdal_rasterize compress options, see
    # https://gis.stackexchange.com/questions/1104/should-gdal-be-set-to-produce-geotiff-files-with-compression-which-algorithm-sh
    #    LZW - highest compression ratio, highest processing power
    #    DEFLATE
    #    PACKBITS - lowest compression ratio, lowest processing power

    tpl = f"""
psql -d {DBNAME} -h {DBHOST} -c 'drop   view {view_name};'
psql -d {DBNAME} -h {DBHOST} -c "create view {view_name} as select st_geometryn(encounter__extents__own_ship_origin, 2) as geom from ais_ship_encounters_201508 {where_clause};"
gdal_rasterize -l "{view_name}" -burn 1.0 -ts 8000.0 8000.0 -init 0.0 -a_nodata -1.0 -te -4000.0 -4000.0 4000.0 4000.0 -ot UInt32 -of GTiff -co COMPRESS=LZW -co BIGTIFF=IF_NEEDED -add "PG:dbname='{DBNAME}' host={DBHOST} port=5432" {WORKING_FOLDER}{view_name}.tif
"""
    return tpl

def contouring(aspect, name):
    view_name = f"ais_shipdomain_{aspect}__{name}"
    tpl = f"""
# -- convert the raster into a format saga understands
saga_cmd io_gdal 0 -TRANSFORM 1 -RESAMPLING 3 -GRIDS "{WORKING_FOLDER}{view_name}.sgrd" -FILES "{WORKING_FOLDER}{view_name}.tif"
# -- do the profile generation
saga_cmd ta_profiles "Profiles from Lines" -DEM "{WORKING_FOLDER}{view_name}.sgrd" -LINES "{WORKING_FOLDER}rays.shp" -NAME "idx" -PROFILE "{WORKING_FOLDER}{view_name}.shp"
# -- convert the profile towards a csv
ogr2ogr -f "CSV" {WORKING_FOLDER}{view_name}.csv {WORKING_FOLDER}{view_name}.shp
"""
    return tpl


def shipdomains(aspect, name, dist, append=False):
    description = f"{aspect}__{name}"
    view_name = f"ais_shipdomain_{aspect}__{name}"
    if append:
        mode = "--append"
    else:
        mode = ""
    tpl = f"""
python3 shipdomain.py {mode} --dist {dist} {description} {WORKING_FOLDER}{view_name}.csv {WORKING_FOLDER}shipdomain_contours.csv
"""
    return tpl

def main():
    parser = argparse.ArgumentParser(
        description='Writes shell scripts to run the analysis workflow')
    # positional
    #    parser.add_argument('file_in',
    #                        metavar='file_in',
    #                        type=str,
    #                        help='filename to process, e.g. {WORKING_FOLDER}daynight__night.csv')
    # optional
    #    parser.add_argument('--dist',
    #                        type=int,
    #                        default=2500,
    #                        help='maximum distance to consider while processing the profiles')
    # parse
    args = parser.parse_args()
    aspects = parse_aspects()
    with open('./rasterize.sh', 'w') as fh:
        fh.write('# generated by script, do not edit by hand, re-run script')

        for aspect in aspects:
            fh.write(rasterize(aspect[0], aspect[1], aspect[2]))

    with open('./contouring.sh', 'w') as fh:
        fh.write('# generated by script, do not edit by hand, re-run script')

        fh.write(f"""# create rays in well known text and convert to shapefile with ogr2ogr
python3 rays.py {WORKING_FOLDER}
ogr2ogr -f "ESRI Shapefile" {WORKING_FOLDER}rays.shp {WORKING_FOLDER}rays.csv
""")
        for aspect in aspects:
            fh.write(contouring(aspect[0], aspect[1]))

    with open('./shipdomains.sh', 'w') as fh:
        fh.write('# generated by script, do not edit by hand, re-run script')

        i = 0
        for max_dist in (500, 1000, 1500, 2000, 2500):
            for aspect in aspects:
                mode = i > 0
                fh.write(shipdomains(aspect[0], aspect[1], max_dist, mode))
                i += 1

    print('generated .sh scripts')
    print('(these scripts should be run in the following order: 1. rasterize.sh, 2. contouring.sh, 3. shipdomains.sh)')

if __name__ == "__main__":
    main()

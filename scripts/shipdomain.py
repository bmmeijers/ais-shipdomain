import argparse
import csv
from itertools import groupby
import os

def load_profiles(file_nm):
    profiles = []
    # the file obtained via
    with open(file_nm) as fh: 
        reader = csv.reader(fh)
        next(reader)
        # each row contains:
        # LINE_ID,ID,DIST,DIST_SURF,X,Y,Z
        # (line_id, id, dist, dist_surf, x, y, z)
        for k, g in groupby((tuple(map(float, row)) for row in reader), lambda x: x[0]):
            profiles.append( (k, list(g)) )
    return profiles


def process_profiles(profiles, MAX_DIST=5000):
    # process the profiles into a set of silhouettes 
    # (percentage of ships occuring around)
    percs = [0.05, 0.10, 0.25, 0.5, 0.75, 1.0]
    silhouettes = {}
    for p in percs:
        silhouettes[p] = []
    for key, profile in profiles:
    #    print(key)
    #    print(len(profile))
        accum_z = 0
        for idx, (line_id, id, dist, dist_surf, x, y, z) in enumerate(profile):
            accum_z += z
            if dist > MAX_DIST:
                break
        for perc in percs:
            p = accum_z * perc

            running_z = 0
            for idx, (line_id, id, dist, dist_surf, x, y, z) in enumerate(profile):
                running_z += z
                if running_z >= p:
                    silhouettes[perc].append((x,y))
                    break
    return silhouettes

def output_contours_header(file_name):
    # output contours to WKT csv
    with open(file_name, 'w') as fh:
        fh.write("percentage,wkt,description,max_dist")
        fh.write("\n")

def output_contours(contours, description, max_dist, file_name): # FIXME: distance, contour category and type?
    # output contours to WKT csv
    with open(file_name, 'a') as fh:
        for percentage, contour in contours.items():
            ords = [(c[0], c[1]) for c in contour]
            # make closed loop
            if ords[0] != ords[-1]:
                ords.append(ords[0])
            ordinates = ",".join("{} {}".format(c[0], c[1]) for c in ords)
            fh.write('{},"POLYGON(({}))",{},{}'.format(percentage, ordinates, description, max_dist))
            fh.write("\n")


def main():

    parser = argparse.ArgumentParser(description='Process rays into contours for the shipdomain')
    # positional
    parser.add_argument('desc',
                        metavar='desc',
                        type=str,
                        help='description for the shipdomain')
    parser.add_argument('file_in',
                        metavar='file_in',
                        type=str,
                        help='filename to process, e.g. /tmp/daynight__night.csv')
    parser.add_argument('file_out',
                        metavar='file_out',
                        type=str,
                        help='filename of output to store, e.g. /tmp/shipdomain.csv')
    # optional
    parser.add_argument('--append', action='store_true', default=False,
                    dest='append_mode',
                    help='Set a switch to true')
    
    parser.add_argument('--dist',
                        type=int,
                        default=2500,
                        help='maximum distance to consider while processing the profiles')

    # parse
    args = parser.parse_args()

    if not args.append_mode:
        output_contours_header(args.file_out)
    else:
        if not os.path.exists(args.file_out):
            raise ValueError('append mode requested, but no file to append to found')

    # do program
    profiles = load_profiles(args.file_in)
    # we can go upto 2500 meters 
    # (as we used this as maximum dist in generating the co-occurences)
    contours = process_profiles(profiles, args.dist)
    output_contours(contours, args.desc, args.dist, args.file_out)


if __name__ == "__main__":
    main()



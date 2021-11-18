import sys
import os.path
from math import pi, cos, sin

# make 360 rays covering square of 4x4km

PI2 = 2 * pi
r = (4000**2 + 4000**2)**0.5
with open('./work/rays.csv', 'w') as fh:
    fh.write('idx;wkt')
    fh.write('\n')
    for i in range(1, 361):
        x, y = r * cos(i / 360. * PI2), r * sin(i / 360. * PI2)
        fh.write(f'{i};"LINESTRING(0 0, {x} {y})"')
        fh.write('\n')

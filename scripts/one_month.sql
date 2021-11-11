\timing on

-- how large square to consider for finding near objects
-- square will be 2 * DIST
\set DIST 2500 

-- how many meters for the 'vector' geometry (linestring) of COG
\set RADIUS 15 

-- table name suffix
\set SUFFIX _201508

-- the time period to use for analysis
\set START_EPOCH '2015-08-01 00:00:00+03'
\set END_EPOCH   '2015-08-31 23:59:59+03'

-- 5636 / 3035 / 5270
\set SRID 5270

drop table if exists ais_logs_dynamic:SUFFIX;
create table ais_logs_dynamic:SUFFIX as
select
    mmsi,
    ts,
    type,
    repeat,
    status,
    turn,
    speed,
    accuracy,
    longitude,
    latitude,
    course,
    heading,
    second,
    maneuvre,
    raim,
    radio,
    wkb_geom
from
    ais_logs_dynamic
where
    ts >= :'START_EPOCH' and ts < :'END_EPOCH'
order by
    mmsi, ts;

drop table if exists ais_logs_dynamic_unique:SUFFIX;

-- INCLUDING DEFAULTS INCLUDING CONSTRAINTS INCLUDING INDEXES 
CREATE TABLE ais_logs_dynamic_unique:SUFFIX ( LIKE ais_logs_dynamic:SUFFIX );
ALTER TABLE ais_logs_dynamic_unique:SUFFIX ADD UNIQUE(mmsi, ts); -- TABLESPACE indx;

-- order by mmsi, timestamp and then on repeat indicator (to have duplicates removed)
INSERT INTO ais_logs_dynamic_unique:SUFFIX (
    mmsi,
    ts,
    type,
    repeat,
    status,
    turn,
    speed,
    accuracy,
    longitude,
    latitude,
    course,
    heading,
    second,
    maneuvre,
    raim,
    radio,
    wkb_geom
)

(
    SELECT
        mmsi,
        ts,
        type,
        repeat,
        status,
        turn,
        speed,
        accuracy,
        longitude,
        latitude,
        course,
        heading,
        second,
        maneuvre,
        raim,
        radio,
        wkb_geom
    FROM
        ais_logs_dynamic:SUFFIX
    where
        mmsi between 100000000 and 999999999
    AND
        longitude between -180 and 180
    and
        latitude between -90 and 90
    and
        speed >= 10 and speed < 1022
    and
        wkb_geom &&
        st_transform(
            st_setsrid(
                st_makeline(
                    st_makepoint(5794500, 2095665),
                    st_makepoint(6031529, 2323859)
                ),
                3035), 4326)
    order by 
        mmsi, ts, repeat
) ON CONFLICT DO NOTHING;

drop table if exists ais_movement:SUFFIX;
create table ais_movement:SUFFIX as
WITH ordered_track AS
(
    select
        *
    from
        martijn.ais_logs_dynamic_unique:SUFFIX
    order by
        mmsi, ts
)
select
*
from 
(
    select
        *,
        st_setsrid(
            st_makeline(
                st_makepoint(
                    st_x(st_transform(wkb_geom, :SRID)),
                    st_y(st_transform(wkb_geom, :SRID)),
                    extract(epoch from ts)
                ),
                st_makepoint(
                    st_x(lead(st_transform(wkb_geom, :SRID)) over w),
                    st_y(lead(st_transform(wkb_geom, :SRID)) over w),
                    extract(epoch from lead(ts) over w)
                )
            ),
            :SRID)::geometry(LineStringZ, :SRID) as space_time_segment
        -- FIXME: add Course over Ground to the startpoint

    from
        ordered_track
        WINDOW w AS (PARTITION BY mmsi ORDER BY ts)
) tbl
where
    (st_zmax(space_time_segment) - st_zmin(space_time_segment)) <= 44
and 
    st_length(st_force2d(space_time_segment)) between 1 and 801
;

CREATE INDEX ais_movement__geom_idx:SUFFIX ON ais_movement:SUFFIX USING GIST (space_time_segment gist_geometry_ops_nd) TABLESPACE indx;

alter table ais_movement:SUFFIX set tablespace temp;
cluster ais_movement:SUFFIX using ais_movement__geom_idx:SUFFIX;

-- update the stats
analyze ais_movement:SUFFIX;
alter table ais_movement:SUFFIX set tablespace users;
drop table if exists ais_ship_encounters:SUFFIX CASCADE;

-- create the encounter table


-- explain
create unlogged table ais_ship_encounters:SUFFIX tablespace temp
as
select
    own_ship.mmsi as own_ship__mmsi,
    own_ship.ts as own_ship__ts,
    own_ship.type as own_ship__type,
    own_ship.repeat as own_ship__repeat,
    own_ship.status as own_ship__status,
    own_ship.turn as own_ship__turn,
    own_ship.speed as own_ship__speed,
    own_ship.accuracy as own_ship__accuracy,
    own_ship.longitude as own_ship__longitude,
    own_ship.latitude as own_ship__latitude,
    own_ship.course as own_ship__course,
    own_ship.heading as own_ship__heading,
    own_ship.second as own_ship__second,
    own_ship.maneuvre as own_ship__maneuvre,
    own_ship.raim as own_ship__raim,
    own_ship.radio as own_ship__radio,
    own_ship.wkb_geom as own_ship__wkb_geom,
    own_ship.space_time_segment as own_ship__space_time_segment,

    st_setsrid(st_makeline(
        st_force2d(st_startpoint(own_ship.space_time_segment)),
        st_setsrid(
            st_makepoint(
                st_x(st_startpoint(own_ship.space_time_segment)) + :RADIUS * cos(-radians(((own_ship.course - 900) % 3600) / 10.)),
                st_y(st_startpoint(own_ship.space_time_segment)) + :RADIUS * sin(-radians(((own_ship.course - 900) % 3600) / 10.))
            ),
            :SRID
        )
    ), :SRID)::geometry(LineString, :SRID) as own_ship__course_vec,

    st_setsrid(
        st_makeline(
            st_makepoint(
                st_x(st_startpoint(own_ship.space_time_segment)) - :DIST,
                st_y(st_startpoint(own_ship.space_time_segment)) - :DIST
            ),
            st_makepoint(
                st_x(st_startpoint(own_ship.space_time_segment)) + :DIST,
                st_y(st_startpoint(own_ship.space_time_segment)) + :DIST
            )
        )::box2d::geometry(Polygon),
        :SRID
    )::geometry(Polygon, :SRID) as own_ship__query_geom,

    target_ship.mmsi as target_ship__mmsi,
    target_ship.ts as target_ship__ts,
    target_ship.type as target_ship__type,
    target_ship.repeat as target_ship__repeat,
    target_ship.status as target_ship__status,
    target_ship.turn as target_ship__turn,
    target_ship.speed as target_ship__speed,
    target_ship.accuracy as target_ship__accuracy,
    target_ship.longitude as target_ship__longitude,
    target_ship.latitude as target_ship__latitude,
    target_ship.course as target_ship__course,
    target_ship.heading as target_ship__heading,
    target_ship.second as target_ship__second,
    target_ship.maneuvre as target_ship__maneuvre,
    target_ship.raim as target_ship__raim,
    target_ship.radio as target_ship__radio,
    target_ship.wkb_geom as target_ship__wkb_geom,
    target_ship.space_time_segment as target_ship__space_time_segment,

    st_setsrid(
        st_makeline(
            st_force2d(st_startpoint(target_ship.space_time_segment)),
            st_setsrid(
                st_makepoint(
                    st_x(st_startpoint(target_ship.space_time_segment)) + :RADIUS * cos(-radians(((target_ship.course - 900) % 3600) / 10.)),
                    st_y(st_startpoint(target_ship.space_time_segment)) + :RADIUS * sin(-radians(((target_ship.course - 900) % 3600) / 10.))
                ),
                :SRID
            )
        ),
        :SRID)::geometry(LineString, :SRID) as target_ship__course_vec,

    st_multi(st_collect(own_ship.space_time_segment,  target_ship.space_time_segment))::geometry(MultiLineStringZ, :SRID) as encounter__movements,

    -- extract(epoch from own_ship_ts) - extract(epoch from target_ship_ts) as tstart_relative,
    -- tstart_relative / (st_zmax(target_ship_segment) - st_zmin(target_ship_segment)) as fraction,
    -- st_x(st_startpoint(target_ship.space_time_segment)) as xstart,
    -- st_y(st_startpoint(target_ship.space_time_segment)) as ystart,
    -- st_z(st_startpoint(target_ship.space_time_segment)) as zstart,
    -- st_x(st_endpoint(target_ship.space_time_segment)) - st_x(st_startpoint(target_ship.space_time_segment)) as xdelta,
    -- st_y(st_endpoint(target_ship.space_time_segment)) - st_y(st_startpoint(target_ship.space_time_segment)) as ydelta,
    -- st_z(st_endpoint(target_ship.space_time_segment)) - st_z(st_startpoint(target_ship.space_time_segment)) as zdelta

    st_setsrid(
        st_makepoint(
            -- xstart + fraction * xdelta
            st_x(st_startpoint(target_ship.space_time_segment)) +
                (extract(epoch from own_ship.ts) - extract(epoch from target_ship.ts)) / (st_zmax(target_ship.space_time_segment) - st_zmin(target_ship.space_time_segment)) *
                (st_x(st_endpoint(target_ship.space_time_segment)) - st_x(st_startpoint(target_ship.space_time_segment))),

            -- ystart + fraction * ydelta
            st_y(st_startpoint(target_ship.space_time_segment)) +
                (extract(epoch from own_ship.ts) - extract(epoch from target_ship.ts)) / (st_zmax(target_ship.space_time_segment) - st_zmin(target_ship.space_time_segment)) *
                (st_y(st_endpoint(target_ship.space_time_segment)) - st_y(st_startpoint(target_ship.space_time_segment))),

            -- -- zstart + fraction * zdelta
            st_z(st_startpoint(target_ship.space_time_segment)) +
                (extract(epoch from own_ship.ts) - extract(epoch from target_ship.ts)) / (st_zmax(target_ship.space_time_segment) - st_zmin(target_ship.space_time_segment)) *
                (st_z(st_endpoint(target_ship.space_time_segment)) - st_z(st_startpoint(target_ship.space_time_segment)))
        ), :SRID)::geometry(PointZ, :SRID) as target_ship__interpolated_rover,

    st_setsrid(
        st_rotate(
            st_translate(
                own_ship_dims.rectangle, 
                st_x(st_startpoint(own_ship.space_time_segment)),
                st_y(st_startpoint(own_ship.space_time_segment))
            ),
            -radians(((own_ship.course) % 3600) / 10.), -- No -90 deg substract!
            st_x(st_startpoint(own_ship.space_time_segment)),
            st_y(st_startpoint(own_ship.space_time_segment))
        ),
        :SRID)::geometry(Polygon, :SRID)  as own_ship__vessel_extent,

    st_setsrid(
        st_rotate(
            st_translate(
                target_ship_dims.rectangle, 
                st_x(st_startpoint(target_ship.space_time_segment)) +
                    (extract(epoch from own_ship.ts) - extract(epoch from target_ship.ts)) / (st_zmax(target_ship.space_time_segment) - st_zmin(target_ship.space_time_segment)) *
                    (st_x(st_endpoint(target_ship.space_time_segment)) - st_x(st_startpoint(target_ship.space_time_segment))),
                st_y(st_startpoint(target_ship.space_time_segment)) +
                    (extract(epoch from own_ship.ts) - extract(epoch from target_ship.ts)) / (st_zmax(target_ship.space_time_segment) - st_zmin(target_ship.space_time_segment)) *
                    (st_y(st_endpoint(target_ship.space_time_segment)) - st_y(st_startpoint(target_ship.space_time_segment)))

            ),
            -radians(((target_ship.course) % 3600) / 10.), -- No -90 deg substract!
            st_x(st_startpoint(target_ship.space_time_segment)) +
                (extract(epoch from own_ship.ts) - extract(epoch from target_ship.ts)) / (st_zmax(target_ship.space_time_segment) - st_zmin(target_ship.space_time_segment)) *
                (st_x(st_endpoint(target_ship.space_time_segment)) - st_x(st_startpoint(target_ship.space_time_segment))),
            st_y(st_startpoint(target_ship.space_time_segment)) +
                (extract(epoch from own_ship.ts) - extract(epoch from target_ship.ts)) / (st_zmax(target_ship.space_time_segment) - st_zmin(target_ship.space_time_segment)) *
                (st_y(st_endpoint(target_ship.space_time_segment)) - st_y(st_startpoint(target_ship.space_time_segment)))
        ),
        :SRID)::geometry(Polygon, :SRID)  as target_ship__vessel_extent,

    st_setsrid(
        st_translate(
            st_rotate(
                st_translate(
                    st_multi(
                        st_collect(
                            --+-- own_ship
                            -- we translate to the physical center of the own ship
                            -- we use the 'displace_vector' column in the ais_mmsi_vessel_dimensions
                            --   [center] - [receiver]
                            -- table (after rotating, translating to (with 0,0 with receiver position,
                            -- we can shift the whole system of both rotated vessel extents to new origin)
                            st_setsrid(
                                st_rotate(
                                    st_translate(
                                        own_ship_dims.rectangle, 
                                        st_x(st_startpoint(own_ship.space_time_segment)),
                                        st_y(st_startpoint(own_ship.space_time_segment))
                                    ),
                                    -radians(((own_ship.course) % 3600) / 10.), -- No -90 deg substract!
                                    st_x(st_startpoint(own_ship.space_time_segment)),
                                    st_y(st_startpoint(own_ship.space_time_segment))
                                ),
                                :SRID
                            )
                            ,
                            --+-- target_ship at interpolated position of time t=own_ship__ts
                            st_setsrid(
                                st_rotate(
                                    st_translate(
                                        target_ship_dims.rectangle, 
                                        st_x(st_startpoint(target_ship.space_time_segment)) +
                                            (extract(epoch from own_ship.ts) - extract(epoch from target_ship.ts)) / (st_zmax(target_ship.space_time_segment) - st_zmin(target_ship.space_time_segment)) *
                                            (st_x(st_endpoint(target_ship.space_time_segment)) - st_x(st_startpoint(target_ship.space_time_segment))),
                                        st_y(st_startpoint(target_ship.space_time_segment)) +
                                            (extract(epoch from own_ship.ts) - extract(epoch from target_ship.ts)) / (st_zmax(target_ship.space_time_segment) - st_zmin(target_ship.space_time_segment)) *
                                            (st_y(st_endpoint(target_ship.space_time_segment)) - st_y(st_startpoint(target_ship.space_time_segment)))
                                    ),
                                    -radians(((target_ship.course) % 3600) / 10.), -- No -90 deg substract!
                                    st_x(st_startpoint(target_ship.space_time_segment)) +
                                        (extract(epoch from own_ship.ts) - extract(epoch from target_ship.ts)) / (st_zmax(target_ship.space_time_segment) - st_zmin(target_ship.space_time_segment)) *
                                        (st_x(st_endpoint(target_ship.space_time_segment)) - st_x(st_startpoint(target_ship.space_time_segment))),
                                    st_y(st_startpoint(target_ship.space_time_segment)) +
                                        (extract(epoch from own_ship.ts) - extract(epoch from target_ship.ts)) / (st_zmax(target_ship.space_time_segment) - st_zmin(target_ship.space_time_segment)) *
                                        (st_y(st_endpoint(target_ship.space_time_segment)) - st_y(st_startpoint(target_ship.space_time_segment)))
                                ),
                                :SRID
                            )
                        )
                    ),
                    -st_x(st_startpoint(own_ship.space_time_segment)),
                    -st_y(st_startpoint(own_ship.space_time_segment))
                ),
                -- rotate so that own ship its course is heading north
                +radians(((own_ship.course) % 3600) / 10.)
            ),
            -- move both to center of ship
            st_x(own_ship_dims.receiver) - st_x(own_ship_dims.center),
            st_y(own_ship_dims.receiver) - st_y(own_ship_dims.center)
        ),
        0
    )::geometry(MultiPolygon, 0) as encounter__extents__own_ship_origin,

    own_ship_dims.width as own_ship__dims_width,
    own_ship_dims.length as own_ship__dims_length,

    target_ship_dims.width as target_ship__dims_width,
    target_ship_dims.length as target_ship__dims_length,

    own_ship_shiptype.shiptype as own_ship__shiptype,
    target_ship_shiptype.shiptype as target_ship__shiptype,

    -- relative velocity
    sqrt(
        pow(own_ship.speed / 10.0, 2) + pow(target_ship.speed / 10.0, 2)
        -2.0 * (own_ship.speed / 10.0) * (target_ship.speed / 10.0) * cos(radians(((own_ship.course) % 3600) / 10.) - radians(((target_ship.course) % 3600) / 10.))
    ) as encounter__relative_velocity

from 
    ais_movement:SUFFIX own_ship

join
    ais_movement:SUFFIX target_ship
on
    st_setsrid(
        st_makeline(
            st_makepoint(
                st_x(st_startpoint(own_ship.space_time_segment)) - :DIST,
                st_y(st_startpoint(own_ship.space_time_segment)) - :DIST,
                st_zmin(own_ship.space_time_segment)
            ),
            st_makepoint(
                st_x(st_startpoint(own_ship.space_time_segment)) + :DIST,
                st_y(st_startpoint(own_ship.space_time_segment)) + :DIST,
                st_zmin(own_ship.space_time_segment)
            )
        ),
        :SRID
    )
&&&
    target_ship.space_time_segment

and 
    own_ship.mmsi <> target_ship.mmsi

-- separating axis theorem
-- needed, as I do not trust fully the &&& computation (which in principle should be sufficient)

-- as we have flat 'slice' at one time moment, we use twice st_zmin, i.e. at the start of the movement
and
    not st_zmax(target_ship.space_time_segment) < st_zmin(own_ship.space_time_segment)
and 
    not st_zmin(target_ship.space_time_segment) > st_zmin(own_ship.space_time_segment)
-- and
--    st_zmin(own_ship.space_time_segment)
--        between st_zmin(target_ship.space_time_segment) and st_zmax(target_ship.space_time_segment)
and
    not st_xmax(target_ship.space_time_segment) < st_x(st_startpoint(own_ship.space_time_segment)) - :DIST
and 
    not st_xmin(target_ship.space_time_segment) > st_x(st_startpoint(own_ship.space_time_segment)) + :DIST
and
    not st_ymax(target_ship.space_time_segment) < st_y(st_startpoint(own_ship.space_time_segment)) - :DIST
and
    not st_ymin(target_ship.space_time_segment) > st_y(st_startpoint(own_ship.space_time_segment)) + :DIST

--and
--st_3dintersects(
--    st_setsrid(
--        st_makeline(
--            st_makepoint(
--                st_x(st_startpoint(own_ship.space_time_segment)) - :DIST,
--                st_y(st_startpoint(own_ship.space_time_segment)) - :DIST,
--                st_zmin(own_ship.space_time_segment)
--            ),
--            st_makepoint(
--                st_x(st_startpoint(own_ship.space_time_segment)) + :DIST,
--                st_y(st_startpoint(own_ship.space_time_segment)) + :DIST,
--                st_zmin(own_ship.space_time_segment)
--            )
--        ),
--        :SRID
--    )::box3d,
--    target_ship.space_time_segment::box3d
--)
left join
    ais_mmsi_vessel_dimensions own_ship_dims
on 
     own_ship_dims.mmsi = own_ship.mmsi

left join
    ais_mmsi_vessel_dimensions target_ship_dims
on 
    target_ship_dims.mmsi = target_ship.mmsi 


left join 
    ais_mmsi_shiptype own_ship_shiptype
on 
    own_ship_shiptype.mmsi = own_ship.mmsi


left join 
    ais_mmsi_shiptype target_ship_shiptype
on 
    target_ship_shiptype.mmsi = target_ship.mmsi

;

--FIXME: distance ?

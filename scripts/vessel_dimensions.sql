--geodata=# 
\timing on

-- drop table if exists ais_mmsi_dims;
-- create table ais_mmsi_dims as
-- select distinct
--     mmsi,
--     to_bow,
--     to_stern,
--     to_port,
--     to_starboard,
--     to_bow+to_stern as length,
--     to_port+to_starboard as width
-- from
--     ais_logs_static
-- where
--     to_port > 0 and to_starboard > 0 and to_bow > 0 and to_stern > 0
-- AND
--     mmsi between 100000000 and 999999999
--     ;

-- to record how many records for each combi of dimensions
-- we can count also the records in the seen table
-- with the window query we remove duplicates and keep only the most seen version
-- this way we do not loose any mmsi number for which we have information in our database
-- (although it still may be that there are multiple *valid* versions of the dimensions per boat -- e.g. tug boat convoy - changes its size over time)

-- TODO: maybe later:
-- a more involved way, would be to create a temporal version of this data:
-- when is a specific set of dimensions valid over time period -
-- it seems as if there can be even multiple gps antennas on the boat, 
-- as the (width,length) are the same,
-- but the location of the receiver on the vessel is not (port/starboard does change with few meters)
drop table if exists ais_mmsi_dims_most_freq_order;
create temp table
    ais_mmsi_dims_most_freq_order
as

WITH ordered_dims AS
(
    select
        mmsi,
        count(ts) as seen,
        to_bow,
        to_stern,
        to_port,
        to_starboard,
        to_bow+to_stern as length,
        to_port+to_starboard as width
    from
        ais_logs_static
    where
        mmsi between 100000000 and 999999999
    and
        to_port > 0 and to_starboard > 0 and to_bow > 0 and to_stern > 0
    group by
        mmsi, to_bow, to_stern, to_port, to_starboard
    order by
        mmsi, count(ts) desc
)

select 
    mmsi,
    to_bow,
    to_stern,
    to_port,
    to_starboard,
    length,
    width
from (
    select 
        mmsi,
        to_bow,
        to_stern,
        to_port,
        to_starboard,
        length,
        width,
        row_number() over w row_num
    FROM
        ordered_dims WINDOW w AS (PARTITION BY mmsi ORDER BY seen desc)
    ) as tbl
where
    row_num=1
;

--SELECT 16147
--Time: 23944.641 ms (00:23.945)

-- select mmsi, count(*), min(width) as minw, max(width) as maxw, min(length) minl, max(length) maxl from (select mmsi, width, length from ais_mmsi_dims group by mmsi, width, length) as foo group by mmsi having count(*) > 1 order by mmsi;

select count(distinct mmsi) as distinct_mmsi_static_report_ct from ais_logs_static;

-- dimensions positive how many are there...
select count(distinct mmsi) as ct_all_mmsi_dims from ais_mmsi_dims_most_freq_order;

-- -- 
-- select count(*) as ct_mmsi_with_multi_dims_orig_values
-- from
-- (
-- select mmsi from (select mmsi, to_bow, to_stern, to_port, to_starboard from ais_mmsi_dims group by mmsi, to_bow, to_stern, to_port, to_starboard) as foo group by mmsi having count(*) > 1 order by mmsi
-- ) as f;

-- --
-- select count(*) as ct_mmsi_with_one_dims_orig_values
-- from
-- (
-- select mmsi from (select mmsi, to_bow, to_stern, to_port, to_starboard from ais_mmsi_dims group by mmsi, to_bow, to_stern, to_port, to_starboard) as foo group by mmsi having count(*) = 1 order by mmsi
-- ) as f;

-- -- not just 1 set of dimensions (width/length)
-- select count(*) as ct_mmsi_with_multi_dims
-- from
-- (
-- select mmsi from (select mmsi, width, length, count(*) as recs from ais_mmsi_dims group by mmsi, width, length) as foo group by mmsi having count(*) > 1 order by mmsi
-- ) as f;

-- -- just 1 set of dimensions (width/length)
-- select count(*) as ct_mmsi_with_one_dims
-- from
-- (
-- select mmsi from (select mmsi, width, length from ais_mmsi_dims group by mmsi, width, length) as foo group by mmsi having count(*) = 1 order by mmsi
-- ) as f;




---- find the center of the boat
-- in a local system with (0,0) being the most lower left point in the hull
drop table if exists ais_mmsi_vessel_dimensions;

create table
    ais_mmsi_vessel_dimensions
as
select
    mmsi,

    to_bow,
    to_stern,
    to_port,
    to_starboard,

    width,
    length,

    st_makepoint(abs(to_port), abs(to_stern))::geometry(Point, 0) as receiver,
    st_makepoint(width * 0.5, length * 0.5)::geometry(Point, 0) as center,

    -- FIXME: also could just use the endpoint of this line (and save storing (0, 0) repeatedly)
    -- this has the advantage of knowing the length of the displacement as well -- st_length(displace_vector)
    st_makeline(
        st_makepoint(0, 0),
        st_makepoint(
            width  * 0.5 - abs(to_port),
            length * 0.5 - abs(to_stern)
        )  -- [center] - [receiver] 
    )::geometry(LineString, 0) as displace_vector,

    st_translate(
        st_makepolygon(
            st_makeline(
                ARRAY[
                    st_makepoint(0, 0),
                    
                    -- 3 points at bow ::
                     st_makepoint(0, length- (0.1*length)),
                     st_makepoint(0.5*width, length),
                     st_makepoint(width, length-(0.1*length)),

                    -- 2 points at bow ::
--                    st_makepoint(0, length),
--                    st_makepoint(width, length),

                    st_makepoint(width, 0),
                    st_makepoint(0, 0)
                ]
            )
        )::geometry(Polygon, 0),
        -abs(to_port),
        -abs(to_stern)
    ) as rectangle

from
    ais_mmsi_dims_most_freq_order
;

CREATE UNIQUE INDEX ais_mmsi_vessel_dimensions__mmsi__idx ON ais_mmsi_vessel_dimensions (mmsi) TABLESPACE indx;
ALTER TABLE ais_mmsi_vessel_dimensions ADD CONSTRAINT ais_mmsi_vessel_dimensions_pkey PRIMARY KEY USING INDEX ais_mmsi_vessel_dimensions__mmsi__idx;

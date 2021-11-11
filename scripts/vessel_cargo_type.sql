\timing ON

drop table if exists ais_mmsi_shiptype;

create table
ais_mmsi_shiptype
as

WITH ordered_types AS
(
    select 
        mmsi,
        count(ts) as seen,
        case when shiptype between 0 and 99 then
            shiptype
        else
            0
        end as shiptype
    from
        ais_logs_static
    group by
        mmsi,
        case when shiptype between 0 and 99 then shiptype else 0 end 
    order by 
        mmsi, 
        count(ts) desc
)
select
    mmsi,
    shiptype
from 
    (
    select 
        *,
        row_number() over w row_num
    FROM
        ordered_types WINDOW w AS (PARTITION BY mmsi ORDER BY seen desc)
    ) as tbl
where 
    tbl.row_num=1
;

CREATE UNIQUE INDEX ais_mmsi_shiptype__mmsi__idx ON ais_mmsi_shiptype (mmsi) TABLESPACE indx;
ALTER TABLE ais_mmsi_shiptype ADD CONSTRAINT ais_mmsi_shiptype_pkey PRIMARY KEY USING INDEX ais_mmsi_shiptype__mmsi__idx;

-- ais_vessel_cargo_type

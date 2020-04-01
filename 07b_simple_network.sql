-- Views for network following with the Python NetworkX module and the QGEP Python plugins

/*
This generates a graph reprensenting the network.

To help debug, shorten all lines using

SET session_replication_role = replica; -- disable triggers
UPDATE qgep_od.vw_qgep_reach SET progression_geometry = 
  case
    when st_geometrytype(ST_ForceCurve(ST_Line_Substring(ST_CurveToLine(progression_geometry), 0.1, 0.9))) = 'ST_CompoundCurve' then
    ST_ForceCurve(ST_Line_Substring(ST_CurveToLine(progression_geometry), 0.1, 0.9))
    else progression_geometry
  end;
SET session_replication_role = DEFAULT;
*/

DROP TABLE IF EXISTS qgep_od.vw_network_node_simple CASCADE;
CREATE TABLE qgep_od.vw_network_node_simple (
  id SERIAL PRIMARY KEY,
  node_type TEXT,
  ne_id TEXT REFERENCES qgep_od.wastewater_networkelement(obj_id),
  geom geometry('POINT', 2056)
);

DROP TABLE IF EXISTS qgep_od.vw_network_edge_simple CASCADE;
CREATE TABLE qgep_od.vw_network_edge_simple (
  id SERIAL PRIMARY KEY,
  from_node INT REFERENCES qgep_od.vw_network_node_simple(id),
  to_node INT REFERENCES qgep_od.vw_network_node_simple(id),
  geom geometry('POINT', 2056)
);

CREATE OR REPLACE FUNCTION qgep_od.refresh_network_simple() RETURNS void AS $body$
BEGIN

  DELETE FROM qgep_od.vw_network_node_simple;
  DELETE FROM qgep_od.vw_network_edge_simple;

  INSERT INTO qgep_od.vw_network_node_simple(node_type, ne_id, geom)
  SELECT DISTINCT * FROM (
    
    -- Insert nodes for wastewater nodes
    SELECT
      'wastewater_node',
      n.obj_id,
      ST_Force2D(n.situation_geometry)
    FROM qgep_od.wastewater_node n

    UNION

    -- Insert reachpoints
    SELECT
      'reachpoint',
      r.obj_id,
      ST_Force2D(rp.situation_geometry)
    FROM qgep_od.reach_point rp
    JOIN qgep_od.reach r ON rp.obj_id = r.fk_reach_point_from OR rp.obj_id = r.fk_reach_point_to

    UNION

    -- Insert virtual nodes for blind connections
    SELECT
      'reachpoint',
      r.obj_id,
      ST_Force2D(rp.situation_geometry)
    FROM qgep_od.reach r
    INNER JOIN qgep_od.reach_point rp ON rp.fk_wastewater_networkelement = r.obj_id
    WHERE ST_LineLocatePoint(ST_CurveToLine(r.progression_geometry), rp.situation_geometry) NOT IN (0.0, 1.0) -- if exactly at start or at end, we don't need a virtualnode as we have the reachpoint

  ) nodes;

  -- Insert reaches
  INSERT INTO qgep_od.vw_network_edge_simple (from_node, to_node, geom)
  SELECT sub2.node_id_1,
         sub2.node_id_2,
         ST_Line_Substring(
           ST_CurveToLine(progression_geometry), ratio_1, ratio_2
         )
  FROM (
    -- This subquery uses LAG to combine a node with the next on a reach.
    SELECT LAG(sub1.node_id) OVER (PARTITION BY sub1.obj_id ORDER BY sub1.ratio) as node_id_1,
           sub1.node_id as node_id_2,
           sub1.progression_geometry,
           LAG(sub1.ratio) OVER (PARTITION BY sub1.obj_id ORDER BY sub1.ratio) as ratio_1,
           sub1.ratio as ratio_2
    FROM (
        -- This subquery selects joins node to reach, with "ratio" being the position of the node along the reach
        SELECT r.obj_id,
               r.progression_geometry,
               n.id as node_id,
               ST_LineLocatePoint(ST_CurveToLine(r.progression_geometry), n.geom) AS ratio
        FROM qgep_od.reach r
        JOIN qgep_od.vw_network_node_simple n ON n.ne_id = r.obj_id
    ) AS sub1
  ) AS sub2
  WHERE ratio_1 is not NULL;

  /*
  DEBUGDEBUG
  SELECT obj_id, sub2.node_id_1,
         sub2.node_id_2,
         ratio_1,
         ratio_2,
         ST_Line_Substring(
           ST_CurveToLine(progression_geometry), ratio_1, ratio_2
         ),
         ST_GeometryType(ST_Line_Substring(
           ST_CurveToLine(progression_geometry), ratio_1, ratio_2
         )) as geomtype
  FROM (
    -- This subquery uses LAG to combine a node with the next on a reach.
    SELECT obj_id,
           LAG(sub1.node_id) OVER (PARTITION BY sub1.obj_id ORDER BY sub1.ratio) as node_id_1,
           sub1.node_id as node_id_2,
           sub1.progression_geometry,
           LAG(sub1.ratio) OVER (PARTITION BY sub1.obj_id ORDER BY sub1.ratio) as ratio_1,
           sub1.ratio as ratio_2
    FROM (
        -- This subquery selects joins node to reach, with "ratio" being the position of the node along the reach
        SELECT r.obj_id,
               r.progression_geometry,
               n.id as node_id,
               ST_LineLocatePoint(ST_CurveToLine(r.progression_geometry), n.geom) AS ratio
        FROM qgep_od.reach r
        JOIN qgep_od.vw_network_node_simple n ON n.ne_id = r.obj_id
    ) AS sub1
  ) AS sub2
  WHERE ratio_1 is not null and ST_GeometryType(ST_Line_Substring(
           ST_CurveToLine(progression_geometry), ratio_1, ratio_2
         )) <> 'ST_LineString';
         */

--        LAG(ratio) OVER (PARTITION BY r.obj_id ORDER BY ratio)

END;
$body$
LANGUAGE plpgsql;

SELECT qgep_od.refresh_network_simple();

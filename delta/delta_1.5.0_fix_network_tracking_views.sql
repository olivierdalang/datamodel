-- Views for network following with the Python NetworkX module and the QGEP Python plugins

/*
This generates a graph reprensenting the network.
*/

CREATE SCHEMA qgep_network;

CREATE TABLE qgep_network.node (
  id SERIAL PRIMARY KEY,
  node_type TEXT,
  ne_id TEXT NULL REFERENCES qgep_od.wastewater_networkelement(obj_id), -- for reachpoints, this will reference the reach object
  rp_id TEXT NULL REFERENCES qgep_od.reach_point(obj_id), -- will only be set for reachpoints
  geom geometry('POINT', 2056)
);

CREATE TABLE qgep_network.segment (
  id SERIAL PRIMARY KEY,
  from_node INT REFERENCES qgep_network.node(id),
  to_node INT REFERENCES qgep_network.node(id),
  ne_id TEXT NULL REFERENCES qgep_od.wastewater_networkelement(obj_id), -- will only be set for segments corresponding to reaches
  geom geometry('LINESTRING', 2056)
);

CREATE OR REPLACE FUNCTION qgep_network.refresh_network_simple() RETURNS void AS $body$
BEGIN

  DELETE FROM qgep_network.node;
  DELETE FROM qgep_network.segment;

  -- Insert nodes for wastewater nodes
  INSERT INTO qgep_network.node(node_type, ne_id, geom)    
  SELECT
    'wastewater node',
    n.obj_id,
    ST_Force2D(n.situation_geometry)
  FROM qgep_od.wastewater_node n;

  -- Insert reachpoints
  INSERT INTO qgep_network.node(node_type, ne_id, rp_id, geom)
  SELECT
    'reachpoint',
    r.obj_id, -- the reachpoint also keeps a reference to it's reach, as it can be used by blind connections that happen exactly on start/end points
    rp.obj_id,
    ST_Force2D(rp.situation_geometry)
  FROM qgep_od.reach_point rp
  JOIN qgep_od.reach r ON rp.obj_id = r.fk_reach_point_from OR rp.obj_id = r.fk_reach_point_to;

  -- Insert virtual nodes for blind connections
  -- INSERT INTO qgep_network.node(node_type, ne_id, description, geom)
  INSERT INTO qgep_network.node(node_type, ne_id, geom)
  SELECT DISTINCT
    'blind connection',
    r.obj_id,
    ST_ClosestPoint(r.progression_geometry, rp.situation_geometry)
  FROM qgep_od.reach r
  INNER JOIN qgep_od.reach_point rp ON rp.fk_wastewater_networkelement = r.obj_id
  WHERE ST_LineLocatePoint(ST_CurveToLine(r.progression_geometry), rp.situation_geometry) NOT IN (0.0, 1.0); -- if exactly at start or at end, we don't need a virtualnode as we have the reachpoint

  -- Insert reaches, subdivided according to blind reaches
  INSERT INTO qgep_network.segment (from_node, to_node, ne_id, geom)
  SELECT sub2.node_id_1,
         sub2.node_id_2,
         obj_id,
         ST_Line_Substring(
           ST_CurveToLine(ST_Force2D(progression_geometry)), ratio_1, ratio_2
         )
  FROM (
    -- This subquery uses LAG to combine a node with the next on a reach.
    SELECT LAG(sub1.node_id) OVER (PARTITION BY sub1.obj_id ORDER BY sub1.ratio) as node_id_1,
           sub1.node_id as node_id_2,
           sub1.progression_geometry,
           LAG(sub1.ratio) OVER (PARTITION BY sub1.obj_id ORDER BY sub1.ratio) as ratio_1,
           sub1.ratio as ratio_2,
           obj_id
    FROM (
        -- This subquery joins blind node to reach, with "ratio" being the position of the node along the reach
        SELECT r.obj_id,
               r.progression_geometry,
               n.id as node_id,
               ST_LineLocatePoint(ST_CurveToLine(r.progression_geometry), n.geom) AS ratio
        FROM qgep_od.reach r
        JOIN qgep_network.node n ON n.ne_id = r.obj_id
    ) AS sub1
  ) AS sub2
  WHERE ratio_1 IS NOT NULL AND ratio_1 <> ratio_2;

  -- Insert edge between reachpoint (from) to the closest node belonging to the wasterwater network element
  INSERT INTO qgep_network.segment (from_node, to_node, geom)
  SELECT DISTINCT ON(n1.id)
         n2.id,
         n1.id,
         ST_MakeLine(n2.geom, n1.geom)
  FROM (
    
    SELECT
      rp.obj_id as rp_obj_id,
      rp.fk_wastewater_networkelement as wwne_id
    FROM qgep_od.reach_point rp
    JOIN qgep_od.reach r ON rp.obj_id = r.fk_reach_point_from
    WHERE rp.fk_wastewater_networkelement IS NOT NULL

  ) AS sub1
  JOIN qgep_network.node as n1 ON n1.rp_id = rp_obj_id
  JOIN qgep_network.node as n2 ON n2.ne_id = wwne_id
  ORDER BY n1.id, ST_Distance(n1.geom, n2.geom);

  -- Insert edge between reachpoint (to) to the closest node belonging to the wasterwater network element
  INSERT INTO qgep_network.segment (from_node, to_node, geom)
  SELECT DISTINCT ON(n1.id)
         n1.id,
         n2.id,
         ST_MakeLine(n1.geom, n2.geom)
  FROM (
    
    SELECT
      rp.obj_id as rp_obj_id,
      rp.fk_wastewater_networkelement as wwne_id
    FROM qgep_od.reach_point rp
    JOIN qgep_od.reach r ON rp.obj_id = r.fk_reach_point_to
    WHERE rp.fk_wastewater_networkelement IS NOT NULL

  ) AS sub1
  JOIN qgep_network.node as n1 ON n1.rp_id = rp_obj_id
  JOIN qgep_network.node as n2 ON n2.ne_id = wwne_id
  ORDER BY n1.id, ST_Distance(n1.geom, n2.geom);

  REFRESH MATERIALIZED VIEW qgep_od.vw_network_node;
  REFRESH MATERIALIZED VIEW qgep_od.vw_network_segment;

END;
$body$
LANGUAGE plpgsql;


/*
-- Retro-compatbility views
DROP MATERIALIZED VIEW IF EXISTS qgep_od.vw_network_node CASCADE;
DROP MATERIALIZED VIEW IF EXISTS qgep_od.vw_network_segment CASCADE;

CREATE MATERIALIZED VIEW qgep_od.vw_network_segment AS
SELECT s.id as gid,
       s.geom AS progression_geometry,
       ne_id AS obj_id,
       CASE WHEN ne_id IS NOT NULL THEN 'reach' ELSE 'connection' END AS type,
       from_node AS from_obj_id,
       to_node AS to_obj_id,
       ST_Length(geom) AS length_calc
FROM qgep_network.segment s;

CREATE MATERIALIZED VIEW qgep_od.vw_network_node AS
SELECT s.id as gid,
       COALESCE(rp_id, ne_id) as obj_id,
       node_type as type,
       s.geom AS situation_geometry,
       COALESCE(rp.identifier, ne.identifier || CASE WHEN node_type = 'blind connection' THEN '-BC' ELSE '' END) AS description
FROM qgep_network.node s
LEFT JOIN qgep_od.reach_point rp ON rp_id = rp.obj_id
LEFT JOIN qgep_od.wastewater_networkelement ne ON ne_id = ne.obj_id;
*/
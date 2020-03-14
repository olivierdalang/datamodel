-- Views for network following with the Python NetworkX module and the QGEP Python plugins

/*
This generates a graph reprensenting the network.

Reaches are 
*/
DROP TABLE IF EXISTS qgep_od.vw_network_node_simple CASCADE;
CREATE TABLE qgep_od.vw_network_node_simple (
  id TEXT PRIMARY KEY,
  geom geometry('GEOMETRY', 2056)
);

DROP TABLE IF EXISTS qgep_od.vw_network_edge_simple CASCADE;
CREATE TABLE qgep_od.vw_network_edge_simple (
  id TEXT PRIMARY KEY,
  node_from TEXT REFERENCES qgep_od.vw_network_node_simple(id),
  node_to TEXT REFERENCES qgep_od.vw_network_node_simple(id)
);


DROP VIEW IF EXISTS qgep_od.vw_network_view_simple;

CREATE VIEW qgep_od.vw_network_view_simple AS (
  SELECT e.id, ST_MakeLine(n1.geom, n2.geom)
  FROM qgep_od.vw_network_edge_simple e
  JOIN qgep_od.vw_network_node_simple n1 ON e.node_from = n1.id
  JOIN qgep_od.vw_network_node_simple n2 ON e.node_to = n2.id
);


CREATE OR REPLACE FUNCTION qgep_od.refresh_network_simple() RETURNS void AS $body$
BEGIN
  /* Empty the tables */
  DELETE FROM qgep_od.vw_network_edge_simple;
  DELETE FROM qgep_od.vw_network_node_simple;

  /* CORRECT ??? APPRAOCH : wastewaterelements are nodes (incl. reaches) */
  -- Add reaches and waswater_nodes (as nodes)
  INSERT INTO qgep_od.vw_network_node_simple (id, geom)
  SELECT obj_id, ST_Force2D(situation_geometry)
  FROM qgep_od.wastewater_node n
  UNION
  SELECT obj_id, ST_LineSubstring(ST_CurveToLine(ST_Force2D(progression_geometry)), 0.1, 0.9)
  FROM qgep_od.reach n;

  -- Connect the reaches FROMs (using edges)
  INSERT INTO qgep_od.vw_network_edge_simple (id, node_from, node_to)
  SELECT rp.obj_id, rp.fk_wastewater_networkelement, r.obj_id
  FROM qgep_od.reach_point rp
  JOIN qgep_od.reach r ON r.fk_reach_point_from = rp.obj_id;

  -- Connect the reaches TOs (using edges)
  INSERT INTO qgep_od.vw_network_edge_simple (id, node_from, node_to)
  SELECT rp.obj_id, r.obj_id, rp.fk_wastewater_networkelement
  FROM qgep_od.reach_point rp
  JOIN qgep_od.reach r ON r.fk_reach_point_to = rp.obj_id;


  /* NAIVE APPROACH : reaches are edges
  -- Add reachpoints (as nodes)
  INSERT INTO qgep_od.vw_network_node_simple (id, geom)
  SELECT obj_id, ST_Force2D(situation_geometry) FROM qgep_od.reach_point;

  -- Add wastewaternodes (as nodes)
  INSERT INTO qgep_od.vw_network_node_simple (id, geom)
  SELECT obj_id, ST_Force2D(situation_geometry) FROM qgep_od.wastewater_node;

  -- Add reaches (as edges, between reachpoints)
  INSERT INTO qgep_od.vw_network_edge_simple (id, node_from, node_to)
  SELECT obj_id, fk_reach_point_from, fk_reach_point_to FROM qgep_od.reach;
  
  -- Add reachpoints connections (as edges, between reachpoints and wasterwater nodes)
  INSERT INTO qgep_od.vw_network_edge_simple (id, node_from, node_to)
  SELECT obj_id, obj_id, fk_wastewater_networkelement FROM qgep_od.reach_point;
  */

  /*

  select
 array_agg(re_branch.obj_id) as branches,
 array_agg(re_trunk.obj_id) as trunks,
 rp_to.situation_geometry
from qgep_od.reach re_branch
 left join qgep_od.reach_point rp_to
 on re_branch.fk_reach_point_to = rp_to.obj_id
 left join qgep_od.reach re_trunk
 on re_trunk.obj_id = rp_to.fk_wastewater_networkelement
 where re_trunk.obj_id is not null
 group by situation_geometry;
 */
END;
$body$
LANGUAGE plpgsql;


SELECT qgep_od.refresh_network_simple();
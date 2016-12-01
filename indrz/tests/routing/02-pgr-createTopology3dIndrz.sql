-- Function: public.pgr_createtopology3dIndrz(text, double precision, text, text, text, text, text, boolean)

-- DROP FUNCTION public.pgr_createtopology3dIndrz(text, double precision, text, text, text, text, text, boolean);

CREATE OR REPLACE FUNCTION public.pgr_createtopology3dIndrz(
    edge_table text,
  from_zlev text,
  to_zlev text,
    tolerance double precision,
    the_geom text DEFAULT 'the_geom'::text,
    id text DEFAULT 'id'::text,
    source text DEFAULT 'source'::text,
    target text DEFAULT 'target'::text,
    rows_where text DEFAULT 'true'::text,
    clean boolean DEFAULT false)
  RETURNS character varying AS
$BODY$

DECLARE
    points record;
    sridinfo record;
    source_id bigint;
    target_id bigint;
    totcount bigint;
    rowcount bigint;
    srid integer;
    sql text;
    sname text;
    tname text;
    tabname text;
    vname text;
    vertname text;
    gname text;
    idname text;
    sourcename text;
    targetname text;
    notincluded integer;
    i integer;
    naming record;
    info record;
    flag boolean;
    query text;
    idtype text;
    gtype text;
    sourcetype text;
    targettype text;
    debuglevel text;
    dummyRec text;
    fnName text;
    err bool;
    msgKind int;
    emptied BOOLEAN;

BEGIN
    msgKind = 1; -- notice
    fnName = 'pgr_createtopology3dIndrz';
    raise notice 'PROCESSING:';
    raise notice 'pgr_createtopology3dIndrz(''%'', %, ''%'', ''%'', ''%'', ''%'', rows_where := ''%'', clean := %)',edge_table,from_zlev, to_zlev, tolerance,the_geom,id,source,target,rows_where, clean;
    execute 'show client_min_messages' into debuglevel;


    raise notice 'Performing checks, please wait .....';

        execute 'select * from _pgr_getTableName('|| quote_literal(edge_table)
                                                  || ',2,' || quote_literal(fnName) ||' )' into naming;
        sname=naming.sname;
        tname=naming.tname;
        tabname=sname||'.'||tname;
        vname=tname||'_vertices_pgr';
        vertname= sname||'.'||vname;
        rows_where = ' AND ('||rows_where||')';
      raise DEBUG '     --> OK';


      raise debug 'Checking column names in edge table';
        select * into idname     from _pgr_getColumnName(sname, tname,id,2,fnName);
        select * into sourcename from _pgr_getColumnName(sname, tname,source,2,fnName);
        select * into targetname from _pgr_getColumnName(sname, tname,target,2,fnName);
        select * into gname      from _pgr_getColumnName(sname, tname,the_geom,2,fnName);


        err = sourcename in (targetname,idname,gname) or  targetname in (idname,gname) or idname=gname;
        perform _pgr_onError( err, 2, fnName,
               'Two columns share the same name', 'Parameter names for id,the_geom,source and target  must be different',
	       'Column names are OK');

      raise DEBUG '     --> OK';

      raise debug 'Checking column types in edge table';
        select * into sourcetype from _pgr_getColumnType(sname,tname,sourcename,1, fnName);
        select * into targettype from _pgr_getColumnType(sname,tname,targetname,1, fnName);
        select * into idtype from _pgr_getColumnType(sname,tname,idname,1, fnName);

        err = idtype not in('integer','smallint','bigint');
        perform _pgr_onError(err, 2, fnName,
	       'Wrong type of Column id:'|| idname, ' Expected type of '|| idname || ' is integer,smallint or bigint but '||idtype||' was found');

        err = sourcetype not in('integer','smallint','bigint');
        perform _pgr_onError(err, 2, fnName,
	       'Wrong type of Column source:'|| sourcename, ' Expected type of '|| sourcename || ' is integer,smallint or bigint but '||sourcetype||' was found');

        err = targettype not in('integer','smallint','bigint');
        perform _pgr_onError(err, 2, fnName,
	       'Wrong type of Column target:'|| targetname, ' Expected type of '|| targetname || ' is integer,smallint or bigint but '||targettype||' was found');

      raise DEBUG '     --> OK';

      raise debug 'Checking SRID of geometry column';
         query= 'SELECT ST_SRID(' || quote_ident(gname) || ') as srid '
            || ' FROM ' || _pgr_quote_ident(tabname)
            || ' WHERE ' || quote_ident(gname)
            || ' IS NOT NULL LIMIT 1';
         raise debug '%',query;
         EXECUTE query INTO sridinfo;

         err =  sridinfo IS NULL OR sridinfo.srid IS NULL;
         perform _pgr_onError(err, 2, fnName,
	     'Can not determine the srid of the geometry '|| gname ||' in table '||tabname, 'Check the geometry of column '||gname);

         srid := sridinfo.srid;
      raise DEBUG '     --> OK';

      raise debug 'Checking and creating indices in edge table';
        perform _pgr_createIndex(sname, tname , idname , 'btree'::text);
        perform _pgr_createIndex(sname, tname , sourcename , 'btree'::text);
        perform _pgr_createIndex(sname, tname , targetname , 'btree'::text);
        perform _pgr_createIndex(sname, tname , gname , 'gist'::text);

        gname=quote_ident(gname);
        idname=quote_ident(idname);
        sourcename=quote_ident(sourcename);
        targetname=quote_ident(targetname);
      raise DEBUG '     --> OK';





    BEGIN
        -- issue #193 & issue #210 & #213
        -- this sql is for trying out the where clause
        -- the select * is to avoid any colum name conflicts
        -- limit 1, just try on first record
        -- if the where clasuse is ill formed it will be catched in the exception
        sql = 'select * from '||_pgr_quote_ident(tabname)||' WHERE true'||rows_where ||' limit 1';
        EXECUTE sql into dummyRec;
        -- end

        -- if above where clasue works this one should work
        -- any error will be catched by the exception also
        sql = 'select count(*) from '||_pgr_quote_ident(tabname)||' WHERE (' || gname || ' IS NOT NULL AND '||
	    idname||' IS NOT NULL)=false '||rows_where;
        EXECUTE SQL  into notincluded;

        if clean then
            raise debug 'Cleaning previous Topology ';
               execute 'UPDATE ' || _pgr_quote_ident(tabname) ||
               ' SET '||sourcename||' = NULL,'||targetname||' = NULL';
        else
            raise debug 'Creating topology for edges with non assigned topology';
            if rows_where=' AND (true)' then
                rows_where=  ' and ('||quote_ident(sourcename)||' is null or '||quote_ident(targetname)||' is  null)';
            end if;
        end if;
        -- my thoery is that the select Count(*) will never go thru here
        EXCEPTION WHEN OTHERS THEN
             RAISE NOTICE 'Got %', SQLERRM; -- issue 210,211
             RAISE NOTICE 'ERROR: Condition is not correct, please execute the following query to test your condition';
             RAISE NOTICE '%',sql;
             RETURN 'FAIL';
    END;

    BEGIN
         raise DEBUG 'initializing %',vertname;
         execute 'select * from _pgr_getTableName('||quote_literal(vertname)
                                                  || ',0,' || quote_literal(fnName) ||' )' into naming;
         emptied = false;
         set client_min_messages  to warning;
         IF sname=naming.sname AND vname=naming.tname  THEN
            if clean then
                execute 'TRUNCATE TABLE '||_pgr_quote_ident(vertname)||' RESTART IDENTITY';
                execute 'SELECT DROPGEOMETRYCOLUMN('||quote_literal(sname)||','||quote_literal(vname)||','||quote_literal('the_geom')||')';
                emptied = true;
            end if;
         ELSE -- table doesnt exist
            execute 'CREATE TABLE '||_pgr_quote_ident(vertname)||' (id bigserial PRIMARY KEY,cnt integer,chk integer,ein integer,eout integer)';
            emptied = true;
         END IF;
         IF (emptied) THEN
             execute 'select addGeometryColumn('||quote_literal(sname)||','||quote_literal(vname)||','||
	         quote_literal('the_geom')||','|| srid||', '||quote_literal('POINT')||', 2)';
             perform _pgr_createIndex(vertname , 'the_geom'::text , 'gist'::text);
         END IF;
         execute 'select * from  _pgr_checkVertTab('||quote_literal(vertname) ||', ''{"id"}''::text[])' into naming;
         execute 'set client_min_messages  to '|| debuglevel;
         raise DEBUG  '  ------>OK';
         EXCEPTION WHEN OTHERS THEN
             RAISE NOTICE 'Got %', SQLERRM; -- issue 210,211
             RAISE NOTICE 'ERROR: something went wrong when initializing the verties table';
             RETURN 'FAIL';
    END;



    raise notice 'Creating Topology, Please wait...';
        rowcount := 0;
        FOR points IN EXECUTE 'SELECT ' || idname || '::bigint AS id,'
            || ' _pgr_StartPoint(' || gname || ') AS source,'
            || ' _pgr_EndPoint('   || gname || ') AS target'
            || ' FROM '  || _pgr_quote_ident(tabname)
            || ' WHERE ' || gname || ' IS NOT NULL AND ' || idname||' IS NOT NULL '||rows_where
        LOOP

            rowcount := rowcount + 1;
            IF rowcount % 1000 = 0 THEN
                RAISE NOTICE '% edges processed', rowcount;
            END IF;


            source_id := _pgr_pointtoid3dIndrz(points.source, tolerance,vertname,srid);
            target_id := _pgr_pointtoid3dIndrz(points.target, tolerance,vertname,srid);
            BEGIN
                sql := 'UPDATE ' || _pgr_quote_ident(tabname) ||
                    ' SET '||sourcename||' = '|| source_id::text || ','||targetname||' = ' || target_id::text ||
                    ' WHERE ' || idname || ' =  ' || points.id::text;

                IF sql IS NULL THEN
                    RAISE NOTICE 'WARNING: UPDATE % SET source = %, target = % WHERE % = % ', tabname, source_id::text, target_id::text, idname,  points.id::text;
                ELSE
                    EXECUTE sql;
                END IF;
                EXCEPTION WHEN OTHERS THEN
                    RAISE NOTICE '%', SQLERRM;
                    RAISE NOTICE '%',sql;
                    RETURN 'FAIL';
            end;
        END LOOP;
        raise notice '-------------> TOPOLOGY CREATED FOR  % edges', rowcount;
        RAISE NOTICE 'Rows with NULL geometry or NULL id: %',notincluded;
        Raise notice 'Vertices table for table % is: %',_pgr_quote_ident(tabname), _pgr_quote_ident(vertname);
        raise notice '----------------------------------------------';

    RETURN 'OK';
 EXCEPTION WHEN OTHERS THEN
   RAISE NOTICE 'Unexpected error %', SQLERRM; -- issue 210,211
   RETURN 'FAIL';
END;


$BODY$
  LANGUAGE plpgsql VOLATILE STRICT
  COST 100;
ALTER FUNCTION public.pgr_createtopology3dIndrz(text, double precision, text, text, text, text, text, boolean)
  OWNER TO postgres;
COMMENT ON FUNCTION public.pgr_createtopology3dIndrz(text, double precision, text, text, text, text, text, boolean) IS 'args: edge_table,tolerance, the_geom:=''the_geom'',source:=''source'', target:=''target'',rows_where:=''true'' - fills columns source and target in the geometry table and creates a vertices table for selected rows';

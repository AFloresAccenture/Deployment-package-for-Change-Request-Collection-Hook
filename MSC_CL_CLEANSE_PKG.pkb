create or replace PACKAGE BODY        "MSC_CL_CLEANSE" AS -- body
/* $Header: MSCCLCAB.pls 120.0 2005/05/25 20:00:48 appldev noship $ */
/*
Package Name: MSC_CL_CLEANSE
Author's Name: Ronald Villavieja
Date written: 05-Dec-2014
RICEFW Object: LF19
Description: Package body for LF19 - Item cost.
Program Style:

Maintenance History:

Date			Issue#				Name					Remarks
-----------		------				-----------				------------------------------------------------
05-Dec-2014				 			Ronald Villavieja		Modified the MSCCLCAB.pls
25-Mar-2015		New Object Ext07	Randyl Pulma			Added code for Ext07-Update Collection Hook
25-Mar-2015							Randyl Pulma			Added v_step and v_mess for debugging purposes
21-May-2015							Albert Flores			Collection hook modifications
30-May-2015							Sanjay Sinha			Modified for the performance issue in UAT instance
31-Aug-2015							Albert Flores			Changes for the Global Netting

*/
--------------------------------------------------------------------------------------------


PROCEDURE CLEANSE( ERRBUF				OUT NOCOPY VARCHAR2,
	              RETCODE				OUT NOCOPY NUMBER,
                      pIID                              IN  NUMBER)
   IS
   f_num     	 NUMBER := 0;
   f_num_err 	 NUMBER := 0;
   f_num_nup 	 NUMBER := 0;
   f_dir     	 fnd_lookup_values.meaning%type;
   v_conc_req_id NUMBER;
   v_userid      NUMBER;
   v_gonogo      VARCHAR2(1) := 'N';
   v_prev_log    VARCHAR2(1000);
   v_step		 NUMBER;
   v_mess        VARCHAR2(500);
   dbLink        MSC_APPS_INSTANCES.M2A_DBLINK%TYPE; --5/20/2015 A.Flores
   query_str     VARCHAR2(3000); 					 --5/20/2015 A.Flores
   v_count		 NUMBER;
   c_ref_cur	 SYS_REFCURSOR;
   c_global_net	 SYS_REFCURSOR; 	--8/31/2015 A.Flores
   l_org_id		 NUMBER := NULL; 	--8/31/2015 A.Flores
   l_query_str	 VARCHAR2(4000);	--8/31/2015 A.Flores
   l_query_str2	 VARCHAR2(4000);	--8/31/2015 A.Flores
   --Start --5/20/2015 A.Flores
   -- Get DB Link from VCP to EBS
   CURSOR c_dbLink
   IS
   SELECT mai.M2A_DBLINK
     FROM msc_apps_instances mai
    WHERE mai.instance_code = 'EBS';
   --END --5/20/2015 A.Flores
   BEGIN
   ---RRV10102014: Removing ABC Class Processes as per Ankit's email.
   ---RRV10062014: Removed other hook customizations. Only one remaining is for Cost and ABC Classes.
   ---RRV10062014: Load Flat file data to staging tables (BEGIN)
   --- Cost and ABC Initialization and flat file Load
    v_conc_req_id := fnd_global.conc_request_id;
    v_userid      := fnd_global.user_id;
   ---RRV11052014: Added condition wherein Hook will only run for LF19 Item Cost
	-- added to check in the staging table instead of the request set
	v_step := 1;
	BEGIN
		Select 'Y'
		  into v_gonogo
		  from xxnbty_msc_costs_st
		 where status = 'N'
		   and rownum < 2;
	EXCEPTION
    WHEN OTHERS THEN
        FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'**** Error Encountered Validating Staging table xxnbty_msc_costs_st. '||SQLERRM);
        RETCODE:=G_WARNING;
	END;
	--
   v_step := 2;
   IF v_gonogo = 'Y' THEN ----- Should only process for ITEM COST and not for other processes
	BEGIN
    DECLARE
       v_inst msc_apps_instances.instance_code%type;
       v_cnt  number := 0;
    BEGIN
	   v_step := 3;
       FOR i_rec IN ( SELECT instance_code FROM msc_apps_instances
                       WHERE instance_id = pIID ) LOOP
          v_inst := i_rec.instance_code;
       END LOOP;
	   v_step := 4;
       FOR upd_cst_rec IN ( SELECT xcct.rowid, xcct.* FROM xxnbty_msc_costs_st xcct
                             WHERE xcct.status = 'N') LOOP
			v_step := 5;
		   UPDATE xxnbty_msc_costs_st
              SET organization_code = v_inst||':'||organization_code,
                  request_id = v_conc_req_id
           WHERE rowid = upd_cst_rec.rowid;
		   v_step := 6;
		   IF MOD(10000,500) = 0  THEN
              FND_CONCURRENT.AF_COMMIT;
           END IF;
       END LOOP;
       FND_CONCURRENT.AF_COMMIT;
    END;

	v_step := 7;
  /*
  -- Start Commented By Sanjay Sinha 5/30/2015
    DECLARE
	     v_found VARCHAR2(1) := 'N';
	  BEGIN
		v_step := 8;
	  ---RRV09102014: Processing COST (Begin)
	  ---RRV10102014: changing where clause to match against ORGANIZATION_CODE and ITEM_NAME
         FOR cost_rec IN ( SELECT cst.ROWID, cst.* FROM xxnbty_msc_costs_st cst where status = 'N' )
		 LOOP
			 v_step := 9;
		    FOR stgcost_rec IN (SELECT  mssi.ROWID, mssi.*
                               FROM msc.msc_st_system_items mssi
			                        WHERE mssi.organization_code   = cost_rec.organization_code
								                AND mssi.item_name           = cost_rec.item_name )
			LOOP
			 v_step := 10;
			     UPDATE msc.msc_st_system_items
				    SET standard_cost = cost_rec.standard_cost
				  WHERE rowid = stgcost_rec.rowid;
					v_found := 'Y';
					f_num := NVL(f_num,0) + 1;
		    END LOOP;
			 v_step := 11;  -- randyl
			 IF v_found = 'Y' THEN
			    UPDATE xxnbty_msc_costs_sted by
				   SET status = 'P'
				 WHERE rowid = cost_rec.rowid;
		     ELSIF v_found = 'N' THEN
			    UPDATE xxnbty_msc_costs_st
				   SET status = 'E',
				       error_description = 'Record not found in MSC_ST_SYSTEM_ITEMS.'
				WHERE rowid = cost_rec.rowid;
		     END IF;
			 v_found := 'N';
	     END LOOP;
		 v_found := 'N';
		 v_step := 12;  -- randyl
	  ---RRV09102014: Processing COST (END)
     EXCEPTION
      WHEN OTHERS THEN
        FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'**** Error encountered at Update Process. '||SQLERRM);
        --null;
     END;
   -- End Commented By Sanjay Sinha 5/30/2015
   */

   -- Start added by Sanjay Sinha 5/30/2015
	BEGIN
	FOR temp_rec IN ( SELECT item_name ,organization_Code FROM msc.msc_st_system_items  )
	LOOP
	  UPDATE xxnbty_msc_costs_st
	  SET status= 'P'
	  WHERE item_name = temp_Rec.item_name
	  AND organization_Code = temp_rec.organization_Code ;
	  FND_CONCURRENT.AF_COMMIT;
	END LOOP;

	UPDATE /*+ NOPARALLEL */ msc.msc_st_system_items a
	SET standard_cost = ( SELECT standard_cost
						  FROM xxnbty_msc_costs_st cst
						  WHERE status = 'P'
						  AND  cst.item_name  = a.item_name
						  AND cst.organization_Code = a.organization_code ) ;

	UPDATE xxnbty_msc_costs_st
	SET status = 'E'
	 ,  error_description = 'Record not found in MSC_ST_SYSTEM_ITEMS'
	WHERE status != 'P';

	END;

   -- End of addition Sanjay Sinha 5/30/2015

	 v_step := 13;
   ---RRV09022014:Commit changes.
       FND_CONCURRENT.AF_COMMIT;

   ---RRV10072014: Log error messages
    FND_FILE.PUT_LINE(FND_FILE.OUTPUT, '=== '||RPAD('COST ',300,'='));
    FND_FILE.PUT_LINE(FND_FILE.OUTPUT, RPAD('ORGANIZATION CODE', 30, ' ')||' '||RPAD('SR INSTANCE ID', 30, ' ')||' '||RPAD('ITEM NAME',30, ' ')||' '||RPAD('STANDARD COST',20, ' ')||' '||RPAD('CREATION DATE',20, ' ')||' '||RPAD('SOURCE',15,' ')||' '||RPAD('STATUS', 10, ' ')||' '||RPAD('ERROR DESCRIPTION',200, ' '));

	v_step := 14;
	FOR cost_err_rec IN ( SELECT  RPAD(organization_code,30,' ') AS sr_org_id
								, RPAD(' ',30,' ') as sr_inst_id
								, RPAD(item_name,30, ' ') AS sr_inv_itm_id
								, RPAD(standard_cost, 20, ' ') as std_cst
								, RPAD(creation_date,20,' ') as crt_dte
								, RPAD(source,15,' '), RPAD('COST', 15, ' ') AS cst
								, RPAD('ERROR', 10, ' ') AS stat
								, RPAD(error_description, 200, ' ') AS err_desc
                            FROM xxnbty_msc_costs_st
                           WHERE status = 'E' ) LOOP
        v_step := 15;
		FND_FILE.PUT_LINE(FND_FILE.OUTPUT, cost_err_rec.sr_org_id||' '||cost_err_rec.sr_inst_id||' '||cost_err_rec.sr_inv_itm_id||' '||cost_err_rec.std_cst||' '||cost_err_rec.crt_dte||' '||cost_err_rec.cst||' '||cost_err_rec.stat||' '||cost_err_rec.err_desc);
		f_num_err := NVL(f_num_err,0) + 1;
    END LOOP;

	v_step := 16;
		FND_FILE.PUT_LINE(FND_FILE.OUTPUT, '=== '||RPAD('Total Cost Records With Errors : '||f_num_err||' ',300, '==='));
		FND_FILE.PUT_LINE(FND_FILE.OUTPUT, ' ');
		FND_FILE.PUT_LINE(FND_FILE.OUTPUT, '=== '||RPAD('Total Cost Records Successfully Updated : '||f_num||' ',300, '==='));

  ---RRV10262014 Log Data Pull data that were not updated
	  FND_FILE.PUT_LINE(FND_FILE.OUTPUT, ' ');
	  FND_FILE.PUT_LINE(FND_FILE.OUTPUT, '=== '||RPAD('ST SYSTEM ITEMS NOT UPDATED ',300,'='));

    v_step := 17;

    /*
 -- Comment  this as i do not know what is the Purpose of this code and this is cartesion prodcut .-- Sanjay Sinha 5/30/2015
  FOR not_updated IN (SELECT ( RPAD(abl.ORGANIZATION_CODE, 30, ' ')||' '||RPAD(abl.SR_INSTANCE_ID, 30, ' ')||' '||RPAD(abl.ITEM_NAME, 30, ' ')||RPAD(abl.STANDARD_COST, 20, ' ')||RPAD('Record Not in Flat File', 200,' ') ) as err_log
                        FROM msc_st_system_items abl,
                             xxnbty_msc_costs_st bkr
                       WHERE abl.organization_code = bkr.organization_code
                         AND abl.item_name <> bkr.item_name
                         AND bkr.status = 'P' ) LOOP
	v_step := 18;
     IF v_prev_log <> not_updated.err_log OR v_prev_log IS NULL THEN
--        FND_FILE.PUT_LINE(FND_FILE.OUTPUT,not_updated.err_log);
        f_num_nup := f_num_nup + 1;
     END IF;
     v_prev_log := not_updated.err_log;
  END LOOP;
  v_step := 19;
		FND_FILE.PUT_LINE(FND_FILE.OUTPUT, '=== '||RPAD('Total ST System Items Not Updated : '||f_num_nup||' ',300, '==='));
  -- End of comment  5/30/2015
*/

  RETCODE:= G_SUCCESS;
  EXCEPTION
    WHEN OTHERS THEN
        FND_FILE.PUT_LINE(FND_FILE.OUTPUT,'**** Error encountered at File Read procedure. '||SQLERRM);
        RETCODE:=G_WARNING;
  END;
  v_step := 20;
  ELSE
    RETCODE := G_SUCCESS;
  END IF;

  -- 3/25/2015 rpulma Ext07 = To update the items to Not Planned (code 6) not for MRP planning (code 3) and MPP planning (code 9).
  v_step := 21;
  BEGIN
    Update msc_st_system_items
	Set mrp_planning_code = 6
	Where mrp_planning_code not in (3,9);
	RETCODE := G_SUCCESS;
  END;
  v_step := 22;
  --START -- 5/20/2015 A.Flores

  BEGIN
  v_step := 23;
    -- Get DB Link from VCP to EBS
   OPEN c_dbLink;
   FETCH c_dbLink INTO dbLink;
   CLOSE c_dbLink;
  v_step := 24;
   --Dynamic Query to delete records from msc_st_supplies
/*   query_str :=  ' SELECT count(*) FROM msc_st_supplies '
			 || ' WHERE order_type = 2 '
			 || ' AND order_number IN ( SELECT segment1 '
								   || ' FROM po_requisition_headers_all@' || dbLink || ' '
								   || ' WHERE NVL(interface_source_code, ''MSC'' ) <> ''MSC'' )';
   OPEN c_ref_cur FOR query_str;
   FETCH c_ref_cur INTO v_count;
   CLOSE c_ref_cur;
   FND_FILE.PUT_LINE(FND_FILE.LOG, 'Dynamic query for query_str_count : [ ' || query_str || ' ]');
   FND_FILE.PUT_LINE(FND_FILE.LOG, 'Number of selected records to be deleted : [ ' || v_count || ' ]'); */
   v_step := 25;

   query_str :=  ' DELETE FROM msc_st_supplies '
			 || ' WHERE order_type = 2 '
			 || ' AND order_number IN ( SELECT segment1 '
								   || ' FROM po_requisition_headers_all@' || dbLink || ' '
								   || ' WHERE NVL(interface_source_code, ''MSC'' ) <> ''MSC'' )';

   FND_FILE.PUT_LINE(FND_FILE.LOG, 'Dynamic query for query_str : [ ' || query_str || ' ]');
   v_step := 26;
   EXECUTE IMMEDIATE query_str;
    
   --START Changes for Global Netting 8/31/2015 Albert Flores
   v_step := 27;
	BEGIN
	DECLARE
	TYPE net_type IS RECORD ( inventory_item_id 		NUMBER
								,item_name				VARCHAR2(500)
								 );
	TYPE net_tab_type IS TABLE OF net_type;

	c_global_net	 SYS_REFCURSOR; 	
	c_global_net2	 SYS_REFCURSOR; 	
	l_org_id		 NUMBER := NULL; 	
	l_query_str	 	 VARCHAR2(4000);	
	l_query_str2	 VARCHAR2(4000);	
	l_netting_rec	 net_tab_type;
	--END 8/31/2015 A.Flores

		BEGIN
	v_step := 28;
			l_query_str :=  ' SELECT organization_id '
						  ||' FROM mtl_parameters@'|| dbLink ||' '
						  ||' WHERE organization_code = ''022'' ';
			
			OPEN  c_global_net FOR l_query_str;
			FETCH c_global_net INTO l_org_id;
			CLOSE c_global_net;
	v_step := 29;
			IF l_org_id IS NOT NULL THEN
			
				l_query_str2 :=  ' SELECT DISTINCT msi.inventory_item_id, msi.segment1 '
							   ||' FROM mtl_system_items@'|| dbLink || ' msi '
							   ||' ,mtl_item_catalog_groups@'|| dbLink || ' micg '
							   ||' WHERE msi.inventory_item_id in (SELECT DISTINCT inventory_item_id 
																   FROM   msc_st_supplies mss
																   WHERE  mss.order_type IN (1,2)) '
							   ||' AND msi.organization_id 		  = '|| l_org_id ||' '
							   ||' AND micg.item_catalog_group_id = msi.item_catalog_group_id '
							   ||' AND UPPER(micg.segment1) 	  = ''BULK'' '
							   ||' AND msi.mrp_planning_code IN (3,9) ' ;
	v_step := 30;			
				OPEN c_global_net2 FOR l_query_str2;
				FETCH c_global_net2 BULK COLLECT INTO l_netting_rec;
				FOR i IN 1..l_netting_rec.COUNT
				LOOP
	v_step := 31;			
					UPDATE msc_st_supplies
					SET    organization_id 		= l_org_id
					WHERE  inventory_item_id	= l_netting_rec(i).inventory_item_id
					AND	   order_type IN ( 1,2 )
					AND    organization_id <> l_org_id;
	v_step := 32;				
					FND_FILE.PUT_LINE(FND_FILE.LOG, 'Successfully updated ITEM : '|| l_netting_rec(i).item_name || ' to Organization ID : ' || l_org_id|| ' ');
				
				END LOOP;
			END IF;	
		END;

	END;
	
	--END Changes for Global Netting 8/31/2015 Albert Flores
	v_step := 33;
   COMMIT;
  END;
  --END -- 5/20/2015 A.Flores

  EXCEPTION
	WHEN OTHERS THEN
	  v_mess := 'At step ['||v_step||'] SQLCODE [' ||SQLCODE|| '] - ' ||substr(SQLERRM,1,100);
	  errbuf  := v_mess;
	  retcode := 2;

  END ;

   --This package will be called from the release code. Any data cleansing
   --can be performed while releasing the data to the source.
   --P_ENTITY          - Added for future use.
   --P_SR_INSTANCE_ID  - Instance Identifier
   --P_PO_BATCH_NUMBER - Identifier to process the relevant data.
PROCEDURE CLEANSE_RELEASE(  ERRBUF            OUT NOCOPY VARCHAR2,
                               RETCODE           OUT NOCOPY NUMBER,
                               P_ENTITY          IN  VARCHAR2,
                               P_SR_INSTANCE_ID  IN  NUMBER,
                               P_PO_BATCH_NUMBER IN  NUMBER)
   IS
   BEGIN
       RETCODE := G_SUCCESS;
 END;

END MSC_CL_CLEANSE;

/

show errors;
  
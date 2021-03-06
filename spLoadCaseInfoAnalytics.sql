USE [MC1_DCM_P]
GO
/****** Object:  StoredProcedure [dbo].[spLoadCaseInfoAnalytics]    Script Date: 07/06/2017 13:37:12 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:		   graj
-- Create date:  04/12/2016
-- Description:	 This procedure selects cases in Investigation status and populates 																										 
--               case information, ci information, dx information required for predictive analysis.
-- =============================================
ALTER PROCEDURE [dbo].[spLoadCaseInfoAnalytics]

AS
      DECLARE @ErrorNumber INT
      DECLARE @ErrorSeverity INT
      DECLARE @ErrorState INT
      DECLARE @ErrorProcedure VARCHAR(200)
      DECLARE @ErrorLine INT
      DECLARE @ErrorMessage VARCHAR(255)
      DECLARE @CodeBlock VARCHAR(255)
      
      DECLARE @log_proc_name VARCHAR(255)   = OBJECT_NAME(@@PROCID)
      DECLARE @log_db VARCHAR(255)   = DB_NAME()
      DECLARE @log_server VARCHAR(255)   = @@SERVERNAME
      DECLARE @log_user VARCHAR(255)   = SYSTEM_USER
      DECLARE @iSecsElapsed INT            = 0
      DECLARE @dStime DATETIME       = GETUTCDATE()
      DECLARE @iSuccessInd INT = 0
      DECLARE @iRowCnt INT = 0
    
    --get cases in investigation status 
		 BEGIN Try

					IF OBJECT_ID('tempdb..#Temp') IS  NOT NULL
						 DROP TABLE #Temp

					SELECT cl_sk,tc_sk 
					INTO #Temp
					FROM tpl_cases WITH (NOLOCK)
					WHERE tc_create_e_sk = 1
					AND tc_status_cd_sk IN (2900)	--Investigation
					AND tc_sk NOT IN (SELECT tc_sk FROM dbo.case_info_analytics)

		 END TRY
		 
		 BEGIN CATCH
			 SELECT
					 @ErrorNumber    = ERROR_NUMBER()
				 , @ErrorSeverity  = ERROR_SEVERITY()
				 , @ErrorState     = ERROR_STATE()
				 , @ErrorProcedure = LEFT(ERROR_PROCEDURE(), 200)
				 , @ErrorLine      = ERROR_LINE()
				 , @ErrorMessage   = LEFT(ERROR_MESSAGE(), 255)
				 GOTO ErrorHandler

		 END CATCH

--update account segments to match the segments setup in Score_Model
	BEGIN TRY
		 IF OBJECT_ID('tempdb..#temp_case_info') IS  NOT NULL
				DROP TABLE #temp_case_info
        
		 SELECT
			 tc.tc_sk
			 ,tc.create_cycle_sk
			 ,tc.a_sk
			 ,CASE WHEN c.cd_code = 'MCARE' THEN 'MEDR' 
						 WHEN c.cd_code = 'MCAID' THEN 'MCD' 
						 WHEN c.cd_code = 'INS' THEN 'PPO' 
						 WHEN c.cd_code = 'UNK' THEN 'UNK'
						 WHEN c.cd_code = 'SELF' THEN 'ASO'
						 WHEN c.cd_code = 'HMO' THEN 'HMOC'
						 ELSE 'UNK'
				END	a_segment_3
			 ,tc.tc_benefit_amt
			 ,convert(date, tc.tc_create_date,102) as case_create_dt
			 ,(select convert(date,max(act_create_date),102) from [activities] where tc_sk = tc.tc_sk) last_act_date
			 ,tc.tc_status_cd_sk as case_status_cd
			 ,(select cd_desc from [codes] where cd_sk = tc.tc_status_cd_sk) as case_status_descr
			 ,tc.tc_closed_desc_cd_sk as case_clsd_desc_cd
			 ,(select cd_desc from [codes] where cd_sk = tc.tc_closed_desc_cd_sk) as case_closed_descr
			 ,(select min(convert(date, act_create_date,102)) from [activities] where tc_sk = tc.tc_sk and actc_sk in (2,3)) as min_pend_set_dt
			 ,(case when exists (select 'x' from [activities] where tc_sk = tc.tc_sk and actc_sk in (2,3)) then NULL
						 else (select min(convert(date, act_create_date,102)) from [activities] where tc_sk = tc.tc_sk and actc_sk in (5, 302003)) 
				 END) as min_cwoc_dt
			 ,1 as case_selected_flag
			 ,(case when exists (select 'x' from [activities] where tc_sk = tc.tc_sk and actc_sk in (2,3)) then 1 else 0 end) as case_success_flag
			 ,(case when not exists (select 'x' from [activities] where tc_sk = tc.tc_sk and actc_sk in (2,3)) and
											 exists (select 'x' from [tpl_cases] where tc_sk = tc.tc_sk and tc_status_cd_sk = 2905 and tc_closed_desc_cd_sk not in (1210011,3305,3350,3353,3351,3352)) 
					then 1 else 0 end) as case_fail_flag
			 , (SELECT COUNT(DISTINCT p_sk) FROM claimheaders WHERE tc_sk = tc.tc_sk) patient_count   
		 INTO #temp_case_info     
		 FROM [tpl_cases] tc	WITH (NOLOCK)
		 JOIN accounts a ON a.a_sk = tc.a_sk
		 JOIN codes c ON c.cd_sk = a.a_funding_cd_sk
		 JOIN #Temp temp ON temp.tc_sk = tc.tc_sk
										AND temp.cl_sk = tc.cl_sk	      							 
		 END TRY
	
	--get dx information grouped by class	 
		 BEGIN CATCH
			 SELECT
					 @ErrorNumber    = ERROR_NUMBER()
				 , @ErrorSeverity  = ERROR_SEVERITY()
				 , @ErrorState     = ERROR_STATE()
				 , @ErrorProcedure = LEFT(ERROR_PROCEDURE(), 200)
				 , @ErrorLine      = ERROR_LINE()
				 , @ErrorMessage   = LEFT(ERROR_MESSAGE(), 255)
				 GOTO ErrorHandler

		 END CATCH
		 
		 BEGIN TRY							 
							 
				 IF OBJECT_ID('tempdb..#temp_dx_info') IS  NOT NULL
						DROP TABLE #temp_dx_info				 
          

				 select
				 tc_sk,count(cdx_order_num) num_of_orders,max(dx_code) max_dx_code,max(dx_icd_version) max_icd_version,
				 sum(cdx_order_num_neg1) cdx_order_num_neg1,
				 sum(dx_class_651) dx_class_651,sum(dx_class_652) dx_class_652,sum(dx_class_653) dx_class_653,
				 sum(dxc_cat1_mva) dxc_cat1_mva,sum(dxc_cat2_ampu) dxc_cat2_ampu,sum(dxc_cat3_fall) dxc_cat3_fall,
				 sum(dxc_cat4_medmal) dxc_cat4_medmal,sum(dxc_cat5_assault) dxc_cat5_assault,sum(dxc_cat6_WC) dxc_cat6_WC,
				 sum(dxc_cat7_sports) dxc_cat7_sports,sum(dx_medmal_ind) dxmedmal_ind, sum(dx_sensitive_ind) dx_sensitive_ind,
				 sum(infect_para_dis_9) + sum(infect_para_dis_10) infect_para_dis,
				 sum(neoplasms_9) + sum(neoplasms_10) neoplasms,
				 sum(immune_9) + sum(immune_10) immune,
				 sum(blood_dis_9) + sum(blood_dis_10) blood_dis,
				 sum(mental_9) + sum(mental_10) mental,
				 sum(nervous_9) + sum(nervous_10) nervous,
				 sum(senses_organ_9) + sum(senses_organ_10) senses_organ,
				 sum(circulatory_9) + sum(circulatory_10) circulatory,
				 sum(respiratory_9) + sum(respiratory_10) respiratory,
				 sum(digestive_9) + sum(digestive_10) digestive,
				 sum(genitourinary_9) + sum(genitourinary_10) genitourinary,
				 sum(pregnancy_9) + sum(pregnancy_10) pregnancy,
				 sum(skin_9) + sum(skin_10) skin,
				 sum(musculo_9) + sum(musculo_10) musculo,
				 sum(congenital_9) + sum(congenital_10) congenital,
				 sum(perinatal_9) + sum(perinatal_10) perinatal,
				 sum(ill_defined_9) + sum(ill_defined_10) ill_defined,
				 sum(injury_9) + sum(injury_10) injury,
				 sum(external_9) + sum(external_10) external_cause,
				 max(icd_hypertension) as icd_hypertension,
				 max(icd_oth_heart) as icd_oth_heart,
				 max(icd_arthopathies) as icd_arthopathies,
				 max(icd_symptoms) as icd_symptoms,
				 max(icd_abnormal) as icd_abnormal,
				 max(icd_sprain_dislo) as icd_sprain_dislo,
				 max(icd_openwound_lowerbody) as icd_openwound_lowerbody,
				 max(icd_crush) as icd_crush,
				 max(icd_MVA) as icd_MVA,
				 max(icd_fall) as icd_fall,
				 max(icd_submerge_suff) as icd_submerge_suff,
				 max(icd_oth_accident) as icd_oth_accident,
				 max(icd_supplemetary) as icd_supplemetary
				 INTO #temp_dx_info
				 from (
				 SELECT 
							ch.tc_sk
						 ,ch.ch_sk
						 ,ch.ch_clmno
						 ,cdx.cdx_order_num
						 ,dx.dx_code
						 ,dx.dx_icd_version
						 ,dx.dx_long_desc
						 ,case when cdx.cdx_order_num = -1 then 1 else 0 end cdx_order_num_neg1
						 ,case when dxcc.dx_class_cd_sk = 651 then 1 else 0 end dx_class_651
						 ,case when dxcc.dx_class_cd_sk = 652 then 1 else 0 end dx_class_652
						 ,case when dxcc.dx_class_cd_sk = 653 then 1 else 0 end dx_class_653
						 ,convert(int,dxcc.dxc_category1) dxc_cat1_mva
						 ,convert(int,dxcc.dxc_category2) dxc_cat2_ampu
						 ,convert(int,dxcc.dxc_category3) dxc_cat3_fall
						 ,convert(int,dxcc.dxc_category4) dxc_cat4_medmal
						 ,convert(int,dxcc.dxc_category5) dxc_cat5_assault
						 ,convert(int,dxcc.dxc_category6) dxc_cat6_WC
						 ,convert(int,dxcc.dxc_category7) dxc_cat7_sports
						 ,dxcc.dx_sensitive_ind,dxcc.dx_medmal_ind
						 ,case when isnumeric(substring(dx_code,1,3)) = 0 or dx_icd_version = 10 then 0 when convert(int,(SUBSTRING(dx_code,1,3))) between 1 and 139 then 1 else 0 end infect_para_dis_9
						 ,case when isnumeric(substring(dx_code,1,3)) = 0 or dx_icd_version = 10 then 0 when convert(int,(SUBSTRING(dx_code,1,3))) between 140 and 239 then 1 else 0 end neoplasms_9
						 ,case when isnumeric(substring(dx_code,1,3)) = 0 or dx_icd_version = 10 then 0 when convert(int,(SUBSTRING(dx_code,1,3))) between 240 and 279 then 1 else 0 end immune_9
						 ,case when isnumeric(substring(dx_code,1,3)) = 0 or dx_icd_version = 10 then 0 when convert(int,(SUBSTRING(dx_code,1,3))) between 280 and 289 then 1 else 0 end blood_dis_9
						 ,case when isnumeric(substring(dx_code,1,3)) = 0 or dx_icd_version = 10 then 0 when convert(int,(SUBSTRING(dx_code,1,3))) between 290 and 319 then 1 else 0 end mental_9
						 ,case when isnumeric(substring(dx_code,1,3)) = 0 or dx_icd_version = 10 then 0 when convert(int,(SUBSTRING(dx_code,1,3))) between 320 and 359 then 1 else 0 end nervous_9
						 ,case when isnumeric(substring(dx_code,1,3)) = 0 or dx_icd_version = 10 then 0 when convert(int,(SUBSTRING(dx_code,1,3))) between 360 and 389 then 1 else 0 end senses_organ_9
						 ,case when isnumeric(substring(dx_code,1,3)) = 0 or dx_icd_version = 10 then 0 when convert(int,(SUBSTRING(dx_code,1,3))) between 390 and 459 then 1 else 0 end circulatory_9
						 ,case when isnumeric(substring(dx_code,1,3)) = 0 or dx_icd_version = 10 then 0 when convert(int,(SUBSTRING(dx_code,1,3))) between 460 and 519 then 1 else 0 end respiratory_9
						 ,case when isnumeric(substring(dx_code,1,3)) = 0 or dx_icd_version = 10 then 0 when convert(int,(SUBSTRING(dx_code,1,3))) between 520 and 579 then 1 else 0 end digestive_9
						 ,case when isnumeric(substring(dx_code,1,3)) = 0 or dx_icd_version = 10 then 0 when convert(int,(SUBSTRING(dx_code,1,3))) between 580 and 629 then 1 else 0 end genitourinary_9
						 ,case when isnumeric(substring(dx_code,1,3)) = 0 or dx_icd_version = 10 then 0 when convert(int,(SUBSTRING(dx_code,1,3))) between 630 and 679 then 1 else 0 end pregnancy_9
						 ,case when isnumeric(substring(dx_code,1,3)) = 0 or dx_icd_version = 10 then 0 when convert(int,(SUBSTRING(dx_code,1,3))) between 680 and 709 then 1 else 0 end skin_9
						 ,case when isnumeric(substring(dx_code,1,3)) = 0 or dx_icd_version = 10 then 0 when convert(int,(SUBSTRING(dx_code,1,3))) between 710 and 739 then 1 else 0 end musculo_9
						 ,case when isnumeric(substring(dx_code,1,3)) = 0 or dx_icd_version = 10 then 0 when convert(int,(SUBSTRING(dx_code,1,3))) between 740 and 759 then 1 else 0 end congenital_9
						 ,case when isnumeric(substring(dx_code,1,3)) = 0 or dx_icd_version = 10 then 0 when convert(int,(SUBSTRING(dx_code,1,3))) between 760 and 779 then 1 else 0 end perinatal_9
						 ,case when isnumeric(substring(dx_code,1,3)) = 0 or dx_icd_version = 10 then 0 when convert(int,(SUBSTRING(dx_code,1,3))) between 780 and 799 then 1 else 0 end ill_defined_9
						 ,case when isnumeric(substring(dx_code,1,3)) = 0 or dx_icd_version = 10 then 0 when convert(int,(SUBSTRING(dx_code,1,3))) between 800 and 999 then 1 else 0 end injury_9
						 ,case when substring(dx_code,1,1) in ('E','V') and dx_icd_version = 9 then 1 else 0 end external_9
						 ,case when dx_icd_version = 9 then 0 when (SUBSTRING(dx_code,1,1) = 'A' and convert(int,SUBSTRING(dx_code,2,2)) between 0 and 99) or (SUBSTRING(dx_code,1,1) = 'B' and convert(int,SUBSTRING(dx_code,2,2)) between 0 and 99) then 1 else 0 end infect_para_dis_10
						 ,case when dx_icd_version = 9 then 0 when (SUBSTRING(dx_code,1,1) = 'C' and convert(int,SUBSTRING(dx_code,2,1)) between 0 and 9) or (SUBSTRING(dx_code,1,1) = 'D' and convert(int,SUBSTRING(dx_code,2,1)) between 0 and 4) then 1 else 0 end neoplasms_10
						 ,case when dx_icd_version = 9 then 0 when (SUBSTRING(dx_code,1,1) = 'D' and convert(int,SUBSTRING(dx_code,2,1)) between 5 and 9) then 1 else 0 end blood_dis_10
						 ,case when dx_icd_version = 9 then 0 when (SUBSTRING(dx_code,1,1) = 'E' and convert(int,SUBSTRING(dx_code,2,2)) between 0 and 90) then 1 else 0 end immune_10
						 ,case when dx_icd_version = 9 then 0 when (SUBSTRING(dx_code,1,1) = 'F' and convert(int,SUBSTRING(dx_code,2,2)) between 0 and 99) then 1 else 0 end mental_10
						 ,case when dx_icd_version = 9 then 0 when (SUBSTRING(dx_code,1,1) = 'G' and convert(int,SUBSTRING(dx_code,2,2)) between 0 and 99) then 1 else 0 end nervous_10
						 ,case when dx_icd_version = 9 then 0 when (SUBSTRING(dx_code,1,1) = 'H' and convert(int,SUBSTRING(dx_code,2,2)) between 0 and 95) then 1 else 0 end senses_organ_10
						 ,case when dx_icd_version = 9 then 0 when (SUBSTRING(dx_code,1,1) = 'I' and convert(int,SUBSTRING(dx_code,2,2)) between 0 and 99) then 1 else 0 end circulatory_10
						 ,case when dx_icd_version = 9 then 0 when (SUBSTRING(dx_code,1,1) = 'J' and convert(int,SUBSTRING(dx_code,2,2)) between 0 and 99) then 1 else 0 end respiratory_10
						 ,case when dx_icd_version = 9 then 0 when (SUBSTRING(dx_code,1,1) = 'K' and convert(int,SUBSTRING(dx_code,2,2)) between 0 and 93) then 1 else 0 end digestive_10
						 ,case when dx_icd_version = 9 then 0 when (SUBSTRING(dx_code,1,1) = 'L' and convert(int,SUBSTRING(dx_code,2,2)) between 0 and 99) then 1 else 0 end skin_10
						 ,case when dx_icd_version = 9 then 0 when (SUBSTRING(dx_code,1,1) = 'M') then 1 else 0 end musculo_10
						 ,case when dx_icd_version = 9 then 0 when (SUBSTRING(dx_code,1,1) = 'N' and convert(int,SUBSTRING(dx_code,2,2)) between 0 and 99) then 1 else 0 end genitourinary_10
						 ,case when dx_icd_version = 9 then 0 when (SUBSTRING(dx_code,1,1) = 'O' and convert(int,SUBSTRING(dx_code,2,1)) between 0 and 9) then 1 else 0 end pregnancy_10
						 ,case when dx_icd_version = 9 then 0 when (SUBSTRING(dx_code,1,1) = 'P' and convert(int,SUBSTRING(dx_code,2,2)) between 0 and 99) then 1 else 0 end perinatal_10
						 ,case when dx_icd_version = 9 then 0 when (SUBSTRING(dx_code,1,1) = 'Q' and convert(int,SUBSTRING(dx_code,2,2)) between 0 and 99) then 1 else 0 end congenital_10
						 ,case when dx_icd_version = 9 then 0 when (SUBSTRING(dx_code,1,1) = 'R' and convert(int,SUBSTRING(dx_code,2,2)) between 0 and 99) then 1 else 0 end ill_defined_10
						 ,case when dx_icd_version = 9 then 0 when (SUBSTRING(dx_code,1,1) in ('S','T') and convert(int,SUBSTRING(dx_code,2,2)) between 0 and 99) then 1 else 0 end injury_10
						 ,case when dx_icd_version = 9 then 0 when (SUBSTRING(dx_code,1,1) in ('V','X','Y') and convert(int,SUBSTRING(dx_code,2,2)) between 0 and 99) then 1 else 0 end external_10
						 ,case when (dx_icd_version = 9 and SUBSTRING(dx_code,1,2) = '40') or (dx_icd_version = 10 and SUBSTRING(dx_code,1,3) in ('I10','I11','I12','I13','I14','I15')) then 'Y' else 'N' end icd_hypertension
						 ,case when (dx_icd_version = 9 and SUBSTRING(dx_code,1,2) = '42') or (dx_icd_version = 10 and SUBSTRING(dx_code,1,3) in ('I30','I31','I32','I33','I34','I35','I36','I37','I38','I39','I40','I41','I42','I43','I44','I45','I46','I47','I48','I49','I50','I51','I52')) then 'Y' else 'N' end icd_oth_heart
						 ,case when (dx_icd_version = 9 and SUBSTRING(dx_code,1,2) = '71') or (dx_icd_version = 10 and SUBSTRING(dx_code,1,3) in ('M00','M01','M02','M03','M04','M05','M06','M07','M08','M09','M10','M11','M12','M13','M14','M15','M16','M17','M18','M19','M20','M21','M22','M23','M24','M25')) then 'Y' else 'N' end icd_arthopathies
						 ,case when (dx_icd_version = 9 and SUBSTRING(dx_code,1,2) = '78') or (dx_icd_version = 10 and SUBSTRING(dx_code,1,2) in ('R0','R1','R2','R3','R4','R5','R6')) then 'Y' else 'N' end icd_symptoms
						 ,case when (dx_icd_version = 9 and SUBSTRING(dx_code,1,2) = '79') or (dx_icd_version = 10 and SUBSTRING(dx_code,1,3) in ('R71','R72','R73','R74','R75','R76','R77','R78','R79','R80','R81','R82','R83','R84','R85','R86','R87','R88','R89','R90','R91','R92','R93','R94','R95')) then 'Y' else 'N' end icd_abnormal
						 ,case when (dx_icd_version = 9 and SUBSTRING(dx_code,1,2) in ('83','84')) or (dx_icd_version = 10 and SUBSTRING(dx_code,1,3) in ('S03','S13','S23','S33','S43','S53','S63','S73','S83','S93','T03')) then 'Y' else 'N' end icd_sprain_dislo
						 ,case when (dx_icd_version = 9 and SUBSTRING(dx_code,1,2) = '89') or (dx_icd_version = 10 and SUBSTRING(dx_code,1,3) in ('S71','S81','S91')) then 'Y' else 'N' end icd_openwound_lowerbody
						 ,case when (dx_icd_version = 9 and SUBSTRING(dx_code,1,2) = '92') or (dx_icd_version = 10 and SUBSTRING(dx_code,1,3) in ('S07','S17','S27','S37','S47','S57','S67','S77','S87','S97','T04')) then 'Y' else 'N' end icd_crush
						 ,case when (dx_icd_version = 9 and SUBSTRING(dx_code,1,2) in ('E81','E82')) or (dx_icd_version = 10 and SUBSTRING(dx_code,1,1) in ('V') and convert(int,SUBSTRING(dx_code,2,2)) between 1 and 9) then 'Y' else 'N' end icd_MVA
						 ,case when (dx_icd_version = 9 and SUBSTRING(dx_code,1,2) in ('E88')) or (dx_icd_version = 10 and SUBSTRING(dx_code,1,1) in ('W') and convert(int,SUBSTRING(dx_code,2,2)) between 0 and 19) then 'Y' else 'N' end icd_fall
						 ,case when (dx_icd_version = 9 and SUBSTRING(dx_code,1,2) in ('E91')) or (dx_icd_version = 10 and SUBSTRING(dx_code,1,1) in ('W') and convert(int,SUBSTRING(dx_code,2,2)) between 65 and 65) then 'Y' else 'N' end icd_submerge_suff
						 ,case when (dx_icd_version = 9 and SUBSTRING(dx_code,1,2) in ('E92')) or (dx_icd_version = 10 and SUBSTRING(dx_code,1,1) in ('W') and convert(int,SUBSTRING(dx_code,2,2)) between 20 and 20) then 'Y' else 'N' end icd_oth_accident
						 ,case when (dx_icd_version = 9 and SUBSTRING(dx_code,1,1) in ('V')) or (dx_icd_version = 10 and SUBSTRING(dx_code,1,1) in ('Z')) then 'Y' else 'N' end icd_supplemetary	 
					 from tpl_cases tc
					 JOIN [claimheaders] ch ON ch.tc_sk = tc.tc_sk
					 INNER JOIN [claimheader_dx_codes] cdx on ch.ch_sk = cdx.ch_sk
					 INNER JOIN [dx_codes_client] dxcc on cdx.dxc_sk = dxcc.dxc_sk
					 INNER JOIN [dx_codes] dx on dxcc.dx_sk = dx.dx_sk
					 INNER JOIN #Temp temp ON temp.tc_sk = tc.tc_sk AND temp.cl_sk = tc.cl_sk
					 where ch.ch_logical_delete_ind = 0) as x 
					 group by tc_sk

       END TRY
       
        BEGIN CATCH
			 SELECT
					 @ErrorNumber    = ERROR_NUMBER()
				 , @ErrorSeverity  = ERROR_SEVERITY()
				 , @ErrorState     = ERROR_STATE()
				 , @ErrorProcedure = LEFT(ERROR_PROCEDURE(), 200)
				 , @ErrorLine      = ERROR_LINE()
				 , @ErrorMessage   = LEFT(ERROR_MESSAGE(), 255)
				 GOTO ErrorHandler

		 END CATCH

--select number of claims for patient
  BEGIN TRY
				 IF OBJECT_ID('tempdb..#temp_claim_count') IS  NOT NULL
						DROP TABLE #temp_claim_count		  
           
					 SELECT 
						 cl.tc_sk,cl.p_sk,
																count(*) claim_count
																INTO #temp_claim_count
																FROM #Temp temp
																JOIN [claimheaders] cl ON cl.tc_sk = temp.tc_sk AND cl.cl_sk = temp.cl_sk
																where cl.ch_logical_delete_ind = 0
																group by cl.tc_sk,p_sk
																having count(*) = (select max(claim_count) 
																									 FROM (SELECT 
																														cl2.tc_sk,cl2.p_sk,
																														count(*) claim_count
																														FROM #Temp temp
																														JOIN [claimheaders] cl2 ON cl2.tc_sk = temp.tc_sk
																														AND cl2.cl_sk = temp.cl_sk
																														AND ch_logical_delete_ind = 0
																														and cl2.tc_sk = cl.tc_sk
																														group by cl2.tc_sk,cl2.p_sk) 
																												x)
    END TRY
     BEGIN CATCH
			 SELECT
					 @ErrorNumber    = ERROR_NUMBER()
				 , @ErrorSeverity  = ERROR_SEVERITY()
				 , @ErrorState     = ERROR_STATE()
				 , @ErrorProcedure = LEFT(ERROR_PROCEDURE(), 200)
				 , @ErrorLine      = ERROR_LINE()
				 , @ErrorMessage   = LEFT(ERROR_MESSAGE(), 255)
				 GOTO ErrorHandler

		 END CATCH	
	
	--get claims, patient and coveredindividual relationship	 
		 BEGIN TRY																											
																							 
			 IF OBJECT_ID('tempdb..#temp_ci_info') IS  NOT NULL
				DROP TABLE #temp_ci_info																					 

						SELECT distinct
 							 p.p_sk,p.tc_sk,ci.ci_sk,
 							 CASE WHEN CHARINDEX('-',ci_zip) > 1 THEN LEFT(ci_zip,CHARINDEX('-',ci_zip)-1)	ELSE ci_zip	END ci_zip,
 							 ci_dob_date,
							 case when ci_dod_date is null then 0 else 1 end 	death_ind,
							 co1.cd_code ci_relation_sub_cd, co1.cd_desc 	ci_relation_sub_desc,
							 co2.cd_code ci_sex_cd,co2.cd_desc ci_sex_desc,
							 co3.cd_code ci_state_cd,co3.cd_desc ci_state_desc,
							 (select count(*) from [claimheaders] 	cl where cl.p_sk = p.p_sk) count_of_claims_pp
						INTO #temp_ci_info   
						FROM #Temp temp
						JOIN claimheaders ch WITH (NOLOCK) ON ch.tc_sk = temp.tc_sk	 AND ch.cl_sk = temp.cl_sk
						JOIN  [patients] p WITH (NOLOCK) ON p.p_sk = ch.p_sk
						JOIN [covered_individuals] ci WITH (NOLOCK) ON ci.ci_sk = p.ci_sk  	
						JOIN [codes] co1 WITH (NOLOCK) ON co1.cd_sk = ci.ci_relation_sub_cd_sk
						JOIN [codes] co2 WITH (NOLOCK) ON co2.cd_sk = ci.ci_sex_cd_sk
						JOIN [codes] co3 WITH (NOLOCK) ON co3.cd_sk = ci.ci_state_cd_sk
						
			END TRY
			 BEGIN CATCH
			 SELECT
					 @ErrorNumber    = ERROR_NUMBER()
				 , @ErrorSeverity  = ERROR_SEVERITY()
				 , @ErrorState     = ERROR_STATE()
				 , @ErrorProcedure = LEFT(ERROR_PROCEDURE(), 200)
				 , @ErrorLine      = ERROR_LINE()
				 , @ErrorMessage   = LEFT(ERROR_MESSAGE(), 255)
				 GOTO ErrorHandler

		 END CATCH	
		
		--populate tmp_case_info analytics table 
		 BEGIN TRY		
     			 
					 INSERT INTO dbo.case_info_analytics
							SELECT 
							cl_sk							 = temp.cl_sk,
							tc_sk							 = temp.tc_sk,
							cycle_sk            = tci.create_cycle_sk,
							a_sk							   = tci.a_sk,
							a_segment_3				 = tci.a_segment_3,
							tc_benefit_amt		   = ISNULL(tci.tc_benefit_amt,'0.00'),
							case_create_dt		   = CONVERT(DATE,tci.case_create_dt,102),
							last_act_date			 = CONVERT(DATE,tci.last_act_date,102),
							case_status_cd		   = tci.case_status_cd,
							case_status_descr	 = tci.case_status_descr,
							case_clsd_desc_cd	 = tci.case_clsd_desc_cd,
							case_closed_descr	 = tci.case_closed_descr,
							min_pend_set_dt		 = CONVERT(DATE,tci.min_pend_set_dt,102),
							min_cwoc_dt				 = CONVERT(DATE,tci.min_cwoc_dt,102),
							case_selected_flag  = tci.case_selected_flag,
							case_success_flag	 = tci.case_success_flag,
							case_fail_flag		   = tci.case_fail_flag,
							num_of_orders			 = NULL,
							max_icd_version		 = NULL,
							cdx_order_num_neg1  = NULL,
							dx_class_651			   = NULL,
							dx_class_652			   = NULL,
							dx_class_653			   = NULL,
							dxc_cat1_mva			   = NULL,
							dxc_cat2_ampu			 = NULL,
							dxc_cat3_fall			 = NULL,
							dxc_cat4_medmal		 = NULL,
							dxc_cat5_assault	   = NULL,
							dxc_cat6_WC				 = NULL,
							dxc_cat7_sports		 = NULL,
							dxmedmal_ind			   = NULL,
							dx_sensitive_ind	   = NULL,
							infect_para_dis		 = NULL,
							neoplasms					 = NULL,
							immune						   = NULL,
							blood_dis					 = NULL,
							mental						   = NULL,
							nervous						 = NULL,
							senses_organ			   = NULL,
							circulatory				 = NULL,
							respiratory				 = NULL,
							digestive					 = NULL,
							genitourinary			 = NULL,
							pregnancy					 = NULL,
							skin							   = NULL,
							musculo						 = NULL,
							congenital				   = NULL,
							perinatal					 = NULL,
							ill_defined				 = NULL,
							injury						   = NULL,
							external_cause		   = NULL,
							icd_hypertension	   = NULL,
							icd_oth_heart			 = NULL,
							icd_arthopathies	 = NULL,
							icd_symptoms			 = NULL,
							icd_abnormal			 = NULL,
							icd_sprain_dislo	 = NULL,
							icd_openwound_lowerbody = NULL,
							icd_crush					 = NULL,
							icd_MVA						 = NULL,
							icd_fall					 = NULL,
							icd_submerge_suff	 = NULL,
							icd_oth_accident	 = NULL,
							icd_supplemetary	 = NULL,
							patient_count     = tci.patient_count,
							p_sk							 = NULL,
							claim_count				 = NULL,
							ci_sk							 = NULL,
							ci_zip						 = NULL,
							ci_dob_date				 = NULL,
							death_ind					 = NULL,
							ci_relation_sub_cd = NULL,
							ci_relation_sub_desc = NULL,
							ci_sex_cd						= NULL,
							ci_sex_desc					= NULL,
							count_of_claims_pp	= NULL,
							raw_prediction			= NULL,
							success_score				= NULL,
							reason1_level1			= NULL,
							reason1_level2			= NULL,
							reason2_level1		  = NULL,
							reason2_level2			= NULL,
							reason3_level1		  = NULL,
							reason3_level2		  = NULL,
							Processed = 0,
							act_sk = NULL
							 FROM #temp temp
								 JOIN #temp_case_info tci  ON tci.tc_sk = temp.tc_sk
     	END TRY
     	
     	 BEGIN CATCH
			 SELECT
					 @ErrorNumber    = ERROR_NUMBER()
				 , @ErrorSeverity  = ERROR_SEVERITY()
				 , @ErrorState     = ERROR_STATE()
				 , @ErrorProcedure = LEFT(ERROR_PROCEDURE(), 200)
				 , @ErrorLine      = ERROR_LINE()
				 , @ErrorMessage   = LEFT(ERROR_MESSAGE(), 255)
				 GOTO ErrorHandler

		 END CATCH					
 
 --update tmp_case_info analytics table with dx information    					
		 BEGIN TRY
		 UPDATE tca
		 SET				 num_of_orders					= tdx.num_of_orders,
								max_icd_version					= tdx.max_icd_version,
								cdx_order_num_neg1			= tdx.cdx_order_num_neg1,
								dx_class_651						= tdx.dx_class_651,
								dx_class_652						= tdx.dx_class_652,
								dx_class_653						= tdx.dx_class_653,
								dxc_cat1_mva						= tdx.dxc_cat1_mva,
								dxc_cat2_ampu						= tdx.dxc_cat2_ampu,
								dxc_cat3_fall						= tdx.dxc_cat3_fall,
								dxc_cat4_medmal					= tdx.dxc_cat4_medmal,
								dxc_cat5_assault				= tdx.dxc_cat5_assault,
								dxc_cat6_WC							= tdx.dxc_cat6_WC,
								dxc_cat7_sports					= tdx.dxc_cat7_sports,
								dxmedmal_ind						= tdx.dxmedmal_ind,
								dx_sensitive_ind				= tdx.dx_sensitive_ind,
								infect_para_dis					= tdx.infect_para_dis,
								neoplasms								= tdx.neoplasms,
								immune									= tdx.immune,
								blood_dis								= tdx.blood_dis,
								mental									= tdx.mental,
								nervous									= tdx.nervous,
								senses_organ						= tdx.senses_organ,
								circulatory							= tdx.circulatory,
								respiratory							= tdx.respiratory,
								digestive								= tdx.digestive,
								genitourinary						= tdx.genitourinary,
								pregnancy								= tdx.pregnancy,
								skin										= tdx.skin,
								musculo									= tdx.musculo,
								congenital							= tdx.congenital,
								perinatal								= tdx.perinatal,
								ill_defined							= tdx.ill_defined,
								injury									= tdx.injury,
								external_cause					= tdx.external_cause,
								icd_hypertension				= tdx.icd_hypertension,
								icd_oth_heart						= tdx.icd_oth_heart,
								icd_arthopathies				= tdx.icd_arthopathies,
								icd_symptoms						= tdx.icd_symptoms,
								icd_abnormal						= tdx.icd_abnormal,
								icd_sprain_dislo				= tdx.icd_sprain_dislo,
								icd_openwound_lowerbody	= tdx.icd_openwound_lowerbody,
								icd_crush								= tdx.icd_crush,
								icd_MVA									= tdx.icd_MVA,
								icd_fall								= tdx.icd_fall,
								icd_submerge_suff				= tdx.icd_submerge_suff,
								icd_oth_accident				= tdx.icd_oth_accident,
								icd_supplemetary				= tdx.icd_supplemetary
			FROM dbo.case_info_analytics tca
				JOIN #temp_dx_info tdx ON tdx.tc_sk = tca.tc_sk

   END TRY
			 BEGIN CATCH
						 SELECT
								 @ErrorNumber    = ERROR_NUMBER()
							 , @ErrorSeverity  = ERROR_SEVERITY()
							 , @ErrorState     = ERROR_STATE()
							 , @ErrorProcedure = LEFT(ERROR_PROCEDURE(), 200)
							 , @ErrorLine      = ERROR_LINE()
							 , @ErrorMessage   = LEFT(ERROR_MESSAGE(), 255)
							 GOTO ErrorHandler

					 END CATCH
   
   --update relationship info in case_info_analytics table    
      BEGIN TRY  
						 UPDATE tca
						 SET  p_sk							     = tci.p_sk,
									claim_count						 = tcc.claim_count,
									ci_sk									 = tci.ci_sk,
									ci_zip								 = tci.ci_zip,
									ci_dob_date						 = tci.ci_dob_date,
									death_ind							 = tci.death_ind,
									ci_relation_sub_cd		 = tci.ci_relation_sub_cd,
									ci_relation_sub_desc	 = tci.ci_relation_sub_desc,
									ci_sex_cd							 = tci.ci_sex_cd,
									ci_sex_desc						 = tci.ci_sex_desc,
									count_of_claims_pp	   = tci.count_of_claims_pp,
									raw_prediction			   = NULL,
									success_score					 = NULL,
									reason1_level1			   = NULL,
									reason1_level2			   = NULL,
									reason2_level1		     = NULL,
									reason2_level2			   = NULL,
									reason3_level1		     = NULL,
									reason3_level2		     = NULL 
							FROM dbo.case_info_analytics tca
								JOIN #temp_claim_count tcc ON tcc.tc_sk = tca.tc_sk 
								JOIN #temp_ci_info tci ON tci.tc_sk = tca.tc_sk
															 AND tci.p_sk = tcc.p_sk
     
     END TRY
      BEGIN CATCH
			 SELECT
					 @ErrorNumber    = ERROR_NUMBER()
				 , @ErrorSeverity  = ERROR_SEVERITY()
				 , @ErrorState     = ERROR_STATE()
				 , @ErrorProcedure = LEFT(ERROR_PROCEDURE(), 200)
				 , @ErrorLine      = ERROR_LINE()
				 , @ErrorMessage   = LEFT(ERROR_MESSAGE(), 255)
				 GOTO ErrorHandler

		 END CATCH                  

		 RETURN 0		

		 ErrorHandler:         
			 SET @ErrorMessage = LEFT(@log_proc_name + ':' + @ErrorMessage, 255)
			 RAISERROR (@ErrorMessage, 10, -1) WITH nowait
		RETURN 1
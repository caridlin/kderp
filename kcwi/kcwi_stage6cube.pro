;
; Copyright (c) 2013, California Institute of Technology. All rights
;	reserved.
;+
; NAME:
;	KCWI_STAGE6CUBE
;
; PURPOSE:
;	This procedure applies the geometry solution derived from
;	KCWI_STAGE3GEOM to the input files, to generate a cube for
;	dispersed data and an image for direct mode data.
;
; CATEGORY:
;	Data reduction for the Keck Cosmic Web Imager (KCWI).
;
; CALLING SEQUENCE:
;	KCWI_STAGE6CUBE, Procfname, Pparfname
;
; OPTIONAL INPUTS:
;	Procfname - input proc filename generated by KCWI_PREP
;			defaults to './redux/kcwi.proc'
;	Pparfname - input ppar filename generated by KCWI_STAGE2_PREP
;			defaults to './redux/kcwi.ppar'
;
; KEYWORDS:
;	VERBOSE	- set to verbosity level to override value in ppar file
;	DISPLAY - set to display level to override value in ppar file
;
; OUTPUTS:
;	None
;
; SIDE EFFECTS:
;	Outputs processed files in output directory specified by the
;	KCWI_PPAR struct read in from Pparfname.
;
; PROCEDURE:
;	Reads Pparfname to derive input/output directories and reads the
;	corresponding '*.proc' file in output directory to derive the list
;	of input files and their associated geometric calibration files.
;
; EXAMPLE:
;	Perform stage6cube reductions on the images in 'night1/redux' directory:
;
;	KCWI_STAGE6CUBE,'night1/redux/kcwi.ppar'
;
; MODIFICATION HISTORY:
;	Written by:	Don Neill (neill@caltech.edu)
;	2017-NOV-13	Initial version
;-
pro kcwi_stage6cube,procfname,ppfname,help=help,verbose=verbose, display=display
	;
	; setup
	pre = 'KCWI_STAGE6CUBE'
	startime=systime(1)
	q = ''	; for queries
	;
	; help request
	if keyword_set(help) then begin
		print,pre+': Info - Usage: '+pre+', Proc_filespec, Ppar_filespec'
		print,pre+': Info - default filespecs usually work (i.e., leave them off)'
		return
	endif
	;
	; get ppar struct
	ppar = kcwi_read_ppar(ppfname)
	;
	; verify ppar
	if kcwi_verify_ppar(ppar,/init) ne 0 then begin
		print,pre+': Error - pipeline parameter file not initialized: ',ppfname
		return
	endif
	;
	; directories
	if kcwi_verify_dirs(ppar,rawdir,reddir,cdir,ddir) ne 0 then begin
		kcwi_print_info,ppar,pre,'Directory error, returning',/error
		return
	endif
	;
	; check keyword overrides
	if n_elements(verbose) eq 1 then $
		ppar.verbose = verbose
	if n_elements(display) eq 1 then $
		ppar.display = display
	;
	; log file
	lgfil = reddir + 'kcwi_stage6cube.log'
	filestamp,lgfil,/arch
	openw,ll,lgfil,/get_lun
	ppar.loglun = ll
	printf,ll,'Log file for run of '+pre+' on '+systime(0)
	printf,ll,'DRP Ver: '+kcwi_drp_version()
	printf,ll,'Raw dir: '+rawdir
	printf,ll,'Reduced dir: '+reddir
	printf,ll,'Calib dir: '+cdir
	printf,ll,'Data dir: '+ddir
	printf,ll,'Filespec: '+ppar.filespec
	printf,ll,'Ppar file: '+ppfname
	if ppar.clobber then $
		printf,ll,'Clobbering existing images'
	printf,ll,'Verbosity level   : ',ppar.verbose
	printf,ll,'Plot display level: ',ppar.display
	;
	; read proc file
	kpars = kcwi_read_proc(ppar,procfname,imgnum,count=nproc)
	;
	; gather configuration data on each observation in reddir
	kcwi_print_info,ppar,pre,'Number of input images',nproc
	;
	; loop over images
	for i=0,nproc-1 do begin
		;
		; image to process
		;
		; check for sky subtracted image first
		obfil = kcwi_get_imname(kpars[i],imgnum[i],'_intk',/reduced)
		;
		; if not check for flat fielded image
		if not file_test(obfil) then $
			obfil = kcwi_get_imname(kpars[i],imgnum[i],'_intf',/reduced)
		;
		; if not check for dark subtracted image
		if not file_test(obfil) then $
			obfil = kcwi_get_imname(kpars[i],imgnum[i],'_intd',/reduced)
		;
		; if not just get stage1 output image
		if not file_test(obfil) then $
			obfil = kcwi_get_imname(kpars[i],imgnum[i],'_int',/reduced)
		;
		; check if input file exists
		if file_test(obfil) then begin
			;
			; read configuration
			kcfg = kcwi_read_cfg(obfil)
			;
			; direct or dispersed?
			if strpos(kcfg.obstype,'direct') ge 0 then $
				do_direct = (1 eq 1) $
			else	do_direct = (1 eq 0)
			;
			; final output file
			if do_direct then $
				ofil = kcwi_get_imname(kpars[i],imgnum[i],'_img',/reduced) $
			else	ofil = kcwi_get_imname(kpars[i],imgnum[i],'_icube',/reduced)
			;
			; get image type
			kcfg.imgtype = strtrim(kcfg.imgtype,2)
			;
			; check if output file exists already
			if kpars[i].clobber eq 1 or not file_test(ofil) then begin
				;
				; print image summary
				kcwi_print_cfgs,kcfg,imsum,/silent
				if strlen(imsum) gt 0 then begin
					for k=0,1 do junk = gettok(imsum,' ')
					imsum = string(i+1,'/',nproc,format='(i3,a1,i3)')+' '+imsum
				endif
				print,""
				print,imsum
				printf,ll,""
				printf,ll,imsum
				flush,ll
				;
				; record input file
				kcwi_print_info,ppar,pre,'input 2-D image',obfil,format='(a,a)'
				;
				; do we have the geom files?
				do_geom = (1 eq 0)	; assume no to begin with
				if strtrim(kpars[i].geom,2) ne '' then begin
					;
					; do we have a specified geom file?
				    	if strtrim(kpars[i].geom,2) ne '' then begin
						gfile = strtrim(kpars[i].geom,2)
					endif 
					;
					; if it exists, read it
					if file_test(gfile,/read) then begin
						if do_direct then begin
							kdgeom = mrdfits(gfile,1,ghdr,/silent)
							do_geom = (kdgeom.status eq 0)
						endif else begin
							kgeom = mrdfits(gfile,1,ghdr,/silent)
							do_geom = (kgeom.status eq 0)
						endelse
						;
						; log it
						kcwi_print_info,ppar,pre,'Using geometry from',gfile,format='(a,a)'
					;
					endif
					;
					; is our geometry good?
					if do_geom then begin
						;
						; read in, update header, apply geometry, write out
						;
						; object image
						img = mrdfits(obfil,0,hdr,/fscale,/silent)
						;
						sxaddpar,hdr, 'HISTORY','  '+pre+' '+systime(0)
                                                ;
						; apply direct geometry
						if do_direct then begin
							kcwi_apply_dgeom,img,hdr,kdgeom,kpars[i],dimg,dhdr
							;
							; write out intensity image
							ofil = kcwi_get_imname(kpars[i],imgnum[i],'_img',/nodir)
							kcwi_write_image,dimg,dhdr,ofil,kpars[i]
						;
						; apply dispersed geometry
						endif else begin
                                                	kcwi_apply_geom,img,hdr,kgeom,kpars[i],cube,chdr                               
							;
							; write out intensity cube
							ofil = kcwi_get_imname(kpars[i],imgnum[i],'_icube',/nodir)
							kcwi_write_image,cube,chdr,ofil,kpars[i]
							;
							; check for arc and output diagnostic 2d image
							if strpos(kcfg.imgtype,'arc') ge 0 then begin
								rcube = kcwi_get_imname(kpars[i],imgnum[i],'_icube',/reduced)
								kcwi_flatten_cube,rcube,/iscale
								kcwi_print_info,ppar,pre,'wrote image file', $
									repstr(rcube,'.fits','_2d.fits'), $
									format='(a,a)'
							endif
							;
							; variance cube
							vfil = repstr(obfil,'_int','_var')
							if file_test(vfil,/read) then begin
								var = mrdfits(vfil,0,varhdr,/fscale,/silent)
								;
								sxaddpar,varhdr,'HISTORY','  '+pre+' '+systime(0)
                                                        	kcwi_apply_geom,var,varhdr,kgeom,kpars[i],vcub,vchdr
								;
								; write out variance cube
								ofil = kcwi_get_imname(kpars[i],imgnum[i],'_vcube',/nodir)
								kcwi_write_image,vcub,vchdr,ofil,kpars[i]
							endif else $
								kcwi_print_info,ppar,pre,'no variance image found',/warning
							;
							; mask cube
							mfil = repstr(obfil,'_int','_msk')
							if file_test(mfil,/read) then begin
								msk = mrdfits(mfil,0,mskhdr,/silent)
								;
                                                        	sxaddpar,mskhdr,'HISTORY','  '+pre+' '+systime(0)
                                                        	kcwi_apply_geom,msk,mskhdr,kgeom,kpars[i],mcub,mchdr,/mask
								;
								; write out mask cube
								ofil = kcwi_get_imname(kpars[i],imgnum[i],'_mcube',/nodir)
								kcwi_write_image,mcub,mchdr,ofil,kpars[i]
							endif else $
								kcwi_print_info,ppar,pre,'no mask image found',/warning
							;
							; check for nod-and-shuffle sky images
							sfil = kcwi_get_imname(kpars[i],imgnum[i],'_sky',/reduced)
							if file_test(sfil,/read) then begin
								sky = mrdfits(sfil,0,skyhdr,/fscale,/silent)
								;
								sxaddpar,skyhdr,'HISTORY','  '+pre+' '+systime(0)
                                                        	kcwi_apply_geom,sky,skyhdr,kgeom,kpars[i],scub,schdr
								;
								; write out sky cube
								ofil = kcwi_get_imname(kpars[i],imgnum[i],'_scube',/nodir)
								kcwi_write_image,scub,schdr,ofil,kpars[i]
							endif
							;
							; check for nod-and-shuffle obj images
							nfil = kcwi_get_imname(kpars[i],imgnum[i],'_obj',/reduced)
							if file_test(nfil,/read) then begin
								obj = mrdfits(nfil,0,objhdr,/fscale,/silent)
								;
                                                        	sxaddpar,objhdr,'HISTORY','  '+pre+' '+systime(0)
                                                        	kcwi_apply_geom,obj,objhdr,kgeom,kpars[i],ocub,ochdr
								;
								; write out obj cube
								ofil = kcwi_get_imname(kpars[i],imgnum[i],'_ocube',/nodir)
								kcwi_write_image,ocub,ochdr,ofil,kpars[i]
							endif
						endelse	; end apply dispersed geometry
					; end if do_geom
					endif else $
						kcwi_print_info,ppar,pre,'unusable geom for: '+obfil+' type: '+kcfg.imgtype,/error
				;
				; end check for geom files
				endif else begin
					;
					; no problem skipping darks
					if strpos(kcfg.imgtype,'dark') ge 0 then $
						kcwi_print_info,ppar,pre,'darks do not get geometry: '+ $
							obfil,/info $
					else	kcwi_print_info,ppar,pre,'missing calibration file(s) for: '+ $
							obfil,/warning
				endelse
			;
			; end check if output file exists already
			endif else begin
				kcwi_print_info,ppar,pre,'file not processed: '+obfil+' type: '+kcfg.imgtype,/warning
				if kpars[i].clobber eq 0 and file_test(ofil) then $
					kcwi_print_info,ppar,pre,'processed file exists already',/warning
			endelse
		;
		; end check if input file exists
		endif else $
			kcwi_print_info,ppar,pre,'input file not found: '+obfil,/error
	endfor	; loop over images
	;
	; report
	eltime = systime(1) - startime
	print,''
	printf,ll,''
	kcwi_print_info,ppar,pre,'run time in seconds',eltime
	kcwi_print_info,ppar,pre,'finished on '+systime(0)
	;
	; close log file
	free_lun,ll
	;
	return
end	; kcwi_stage6cube

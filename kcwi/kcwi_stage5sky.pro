;
; Copyright (c) 2017, California Institute of Technology. All rights
;	reserved.
;+
; NAME:
;	KCWI_STAGE5SKY
;
; PURPOSE:
;	This procedure generates a model sky and subtracts it from
;	the input 2D image.
;
; CATEGORY:
;	Data reduction for the Keck Cosmic Web Imager (KCWI).
;
; CALLING SEQUENCE:
;	KCWI_STAGE5SKY, Procfname, Pparfname
;
; OPTIONAL INPUTS:
;	Procfname - input proc filename generated by KCWI_PREP
;			defaults to './redux/kcwi.proc'
;	Pparfname - input ppar filename generated by KCWI_PREP
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
;	of input files and their associated master flat files.  Each input
;	file is read in and the required master flat is generated and 
;	fit and multiplied.  If the input image is a nod-and-shuffle
;	observation, the image is sky subtracted and then the flat is applied.
;
; EXAMPLE:
;	Perform stage5sky reductions on the images in 'night1' directory and put
;	results in 'night1/redux':
;
;	KCWI_STAGE5SKY,'night1/redux/kcwi.ppar'
;
; MODIFICATION HISTORY:
;	Written by:	Don Neill (neill@caltech.edu)
;	2017-NOV-13	Initial version
;-
pro kcwi_stage5sky,procfname,ppfname,help=help,verbose=verbose, display=display
	;
	; setup
	pre = 'KCWI_STAGE5SKY'
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
	if kcwi_verify_dirs(ppar,rawdir,reddir,cdir,ddir,/nocreate) ne 0 then begin
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
	lgfil = reddir + 'kcwi_stage5sky.log'
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
	printf,ll,'Display level     : ',ppar.display
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
		; must use flat-fielded data to get a good sky model
		obfil = kcwi_get_imname(kpars[i],imgnum[i],'_intf',/reduced)
		;
		; check if input file exists
		if file_test(obfil) then begin
			;
			; read configuration
			kcfg = kcwi_read_cfg(obfil)
			;
			; final output file
			ofil = kcwi_get_imname(kpars[i],imgnum[i],'_intk',/reduced)
			;
			; trim image type
			kcfg.imgtype = strtrim(kcfg.imgtype,2)
			;
			; check of output file exists already
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
				; report input file
				kcwi_print_info,ppar,pre,'input reduced image',obfil,format='(a,a)'
				;
				; do we have master sky file?
				do_sky = (1 eq 0)
				if strtrim(kpars[i].mastersky,2) ne '' and kcfg.shuffmod ne 1 then begin
					msfile = kpars[i].mastersky
					;
					; is master sky already built?
					if file_test(msfile) then begin
						do_sky = (1 eq 1)
						;
						; log that we got it
						kcwi_print_info,ppar,pre,'master sky file = '+msfile
					endif else begin
						;
						; does input master sky image exist?
						;
						; need flat fielded image
						sinfile = repstr(msfile,'_sky','_intf')
						if file_test(sinfile) then begin
							;
							; also need geom file
							gfile = repstr(strtrim(kpars[i].geomcbar,2),'_int','_geom')
							;
							; check access
							if file_test(gfile) then begin
								;
								; check status
								kgeom = mrdfits(gfile,1,/silent)
								if kgeom.status eq 0 then begin
									do_sky = (1 eq 1)
									;
									; log that we got it
									kcwi_print_info,ppar,pre,'building master sky file = '+msfile
									kcwi_print_info,ppar,pre,'sky input file = '+sinfile
									kcwi_print_info,ppar,pre,'geom file = '+gfile
								endif else begin
									kcwi_print_info,ppar,pre,'bad geometry solution in ',gfile, $
										format='(a,a)',/error
								endelse
							endif else begin
								;
								; log that we haven't got it
								kcwi_print_info,ppar,pre,'geom file not found: '+gfile,/error
							endelse
						endif else begin
							;
							; log that we haven't got it
							kcwi_print_info,ppar,pre,'master sky input file not found: '+sinfile,/error
						endelse
					endelse
				endif	; do we have a master sky file?
				;
				; let's read in or create master sky
				if do_sky then begin
					;
					; build master sky if necessary
					if file_test(msfile) then begin
						;
						; read in master sky
						sky = mrdfits(msfile,0,mshdr,/fscale,/silent)
					endif else begin
						;
						; read sky input image
						skimg = mrdfits(sinfile,0,sihdr,/fscale,/silent)
						;
						; check for a sky mask file, (txt or fits)
						smfil = repstr(sinfile,'_intf.fits','_smsk.txt')
						smfits = repstr(sinfile,'_intf.fits','_smsk.fits')
						;
						; make the master sky
						if file_test(smfil) then begin
							kcwi_print_info,ppar,pre,'Using sky mask region file',smfil
							kcwi_make_sky,kpars[i],skimg,sihdr,gfile,sky, $
								sky_mask_file=smfil
						endif else if file_test(smfits) eq 1 then begin
							kcwi_print_info,ppar,pre,'Using sky mask image',smfits
							kcwi_make_sky,kpars[i],skimg,sihdr,gfile,sky, $
								sky_mask_file=smfits,/fits
						endif else begin
							kcwi_print_info,ppar,pre,'No sky mask'
							kcwi_make_sky,kpars[i],skimg,sihdr,gfile,sky
						endelse
					endelse
					;
					; read in image
					img = mrdfits(obfil,0,hdr,/fscale,/silent)
					;
					; get dimensions
					sz = size(img,/dimension)
					;
					; read variance, mask images
					vfil = repstr(obfil,'_int','_var')
					if file_test(vfil) then begin
						var = mrdfits(vfil,0,varhdr,/fscale,/silent)
					endif else begin
						var = fltarr(sz)
						var[0] = 1.	; give var value range
						varhdr = hdr
						kcwi_print_info,ppar,pre,'variance image not found for: '+obfil,/warning
					endelse
					mfil = repstr(obfil,'_int','_msk')
					if file_test(mfil) then begin
						msk = mrdfits(mfil,0,mskhdr,/silent)
					endif else begin
						msk = intarr(sz)
						msk[0] = 1	; give mask value range
						mskhdr = hdr
						kcwi_print_info,ppar,pre,'mask image not found for: '+obfil,/warning
					endelse
					;
					; do correction
					img = img - sky
					;
					; variance is multiplied by sky squared
					var = var + sky^2
					;
					; mask is not changed by flat
					;
					; update header
					fdecomp,msfile,disk,dir,root,ext
					sxaddpar,mskhdr,'HISTORY','  '+pre+' '+systime(0)
					sxaddpar,mskhdr,'SKYCOR','T',' sky corrected?'
					sxaddpar,mskhdr,'SKYMAST',root+'.'+ext,' master sky file'
					;
					; write out sky corrected mask image
					ofil = kcwi_get_imname(kpars[i],imgnum[i],'_mskk',/nodir)
					kcwi_write_image,msk,mskhdr,ofil,kpars[i]
					;
					; update header
					sxaddpar,varhdr,'HISTORY','  '+pre+' '+systime(0)
					sxaddpar,varhdr,'SKYCOR','T',' sky corrected?'
					sxaddpar,varhdr,'SKYMAST',root+'.'+ext,' master sky file'
					;
					; write out sky corrected variance image
					ofil = kcwi_get_imname(kpars[i],imgnum[i],'_vark',/nodir)
					kcwi_write_image,var,varhdr,ofil,kpars[i]
					;
					; update header
					sxaddpar,hdr,'HISTORY','  '+pre+' '+systime(0)
					sxaddpar,hdr,'SKYCOR','T',' sky corrected?'
					sxaddpar,hdr,'SKYMAST',root+'.'+ext,' master sky file'
					;
					; write out sky corrected intensity image
					ofil = kcwi_get_imname(kpars[i],imgnum[i],'_intk',/nodir)
					kcwi_write_image,img,hdr,ofil,kpars[i]
				endif else begin
					if kcfg.shuffmod eq 1 then $
						kcwi_print_info,ppar,pre,'sky already subtracted (N&S) for: '+ $
							kcfg.obsfname $
					else	kcwi_print_info,ppar,pre,'skipping sky subtraction for: '+ $
							kcfg.obsfname
				endelse
				flush,ll
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
end	; kcwi_stage5sky

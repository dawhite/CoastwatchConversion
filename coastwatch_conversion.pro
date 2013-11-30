;+
;coastwatch_conversion.pro
;
;This program is designed to convert NOAA CoastWatch AVHRR data sets
;into an ENVI format file.  It is not officially supported by ITT-VIS Technical
;Support and is not guaranteed to work with versions of ENVI beyond 4.3.
;It serves as an example of how you can import and georeference
;non-standard data sets into ENVI programmatically using a
;combination of IDL and ENVI routines.
;
;Author:  Devin Alan White, ITT-VIS Technical Support
;Email:  dwhite@ittvis.com
;Date:  07/20/07
;-

pro coastwatch_conversion_define_buttons, buttonInfo
	compile_opt idl2

	;Create button in ENVI menu system
	envi_define_menu_button, buttonInfo, value = 'CoastWatch AVHRR', $
	   event_pro='coastwatch_conversion', position='Last', ref_value = 'AVHRR', uvalue='Open CoastWatch AVHRR'

end


pro coastwatch_conversion, event
	compile_opt idl2

	;Prompt user for CoastWatch HDF file
	hdf_filename = dialog_pickfile(title='Select NOAA CoastWatch HDF file', filter='*.hdf')
	if hdf_filename eq '' then return

	;Prompt user to provide output path for georeferenced data
	output_path = dialog_pickfile(title='Select an output path', /directory)
	if output_path eq '' then return

	;Derive basename for outputted files from inputted file
	hdf_basename = file_basename(hdf_filename, '.hdf')

	;Initialize HDF interface for SD data
	sdinterface_id = hdf_sd_start(hdf_filename)

	;Retrieve number of datasets and related attributes
	hdf_sd_fileinfo, sdinterface_id, datasets, attributes

	;Setup geographic information, assuming a Mercator projection
	map_index = hdf_sd_attrfind(sdinterface_id, 'et_affine')
	hdf_sd_attrinfo, sdinterface_id, map_index, data=map_info
	projection = envi_proj_create(type=20, $
	params=[0.0,0.0,0.0,0.0,0.0,0.0], $
	name = 'Mercator', datum='WGS-84', $
	units = envi_translate_projection_units('Meters'))
	map_info = envi_map_info_create(proj=projection, $
		mc=[1.0,1.0,map_info[4],map_info[5]], ps=[1470.0,1470.0])

	;Access first data set in order to retrieve	image dimensions
	hdf_sd_select_id = hdf_sd_select(sdinterface_id, 0)
	hdf_sd_getinfo, hdf_sd_select_id, dims=dims

	;Create container arrays for data sets within HDF file
	hdf_data = fltarr(dims[0], dims[1], datasets)
	dataset_names = strarr(datasets)

	;Process data
	for j=0,datasets-1 do begin
		sd_id = hdf_sd_select(sdinterface_id, j)

		;Get name of dataset
		hdf_sd_getinfo, sd_id, name=name
		dataset_names[j] = name

		;Get raw data
		hdf_sd_getdata, sd_id, data

		;Get fill, scale, and offset values
		fill_index = hdf_sd_attrfind(sd_id, '_FillValue')
		scale_index = hdf_sd_attrfind(sd_id, 'scale_factor')
		offset_index = hdf_sd_attrfind(sd_id, 'add_offset')

		fill_count = 0
		if fill_index ge 0 then begin
			hdf_sd_attrinfo, sd_id, fill_index, data=fill_value
			where_fill = where(data eq fill_value[0], fill_count)
		endif

		;Follow HDF stored value conversion convention:
		;float value = scale_factor*(stored_value - add_offset) (scale_factor =< 1)
		;float value = (stored_value - add_offset)/scale_factor (scale_factor > 1)
		;float value = stored_value - add_offset (scale_factor = 0)
		if (scale_index ge 0) && (offset_index ge 0) then begin
			hdf_sd_attrinfo, sd_id, scale_index, data=scale_factor
			hdf_sd_attrinfo, sd_id, offset_index, data=add_offset
			if double(scale_factor[0]) le 1.0d then data = (double(data) - add_offset[0])*scale_factor[0]
			if double(scale_factor[0]) gt 1.0d	then data = (double(data)-add_offset[0])/scale_factor[0]
			if double(scale_factor[0]) eq 0.0d then data = double(data) - add_offset[0]
		endif
		;No scale factor or offset present
		if (scale_index eq -1) && (offset_index eq -1) then data = double(data)
		;Only offset present
		if (scale_index eq -1) && (offset_index ge 0) then begin
			hdf_sd_attrinfo, sd_id, offset_index, data=add_offset
			data = double(data) - add_offset[0]
		endif
		;Only scale present
		if (scale_index ge 0) && (offset_index eq -1) then begin
			hdf_sd_attrinfo, sd_id, scale_index, data=scale_factor
			if double(scale_factor[0]) le 1.0d then data = double(data)*scale_factor[0]
			if double(scale_factor[0]) gt 1.0d	then data = double(data)/scale_factor[0]
			if double(scale_factor[0]) eq 0.0d then data = double(data)
		endif

		;Convert data from double to float to save space in output file
		data = float(data)
		;Convert fill values to NaN
		if fill_count gt 0 then begin
			data[where_fill] = 'NaN'
		endif

		;Put data in container array
		hdf_data[*,*,j] = data

	endfor
	;Close HDF interface
	hdf_sd_end, SDinterface_id

	;Build ENVI format file
	out_filename = output_path + hdf_basename + '_converted.img'
	sensor_type = envi_sensor_type('AVHRR')
	envi_write_envi_file, hdf_data, bnames=dataset_names, data_type=4, interleave=0, $
		map_info=map_info, nb=datasets, ns=dims[0], nl=dims[1], out_dt=4, out_name=out_filename, $
		sensor_type=sensor_type

end
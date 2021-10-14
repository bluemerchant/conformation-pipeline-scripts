#!/bin/bash

./csdb2pdb.sh

export TINKER_HOME=./Tinker
export PATH=./Tinker/bin:$PATH
export CAT_USER=.
USER='PUT_HERE_USERNAME'
PASS='PUT_HERE_PASSWORD'
HOST='PUT_HERE_HOST'
REMOTE_DIR='PUT_HERE_DIRECTORY'
current_date=`date +%Y.%m.%d-%H:%M`

array=()
find ./pdb_sources -name '*.pdb' -print0 > /tmp/pdb_list_tmp
while IFS=  read -r -d $'\0'; do
    array+=(`realpath $REPLY`)
done < /tmp/pdb_list_tmp
rm -f /tmp/pdb_list_tmp
for i in "${array[@]}"
do
    current_pdb=`echo $i | rev | cut -d / -f1 | rev | cut -d . -f1`
    current_pdb_prefix=`echo $i | rev | cut -d / -f2 | rev`
    current_folder="cat-results-$current_date-$current_pdb_prefix"
    if [ ! -d $current_folder ]; then
        mkdir $current_pdb_prefix
        cd $current_pdb_prefix
        cp $i .
        box_size=`ls | sed 's/[^0-9][^0-9]*\([0-9][0-9]*\).*/\1/g'`
        charge_ca=`grep -wc "N1+" $i`
        charge_an=`grep -wc "O1-" $i`
        total_charge=`expr $charge_ca - $charge_an`
        csl_config=$1
	echo -e "
parameters             ../Tinker/params/mm3.prm      
archive
randomseed             91202
cutoff                 10
printout               2000
integrate              BEEMAN
STEEPEST-DESCENT
MAXITER                100000
LIGHTS
" > minim_init.key
        echo -e "
parameters             ../Tinker/params/mm3.prm      
archive
randomseed             91202
tautemp                0.1
cutoff                 10
printout               2000
A-AXIS                 $box_size
B-AXIS                 $box_size
C-AXIS                 $box_size
integrate              BEEMAN
THERMOSTAT             BERENDSEN
VDWTERM
VDWTYPE                MM3-HBOND
EWALD
EWALD-BOUNDARY
EWALD-CUTOFF           10
GAUSSTYPE              MM3-2
STEEPEST-DESCENT
MAXITER                100000
LIGHTS
DIPOLETERM
CHARGETERM
BONDTERM
OPBENDTYPE             ALLINGER
OPBENDTERM
ANGLETERM
ANGANGTERM	
SOLVATETERM
TORSIONTERM
STRTORTERM
STRBNDTERM
" > minim_box.key
        echo -e "
parameters             ../Tinker/params/mm3.prm      
archive
randomseed             91202
tautemp                0.1
cutoff                 10
printout               100000
A-AXIS                 $box_size
B-AXIS                 $box_size
C-AXIS                 $box_size
integrate              BEEMAN
THERMOSTAT             BERENDSEN
VDWTERM
VDWTYPE                MM3-HBOND
EWALD
EWALD-BOUNDARY
EWALD-CUTOFF           10
GAUSSTYPE              MM3-2
LIGHTS
DIPOLETERM
CHARGETERM
BONDTERM
OPBENDTYPE             ALLINGER
OPBENDTERM
ANGLETERM
ANGANGTERM	
SOLVATETERM
TORSIONTERM
STRTORTERM
STRBNDTERM
" > start_eq.key
        echo -e "
parameters             ../Tinker/params/mm3.prm      
archive
randomseed             91202
tautemp                0.1
cutoff                 10
printout               2000
A-AXIS                 $box_size
B-AXIS                 $box_size
C-AXIS                 $box_size
integrate              BEEMAN
THERMOSTAT             BERENDSEN
VDWTERM
VDWTYPE                MM3-HBOND
EWALD
EWALD-BOUNDARY
EWALD-CUTOFF           10
GAUSSTYPE              MM3-2
LIGHTS
DIPOLETERM
CHARGETERM
BONDTERM
OPBENDTYPE             ALLINGER
OPBENDTERM
ANGLETERM
ANGANGTERM	
SOLVATETERM
TORSIONTERM
STRTORTERM
STRBNDTERM
" > start.key
        echo -e "<CSL id='run_tinker_csl'>
<read_parameters path='CAT_par.xml' />
<read_template  path='$i'   bonds='calculate' bonds='per_molecule' molecules='find'  />
<#md_parameters temperature='300' time_step_fs='1.0' history_start='0' history_freq='2.0' history_unit='ps' N_time_steps='100000000' />
<assign_atom_properties mode='MM3_atom_types'    /> 
<save_template format='tinker' path='start.tnk'/>
</CSL>
" > run_tinker.csl
        echo -e "<CSL id='run_min_csl'>
<read_parameters path='CAT_par.xml' />
<read_template format='tinker' path='start.xyz' />
<save_template format='pdb' path='min.pdb'/>
</CSL>
" > run_min.csl
        echo -e "<CSL id='run_box.csl'>
<read_parameters path='CAT_par.xml' />
<read_template  path='solution_box.pdb'   bonds='calculate' bonds='per_molecule' molecules='find'  />
<assign_atom_properties mode='MM3_atom_types'    /> 
<save_template format='tinker' path='box_equilibrate.tnk'/>
</CSL>
" > run_box.csl
	echo -e "<CSL id='convert_archive'>
<read_parameters path='CAT_par.xml' />
<#analysis_parameter solvent_residue1='WAT' solvent_residue2='DMS'  />
<read_template path='solution_box.pdb'  bonds='calculate' molecules='find'  cen#ter='1' cen#ter='solute' PBC='on' />
<deactivate_atoms atom_type='solvent' />
<deactivate_atoms atom_type='ions' />
<save_template path='template_nos.pdb' mode='active'/>
<convert_archive input_path='dynamics.arc'  output_path='MD_trj.xyz'  ce#nter='solute' ce#nter='1'  output_mode='active' frames='0 0 1'  />
<save_template path='last_nos.pdb' mode='active'/>
</CSL>
" > XTC_postprocessor.csl
        echo -e "<CSL id='analyse_trajectory'>
<help>
Analysis of MD trajectories
requires 'MD_parameters.csl' in local path
Parameters:
1. template
2. trajectory
</help>
<read_parameters path='CAT_par.xml' />
<read_color_table table_id='svg' />
<read_color_table2 table_id='rgb_greenwhitered_light' />
<analysis_parameters torsion_scale_start='-120' torsion_scale_delta='10' />
<md_parameters temperature='300' time_step_fs='1.0' history_start='0' history_freq='2.0' history_unit='ps' N_time_steps='100000000' />
<analysis_parameters  population_output='boltzmann'  rel_energy_cutoff='10.0' />
<read_template path='$i' bonds='calculate' molecules='find' PBC='off' />
<!-- -------------------------------------------------------------------- -->
<!--  define waves   -->
<!-- -------------------------------------------------------------------- -->
<find_carbohydrate />
<assign_linkages wave_def_flag='2'  wave_group_id='12'  dim='0' def_atoms='sugar' IUPA#C='xray'   />
<#assign_linkages wave_def_flag='16'  wave_group_id='16'  dim='3' def_atoms='sugar' IUPA#C='xray'   />
<assign_torsions wave_def_flag='true' group_id='1' wave_group_id='1'  def_atoms='sugar_glycosidic_phi'  IUP#AC='xray' />
<assign_torsions wave_def_flag='true' group_id='2' wave_group_id='2'  def_atoms='sugar_glycosidic_psi'  IUP#AC='xray'   />
<assign_torsions wave_def_flag='true' group_id='3' wave_group_id='3'  def_atoms='sugar_omega'  IU#PAC='xray'   />
<assign_torsions wave_def_flag='16' group_id='16' wave_group_id='3'  def_atoms='sugar_omega'  IU#PAC='xray'   />
<!-- these are only required for adjusting the template minima - no need to output the trajectories - saves disc space --> 
<assign_torsions wave_def_flag='true' group_id='4' wave_group_id='4'  def_atoms='sugar_OH'  IU#PAC='xray'  output_flag='0'   />
<!-- ring conformation waves  -->
<assign_rings mode='sugar_6ring_conformation' wave_group_id='6'   ring_size='6'   population_output='percent' />
</skip>
<!-- -------------------------------------------------------------------- -->
<!--  analyse trajectory  -->
<!-- -------------------------------------------------------------------- -->
<analyse_trajectory  input_path='MD_trj.xyz' fra#mes='0 0 1' adjust_history_freq='true' />
<find_minima  grid_wave='all' min_barrier='0.7' max_level='5.0' options='save2template_values' />
<!-- -------------------------------------------------------------------- -->
<!--  save results  -->
<!-- -------------------------------------------------------------------- -->
<CONTROL:system_call command='mkdir maps'  /> 
<plot_parameter width='600' height='400' fontsize='14' markersize='2' title='auto' x_label='auto' y_label='auto' value_min='0'  value_max='5' />
<save_waves format='xml' path='local_minima'  output_mode='template_values'   />
<save_waves format='xml'  path='MD_data'  />
<save_waves format='xml single' path='maps/Map_data_' value_type='linkage' />
<!-- -------------------------------------------------------------------- -->
<!--   generate SVG plots using CAT  -->
<!-- -------------------------------------------------------------------- -->
<!--  read color used for trajectories -->
<read_color_table table_id='svg' background_color='none' />
<CONTROL:system_call command='mkdir maps_svg'  /> 
<#save_waves format='svg' path='maps_svg/Map_image_' value_type='linkage' />
<read_color_table2 table_id='rgb_greenwhite' />
<plot_parameter width='500' height='500' marker_size='10'  fontsize='12' title='auto' />
<plot_parameter  margin_left='100'  margin_right='300'  margin_top='100'  margin_bottom='100'  />
<plot_parameter highlight_color='white' highlight_color2='yellow'   />
<!-- plot template values for linkages with plot_style='markers' AND/OR user_markers='-1'   , user_markers='-10' plots also reference template_values (0) with plot_highlight_color2  --> 
<save_plot path='maps_svg/FYmap_min' image_format='svg' value_type='linkage' grid_wave='all' plot_style='markers' user_markers='-1' 
x_scaling='-120 240 60' y_scaling='-120 240 60' z_min='1.0' z_max='10' hyperlinks='value' output_mode='dump'  />
<CONTROL:system_call command='mkdir svg_plots'  /> 
<!-- dump output of all torsion waves as SVG - use interval='x' to plot only every xth point to save disc space and make the html report display faster-->
<save_waves format='svg' path='svg_plots/tors_' value_type='torsion'  interval='10'  />
<plot_parameter plot_style_default='spline'  markersize='1'  linewidth='3' barwidth='1'  mar#ker_fill='border'   />
<save_waves format='svg' path='svg_plots/torsH_' value_type='torsion'  interval='10' output_mode='histogram'  />
<plot_parameter title='Ring Conformations '  x_label='auto' y_label='auto'  />
<make_color_table2    first='blue'   first_label='4C1' last='red' last_label='1C4'  named_entries='1' color_list='yellow' color_labels='boat/twist'   />
<!-- smooth='-999010'  means plot only every 10th datapoint -->
<save_plot path='svg_plots/RINGS_trj' image_format='svg' x_wave='auto' y_wave='all'  linewidth='1' markerfill='true'  smooth='-999010' 
wave_group_id='6'     output_mode='traj_waves_as_y_category'  plot_style='markers'   markersize='auto'   
marker_color='value_section'   color_value_sections='14 26' 
 x_sca#ling='-120 240 20' y_scaling='0 38'  grid_#lines='xy' user_grid_lines_x='999021 '  group_wave='section_id'   />
<CSL/>
" > maps.csl
        export CAT_HOME=../CAT
        cp -r ../CAT/lib .
        cp ../job.log .
        ../CAT/bin/CAT.linux64 run_tinker.csl start
        ../Tinker/bin/minimize start.tnk -k minim_init.key 0.01 > start_min.log start
        ../CAT/bin/CAT.linux64 run_min.csl start
        ../packmol/solvate.tcl min.pdb -shell $box_size. -charge $total_charge -density 1.0 -i mixture_comment.inp -o solution_box.pdb start
        sed -i '19s/.0//' mixture_comment.inp
        ../packmol/packmol < mixture_comment.inp start
        ../CAT/bin/CAT.linux64 run_box.csl start
	../Tinker/bin/minimize box_equilibrate.tnk -k minim_box.key 1.0 > start_min_1.log start
        ../Tinker/bin/dynamic box_equilibrate.xyz -k start_eq.key 100000 1.0 2.000 2 300.00 > equil.log start
	rm -r equil.log
        mv box_equilibrate.arc box.xyz
	mv box_equilibrate.dyn box.dyn
        ../Tinker/bin/dynamic box.xyz -k start.key 100000000 1.0 2.000 2 300.00 > dynamics.log start
        sed '/0\ \ \ 90.000000\ \ \ 90.000000\ \ \ 90.000000/d' box.arc > dynamics.arc
        rm -r box.arc
        ../CAT/bin/CAT.linux64 XTC_postprocessor.csl start
        ../CAT/bin/CAT.linux64 maps.csl start
        tar cvzf MD_trj.tar.gz MD_trj.xyz
        rm -r MD_trj.xyz
        tar cvzf dynamics.tar.gz dynamics.log
        rm -r dynamics.log
        rm -r dynamics.arc
        rm -rf ./lib
        tar -cvzf "$current_pdb_prefix.tar.gz" *
        lftp -u $USER,$PASS $HOST <<EOF
        set ftp:ssl-protect-data true
        set ftp:ssl-force true
        set ssl:verify-certificate no
        put -O "$REMOTE_DIR" "$current_pdb_prefix.tar.gz"
        quit
EOF
        cd ..
        rm -r $current_pdb_prefix
    fi
done

rm -r ./pdb_sources

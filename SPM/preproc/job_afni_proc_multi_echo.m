function job = job_afni_proc_multi_echo( meinfo , par )
% JOB_AFNI_PROC_MULTI_ECHO - AFNI:afni_proc.py
%
% INPUT : meinfo structure generated by job_sort_echos
%
% Note : if you use matvol objects, you can add a field .volume in meinfo, such as : meinfo.volume = e.getSerie('run').getVolume('^e');
%
% See also job_sort_echos get_subdir_regex get_subdir_regex_files exam exam.AddSerie exam.addVolume


%% Check input arguments

if ~exist('par','var')
    par = ''; % for defpar
end

if nargin < 1
    help(mfilename)
    error('[%s]: not enough input arguments - img is required',mfilename)
end

obj = 0;
if isfield(meinfo,'volume')
    obj = 1;
    in_obj  = meinfo.volume; % @volume array
end

if isfield(meinfo,'anat')
    switch class(meinfo.anat)
        case 'volume'
            anat = meinfo.anat.toJob(0);
        case 'cellstr'
            anat = meinfo.anat;
        otherwise
            error('format of anat input is not supported : cellstr or @volume')
    end
    assert(length(anat) == length(meinfo.path),'number of anat is not consistent')
end


%% defpar

% TEDANA recomandations : tshift, volreg
% MEICA pipeline        : despike, tshift, align, volreg
% robust for TEDANA     : despike, tshift, align, volreg BUT it "blurs" the data

defpar.blocks   = {'despike','tshift','volreg'}; % now codded : despike, tshift, align, volreg
defpar.seperate = 0;                             % each volume is treated seperatly : useful when runs have different orientations
defpar.execute  = 1;                             % execute afni_proc.py generated tcsh script file immidatly after the generation

defpar.OMP_NUM_THREADS = 0; % number of CPU threads : 0 means all CPUs available

defpar.sge      = 0;
defpar.jobname  = 'job_afni_proc_multi_echo';
defpar.subdir   = 'afni';

defpar.auto_add_obj = 1;

defpar.pct      = 0;
defpar.redo     = 0;
defpar.run      = 1;
defpar.display  = 0;
defpar.verbose  = 1;

par = complet_struct(par,defpar);

% Security
if par.sge
    par.auto_add_obj = 0;
end
if par.sge || par.pct
    par.OMP_NUM_THREADS = 1; % in case of parallelization, only use 1 thread per job
end

%% Seperate ? then we need to reformat meinfo

if par.seperate
    
    meinfo_orig = meinfo; % make a copy
    
    j = 0; % job
    
    meinfo_new = struct;
    
    for iSubj =  1 : length(meinfo.path)
        for iRun = 1 : length(meinfo.path{iSubj})
            
            j = j + 1;
            
            meinfo_new.full       {j,1}{1} = meinfo_orig.full       {iSubj}{iRun};
            meinfo_new.path       {j,1}{1} = meinfo_orig.path       {iSubj}{iRun};
            meinfo_new.TE         {j,1}{1} = meinfo_orig.TE         {iSubj}{iRun};
            meinfo_new.TR         {j,1}{1} = meinfo_orig.TR         {iSubj}{iRun};
            meinfo_new.sliceonsets{j,1}{1} = meinfo_orig.sliceonsets{iSubj}{iRun};
            meinfo_new.volume              = meinfo_orig.volume                  ;
            meinfo_new.anat                = meinfo_orig.anat                    ;
            
        end % iSubj
    end % iRun
    
    meinfo = meinfo_new; % swap
    
end


%% Setup that allows this scipt to prepare the commands only, no execution

parsge  = par.sge;
par.sge = -1; % only prepare commands

parverbose  = par.verbose;
par.verbose = 0; % don't print anything yet


%% afni_proc.py

prefix = char(par.blocks); % {'despike', 'tshift', 'volreg'}
prefix = prefix(:,1)';
prefix = fliplr(prefix);   % 'vtd'

nSubj = length(meinfo.path);
job   = cell(0);
skip  = [];

for iSubj = 1 : nSubj
    
    %----------------------------------------------------------------------
    % Prepare job
    %----------------------------------------------------------------------
    
    subj_path = get_parent_path(meinfo.path{iSubj}{1}{1},2);
    
    if par.seperate
        [~,subj_name,~] = fileparts(subj_path);
        run_path        = get_parent_path(meinfo.path{iSubj}{1}{1});
        [~,run_name,~]  = fileparts(run_path);
        subj_name       = sprintf('%s__%s',subj_name,run_name);
        working_dir     = fullfile(run_path,par.subdir);
    else
        [~,subj_name,~] = fileparts(subj_path);
        working_dir     = fullfile(subj_path,par.subdir);
    end
    
    if ~par.redo  &&  exist(working_dir,'dir')==7
        fprintf('[%s]: skiping %d/%d because %s exist \n', mfilename, iSubj, nSubj, working_dir);
        job{iSubj,1} = '';
        skip = [skip iSubj]; %#ok<AGROW>
        continue
    elseif exist(working_dir,'dir')==7
        rmdir(working_dir,'s')
    end
    
    fprintf('[%s]: Preparing JOB %d/%d @ %s \n', mfilename, iSubj, nSubj, subj_path);
    cmd = sprintf('#################### [%s] JOB %d/%d @ %s #################### \n', mfilename, iSubj, nSubj, subj_path); % initialize
    
    %----------------------------------------------------------------------
    % afni_proc.py basics
    %----------------------------------------------------------------------
    
    cmd     = sprintf('%s export OMP_NUM_THREADS=%d;   \n', cmd, par.OMP_NUM_THREADS); % multi CPU option
    if par.seperate
        cmd = sprintf('%s cd %s;                       \n', cmd, run_path   );         % go to subj dir so afni_proc tcsh script is written there
        cmd = sprintf('%s afni_proc.py -subj_id %s \\\\\n', cmd, subj_name  );         % subj_id is almost mendatory with afni
        cmd = sprintf('%s -out_dir %s              \\\\\n', cmd, working_dir);         % afni working dir
    else
        cmd = sprintf('%s cd %s;                       \n', cmd, subj_path  );         % go to subj dir so afni_proc tcsh script is written there
        cmd = sprintf('%s afni_proc.py -subj_id %s \\\\\n', cmd, subj_name  );         % subj_id is almost mendatory with afni
        cmd = sprintf('%s -out_dir %s              \\\\\n', cmd, working_dir);         % afni working dir
    end
    cmd     = sprintf('%s -scr_overwrite           \\\\\n', cmd);                      % overwrite previous afni_proc tcsh script, if exists
    
    % add ME datasets
    for iRun = 1 : length(meinfo.path{iSubj})
        run_path = get_parent_path(meinfo.path{iSubj}{iRun}{1});
        cmd = sprintf('%s -dsets_me_run %s \\\\\n',cmd, fullfile(run_path,'e*.nii'));
    end % iRun
    
    % blocks
    blocks = strjoin(par.blocks, ' ');
    cmd    = sprintf('%s -blocks %s \\\\\n',cmd, blocks);
    nBlock = 0; % manually manage the block number : some does generate volumes, some does not
    
    %----------------------------------------------------------------------
    % Blocks options
    %----------------------------------------------------------------------
    
    % despike
    if strfind(blocks, 'despike') %#ok<*STRIFCND>
        nBlock = nBlock + 1;
    end
    
    % tshift
    if strfind(blocks, 'tshift')
        
        nBlock = nBlock + 1;
        cmd    = sprintf('%s -tshift_interp -heptic \\\\\n', cmd);
        
        % TR & slice onsets
        sliceonsets = meinfo.sliceonsets{iSubj}{1} / 1000; % millisecond -> second;
        TR =  meinfo.TR{iSubj}{1} / 1000;
        tpattern = fullfile(subj_path,'sliceonsets.txt'); % destination file
        fileID = fopen( tpattern , 'w' , 'n' , 'UTF-8' );
        if fileID < 0
            warning('[%s]: Could not open %s', mfilename, filename)
        end
        fprintf(fileID, '%f\n', sliceonsets ); % in seconds
        fclose(fileID);
        cmd = sprintf('%s -tshift_opts_ts -TR %g -tpattern @%s \\\\\n', cmd, TR, tpattern);
        
    end
    
    % align
    if strfind(blocks, 'align')
        % no volume generated, do not increment nBlock
        cmd = sprintf('%s -copy_anat %s                                              \\\\\n', cmd, anat{iSubj});
        cmd = sprintf('%s -volreg_align_e2a                                          \\\\\n', cmd             );
        cmd = sprintf('%s -align_opts_aea -ginormous_move -cost lpc+ZZ -resample off \\\\\n', cmd             );
    end
    
    % volreg
    if strfind(blocks, 'volreg')
        nBlock = nBlock + 1;
        cmd    = sprintf('%s -reg_echo 1                          \\\\\n', cmd);
        cmd    = sprintf('%s -volreg_warp_final_interp wsinc5     \\\\\n', cmd);
        cmd    = sprintf('%s -volreg_align_to MIN_OUTLIER         \\\\\n', cmd);
        cmd    = sprintf('%s -volreg_interp -quintic              \\\\\n', cmd);
        cmd    = sprintf('%s -volreg_zpad 4                       \\\\\n', cmd);
        cmd    = sprintf('%s -volreg_opts_vr -nomaxdisp           \\\\\n', cmd); % this step takes way too long on the cluster
        % cmd    = sprintf('%s -volreg_post_vr_allin yes            \\\\\n', cmd); % per run alignment, like align_center ?
        % cmd    = sprintf('%s -volreg_pvra_base_index MIN_OUTLIER  \\\\\n', cmd);
    end
    
    % Execute the batch generated by afni_proc.py -------------------------
    if par.execute
        cmd = sprintf('%s -execute \\\\\n', cmd);
    end
    
    % ALWAYS end with cariage return
    cmd = sprintf('%s \n', cmd);
    
    %----------------------------------------------------------------------
    % Convert processed echos to nifi
    %----------------------------------------------------------------------
    
    for iRun = 1 : length(meinfo.path{iSubj})
        for echo = 1 : length( meinfo.path{iSubj}{iRun} )
            in  = fullfile(working_dir, sprintf('pb%0.2d.%s.r%0.2d.e%0.2d.%s+orig', nBlock, subj_name, iRun, echo, par.blocks{end}) );
            out = addprefixtofilenames( meinfo.path{iSubj}{iRun}{echo}, prefix);
            cmd = sprintf('%s 3dAFNItoNIFTI -verb -verb -prefix %s %s \n', cmd, out, in);
        end % echo
    end % iRun
    
    %----------------------------------------------------------------------
    % Save job
    %----------------------------------------------------------------------
    
    job{iSubj,1} = cmd;
    
    
end % iSubj

job(skip) = [];


%% Run the jobs

% Fetch origial parameters, because all jobs are prepared
par.sge     = parsge;
par.verbose = parverbose;

% Prepare Cluster job optimization
if par.sge
    if par.OMP_NUM_THREADS == 0
        par.OMP_NUM_THREADS = 1; % on the cluster, each node have 28 cores and 128Go of RAM
    end
    par.sge_nb_coeur = par.OMP_NUM_THREADS;
    par.mem          = 4000; % AFNI is memory efficient, even with huge data
    par.walltime     = '08'; % 8h computation max for 8 runs MEMB runs
end

% Run CPU, run !
job = do_cmd_sge(job, par);


%% Add outputs objects

if obj && par.auto_add_obj && par.run
    
    tag             =  {in_obj.tag};
    ext             = '.*.nii$';
    for iVol = 1 : numel(in_obj)
        in_obj(iVol).serie.addVolume(['^' prefix tag{iVol} ext],[prefix tag{iVol}])
    end
    
end


end % function

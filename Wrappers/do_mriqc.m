function  do_mriqc(bids_dir,par)

if ~exist('par'),par ='';end

defpar.frac = 0.1 ;

defpar.jobname = 'mriqc';
defpar.outdir = '';

defpar.sge=0;

par = complet_struct(par,defpar);


bids_dir=cellstr(char(bids_dir));

cmd={};

if isempty(par.outdir)
    [pp fff] = get_parent_path(bids_dir{1})
    par.outdir = r_mkdir(pp,'mriqc_out');
    par.outdir=par.outdir{1}
end
    

for nbbids=1:length(bids_dir)
    
    bdir = bids_dir{nbbids};
    
    suj = gdir(bdir,'^sub');
    
    [pp sujname] = get_parent_path(suj);
    
    for kk=1:length(suj)
        cmd{end+1} = sprintf('mriqc %s %s participant  --n_cpus 1  --ants-nthreads 1 ',bdir,par.outdir);
        cmd{end} = sprintf('%s--ica --fft-spikes-detector --hmc-fsl --no-sub --verbose-reports --participant-label %s \n',...
            cmd{end},sujname{kk}(5:end));
    end
end

do_cmd_sge(cmd,par)


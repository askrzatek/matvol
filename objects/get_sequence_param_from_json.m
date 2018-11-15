function [ param ] = get_sequence_param_from_json( json_filename, all_fields, pct )
%GET_SEQUENCE_PARAM_FROM_JSON read the content of the json file, and get the most useful parameters
%
% IMPORTANT : the parameters are BIDS compatible.
% Mostly, it means using SI units, with BIDS json names
%
% Syntax :  [ param ] = get_sequence_param_from_json( json_filename                    )
% Syntax :  [ param ] = get_sequence_param_from_json( json_filename , all_fields , pct )
%
% json_filename can be char, a cellstr, cellstr containing multi-line char
%
% all_fields is a flag, to add all fields in the structure, even if the paramter is not available
% ex : 3DT1 sequence do not have SliceTiming, but EPI does
% all_fields=1 is usefull if you want to convert the output structure into a cell
% all_fields=2 also fetchs fields at first levels of the json (mostly for MRIQC output .json)
%
% pct is a flag to activate Parallel Computing Toolbox
%
% see also gfile gdir parpool
%

if nargin == 0
    help(mfilename)
    return
end

AssertIsCharOrCellstr( json_filename )
json_filename = cellstr(json_filename);

if nargin < 2
    all_fields = 0;
end

if nargin < 3
    pct = 0; % Parallel Computing Toolbox
end


%% Main loop

param = cell(size(json_filename));

if pct
    
    parfor idx = 1 : numel(json_filename)
        param{idx} = parse_jsons(json_filename{idx}, all_fields);
    end
    
else
    
    for idx = 1 : numel(json_filename)
        param{idx} = parse_jsons(json_filename{idx}, all_fields);
    end
    
end

% Jut for conviniency
if numel(param) == 1
    param = param{1};
end


end % function

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function data = parse_jsons(json_filename, all_fields)

data = struct([]);

for j = 1 : size(json_filename,1)
    %% Open & read the file
    
    content = get_file_content_as_char(json_filename(j,:));
    if isempty(content)
        warning( 'Empty file : %s', json_filename(j,:) )
        continue
    end
    
    
    %% Fetch all fields
    
    % TR
    RepetitionTime = get_field_one(content, 'RepetitionTime');
    if ~isempty(RepetitionTime)
        
        %------------------------------------------------------------------
        % Sequence
        %------------------------------------------------------------------
        
        data_file.RepetitionTime    = str2double( RepetitionTime ) / 1000           ;
        data_file.MRAcquisitionType = get_field_one( content, 'MRAcquisitionType' ) ;
        
        % Sequence name in Siemens console
        SequenceFileName = get_field_one(content, 'CsaSeries.MrPhoenixProtocol.tSequenceFileName');
        if ~isempty(SequenceFileName)
            split = regexp(SequenceFileName,'\\\\','split'); % example : "%SiemensSeq%\\ep2d_bold"
            data_file.SequenceFileName = split{end};
        else
            data_file.SequenceFileName = '';
        end
        
        % Sequence binary name ?
        SequenceName = get_field_one(content, 'SequenceName'); % '*tfl3d1_ns'
        data_file.SequenceName = SequenceName;
        
        data_file.EchoTime          = str2double( get_field_one( content, 'EchoTime'          ) ) / 1000; % second
        data_file.FlipAngle         = str2double( get_field_one( content, 'FlipAngle'         ) )       ; % degre
        data_file.InversionTime     = str2double( get_field_one( content, 'InversionTime'     ) ) / 1000; % second
        
        % Sequence number on the console
        % ex1 : mp2rage       will have paramput series but with identical SequenceID (INV1, INV2, UNI_Image)
        % ex2 : gre_field_map will have paramput series but with identical SequenceID (magnitude, phase)
        data_file.SequenceID = str2double( get_field_one(content, 'CsaSeries.MrPhoenixProtocol.lSequenceID') );
        
        data_file.ScanningSequence = get_field_mul(content, 'ScanningSequence');
        data_file.SequenceVariant  = get_field_mul(content, 'SequenceVariant' );
        data_file.ScanOptions      = get_field_mul(content, 'ScanOptions'     );
        
        % Slice Timing
        SliceTiming = get_field_mul(content, 'CsaImage.MosaicRefAcqTimes'); SliceTiming = str2double(SliceTiming(2:end))' / 1000;
        data_file.SliceTiming = SliceTiming;
        
        % bvals & bvecs
        B_value = get_field_mul(content, 'CsaImage.B_value'); B_value = str2double(B_value)';
        data_file.B_value = B_value;
        B_vect  = get_field_mul_vect(content, 'CsaImage.DiffusionGradientDirection');
        data_file.B_vect = B_vect;
        
        %------------------------------------------------------------------
        % Machine
        %------------------------------------------------------------------
        data_file.MagneticFieldStrength = str2double( get_field_one( content, 'MagneticFieldStrength' ) ); % Tesla
        data_file.Manufacturer          =             get_field_one( content, 'Manufacturer'          )  ;
        data_file.ManufacturerModelName =             get_field_one( content, 'ManufacturerModelName' )  ;
        data_file.Modality              =             get_field_one( content, 'Modality'              )  ;
        
        %------------------------------------------------------------------
        % Subject
        %------------------------------------------------------------------
        data_file.PatientName      =             get_field_one( content, 'PatientName'      )   ;
        data_file.PatientAge       =             get_field_one( content, 'PatientAge'       )   ;
        data_file.PatientBirthDate = str2double( get_field_one( content, 'PatientBirthDate' ) ) ;
        data_file.PatientWeight    = str2double( get_field_one( content, 'PatientWeight'    ) ) ;
        data_file.PatientSex       =             get_field_one( content, 'PatientSex'       )   ;
        
        %------------------------------------------------------------------
        % Date / Time
        %------------------------------------------------------------------
        data_file.AcquisitionDate = str2double( get_field_one( content, 'AcquisitionDate' ) ) ;
        data_file.StudyDate       = str2double( get_field_one( content, 'StudyDate'       ) ) ;
        data_file.StudyTime       = str2double( get_field_one( content, 'StudyTime'       ) ) ;
        data_file.AcquisitionTime = cellfun( @str2double, get_field_mul(content, 'AcquisitionTime') ); % AcquisitionTime is special, it depends on 3D vs 4D
        
        
        %------------------------------------------------------------------
        % Study / Serie
        %------------------------------------------------------------------
        data_file.StudyID           = str2double( get_field_one( content, 'StudyID'           ) ) ;
        data_file.StudyInstanceUID  =             get_field_one( content, 'StudyInstanceUID'  )   ;
        data_file.SeriesInstanceUID =             get_field_one( content, 'SeriesInstanceUID' )   ;
        data_file.StudyDescription  =             get_field_one( content, 'StudyDescription'  )   ;
        data_file.SeriesDescription =             get_field_one( content, 'SeriesDescription' )   ;
        data_file.ProtocolName      =             get_field_one( content, 'ProtocolName'      )   ;
        data_file.SeriesNumber      = str2double( get_field_one( content, 'SeriesNumber'      ) ) ;
        data_file.TotalScanTimeSec  = str2double( get_field_one( content, 'CsaSeries.MrPhoenixProtocol.lTotalScanTimeSec') );
        
        
        %------------------------------------------------------------------
        % Image
        %------------------------------------------------------------------
        data_file.ImageType                    =                       get_field_mul     ( content, 'ImageType'                  )  ; % M' / 'P' / ... % Magnitude ? Phase ? ...
        data_file.ImageOrientationPatient      = cellfun( @str2double, get_field_mul     ( content, 'ImageOrientationPatient'    ) );
        switch data_file.MRAcquisitionType
            case '2D'
                data_file.ImagePositionPatient = cellfun( @str2double, get_field_mul     ( content, 'ImagePositionPatient'       ) );
            case '3D'
                data_file.ImagePositionPatient =                       get_field_mul_vect( content, 'ImagePositionPatient'       )  ;
        end
        data_file.AbsTablePosition             = str2double(           get_field_one     ( content, 'CsaSeries.AbsTablePosition' ) );
        
        %------------------------------------------------------------------
        % Matrix / Acq
        %------------------------------------------------------------------
        data_file.PixelBandwidth       = str2double( get_field_one( content, 'PixelBandwidth'       ) ) ; % Hz/pixel
        data_file.SliceThickness       = str2double( get_field_one( content, 'SliceThickness'       ) ) ; % millimeter
        data_file.SpacingBetweenSlices = str2double( get_field_one( content, 'SpacingBetweenSlices' ) ) ; % millimeter
        data_file.ProtocolSliceNumber  = str2double( get_field_one( content, 'CsaImage.ProtocolSliceNumber'                           ) ) ; % ?
        data_file.Rows                 = str2double( get_field_one( content, 'CsaSeries.MrPhoenixProtocol.sKSpace.lBaseResolution'    ) ) ;
        data_file.Columns              = str2double( get_field_one( content, 'CsaSeries.MrPhoenixProtocol.sKSpace.lPhaseEncodingLines') ) ;
        data_file.PixelSpacing         = cellfun( @str2double, get_field_mul( content, 'PixelSpacing') );
        switch data_file.MRAcquisitionType
            case '2D'
                data_file.Slices       = str2double( get_field_one( content, 'CsaSeries.MrPhoenixProtocol.sSliceArray.lSize'          ) ) ;
            case '3D'
                data_file.Slices       = str2double( get_field_one( content, 'CsaSeries.MrPhoenixProtocol.sKSpace.lImagesPerSlab'     ) ) ;
        end
        
        % iPat
        data_file.ParallelReductionFactorInPlane = str2double( get_field_one(content, 'CsaSeries.MrPhoenixProtocol.sPat.lAccelFactPE') );
        
        % MB factor
        MultibandAccelerationFactor = get_field_one(content, 'CsaSeries.MrPhoenixProtocol.sWipMemBlock.alFree\[13\]'); MultibandAccelerationFactor = str2double(MultibandAccelerationFactor);
        data_file.MultibandAccelerationFactor = MultibandAccelerationFactor;
        
        % EffectiveEchoSpacing & TotalReadoutTime
        ReconMatrixPE = str2double( get_field_one(content, 'NumberOfPhaseEncodingSteps') );
        data_file.NumberOfPhaseEncodingSteps = ReconMatrixPE;
        BWPPPE = str2double( get_field_one(content, 'CsaImage.BandwidthPerPixelPhaseEncode') );
        data_file.BandwidthPerPixelPhaseEncode = BWPPPE;
        data_file.EffectiveEchoSpacing = 1 / (BWPPPE * ReconMatrixPE); % SIEMENS
        data_file.TotalReadoutTime = data_file.EffectiveEchoSpacing * (ReconMatrixPE - 1); % FSL
        
        % Phase : encoding direction
        InPlanePhaseEncodingDirection = get_field_one(content, 'InPlanePhaseEncodingDirection');
        data_file.InPlanePhaseEncodingDirection = InPlanePhaseEncodingDirection;
        PhaseEncodingDirectionPositive = get_field_one(content, 'CsaImage.PhaseEncodingDirectionPositive'); PhaseEncodingDirectionPositive = str2double(PhaseEncodingDirectionPositive);
        data_file.PhaseEncodingDirectionPositive = PhaseEncodingDirectionPositive;
        switch InPlanePhaseEncodingDirection % InPlanePhaseEncodingDirection
            case 'COL'
                phase_dir = 'j';
            case 'ROW'
                phase_dir = 'i';
            otherwise
                warning('wtf ? InPlanePhaseEncodingDirection')
                phase_dir = '';
        end
        if PhaseEncodingDirectionPositive
            phase_dir = [phase_dir '-']; %#ok<AGROW>
        end
        data_file.PhaseEncodingDirection = phase_dir;
        
        data_file.PATMode     = str2double( get_field_one( content, 'CsaSeries.MrPhoenixProtocol.sPat.ucPATMode'     ) ) ;
        data_file.AccelFactPE = str2double( get_field_one( content, 'CsaSeries.MrPhoenixProtocol.sPat.lAccelFactPE'  ) ) ;
        data_file.AccelFact3D = str2double( get_field_one( content, 'CsaSeries.MrPhoenixProtocol.sPat.lAccelFact3D'  ) ) ;
        data_file.RefLinesP   = str2double( get_field_one( content, 'CsaSeries.MrPhoenixProtocol.sPat.lRefLinesP'    ) ) ;
        data_file.RefScanMode = str2double( get_field_one( content, 'CsaSeries.MrPhoenixProtocol.sPat.ucRefScanMode' ) ) ;
        
        data_file.SliceArrayMode           = str2double( get_field_one( content, 'CsaSeries.MrPhoenixProtocol.sSliceArray.ucMode'                    ) ) ;
        data_file.SliceArrayConcatenations = str2double( get_field_one( content, 'CsaSeries.SliceArrayConcatenations'                                ) ) ;
        data_file.PhysioECGScanWindow      = str2double( get_field_one( content, 'CsaSeries.MrPhoenixProtocol.sPhysioImaging.sPhysioECG.lScanWindow' ) ) ;
        
        data_file.Repetitions = str2double( get_field_one( content, 'CsaSeries.MrPhoenixProtocol.lRepetitions' ) ) ; % nVolumes ?
        
        %------------------------------------------------------------------
        % Coil
        %------------------------------------------------------------------
        data_file.ImaCoilString            =             get_field_one( content, 'CsaImage.ImaCoilString'                                                                        );
        data_file.CoilString               =             get_field_one( content, 'CsaSeries.CoilString'                                                                          );
        data_file.CoilStringForConversion  =             get_field_one( content, 'CsaSeries.MrPhoenixProtocol.sCoilSelectMeas.sCoilStringForConversion'                          );
        data_file.nRxCoilSelected          = str2double( get_field_one( content, 'CsaSeries.MrPhoenixProtocol.sCoilSelectMeas.aRxCoilSelectData\[0\].asList.__attribute__.size') );
        
        
    end % if RepetitionTime not empty
    
    
    %% Fetch all normal fields at first level
    
    tokens = regexp(content,'\n  "(\w+)": ([0-9.-]+)','tokens');
    for t = 1 : length(tokens)
        data_file.(tokens{t}{1}) = str2double(tokens{t}{2});
    end
    
    if j == 1
        data = data_file;
    else
        data(j) = data_file;
    end
    
end % j

end % function


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% function out = get_list( content, list )
%
% out = struct;
% for i = 1 : size(list,1)
%     out.(list{i,1}) = get_field_one(content, list{i,1});
%     if size(list,2) > 1
%         switch list{i,2}
%             case 'str'
%                 % pass
%             case 'num'
%                 out.(list{i,1}) = str2double(out.(list{i,1}));
%         end
%     end
% end
%
% end % function

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function result = get_field_one(content, regex)

% Fetch the line content
start = regexp(content           , regex, 'once');
stop  = regexp(content(start:end), ','  , 'once');
line = content(start:start+stop);
token = regexp(line, ': (.*),','tokens'); % extract the value from the line
if isempty(token)
    result = [];
else
    res = token{1}{1};
    if strcmp(res(1),'"')
        result = res(2:end-1); % remove " @ beguining and end
    else
        result = res;
    end
end

end % function

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function result = get_field_mul(content, regex)

% Fetch the line content
start = regexp(content           , regex, 'once');
idx1 = regexp(content(start:end),'[','once');
idx2 = regexp(content(start:end),',','once');
if idx1 < idx2
    stop  = regexp(content(start:end), ']'  , 'once');
else
    stop  = regexp(content(start:end), ','  , 'once');
end
line = content(start:start+stop);

if strfind(line(length(regex):end),'Csa') % in cas of single value, and not multiple ( such as signle B0 value for diff )
    stop  = regexp(content(start:end), ','  , 'once');
    line = content(start:start+stop);
end

token = regexp(line, ': (.*),','tokens'); % extract the value from the line
if isempty(token)
    result = [];
else
    res    = token{1}{1};
    VECT_cell_raw = strsplit(res,'\n')';
    if length(VECT_cell_raw)>1
        VECT_cell = VECT_cell_raw(2:end-1);
    else
        VECT_cell = VECT_cell_raw;
    end
    VECT_cell = strrep(VECT_cell,',','');
    VECT_cell = strrep(VECT_cell,' ','');
    result    = strrep(VECT_cell,'"','');
end

end % function

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
function result = get_field_mul_vect(content, regex)

% with Siemens product, [0,0,0] vectors are written as 'null'
% but 'null' is dirty, i prefrer real null vectors [0,0,0]
content_new = regexprep(content,'null',sprintf('[\n 0,\n 0,\n 0 \n]'));

% Fetch the line content
start = regexp(content_new           , regex, 'once');
stop  = regexp(content_new(start:end), '\]\s+\]'  , 'once');
line = content_new(start:start+stop+1);

if strfind(line(length(regex):end),'Csa') % in cas of single value, and not multiple ( such as signle B0 value for diff )
    stop  = regexp(content(start:end), '\],\s+"'  , 'once');
    line = content(start:start+stop);
end

VECT_cell_raw = strsplit(line,'\n')';

if length(VECT_cell_raw)>1
    VECT_cell = VECT_cell_raw(2:end-1);
else
    VECT_cell = VECT_cell_raw;
end
VECT_cell = strrep(VECT_cell,',','');
VECT_cell = strrep(VECT_cell,' ','');
VECT_cell = strrep(VECT_cell,'[','');
VECT_cell = strrep(VECT_cell,']','');
VECT_cell = VECT_cell(~cellfun(@isempty,VECT_cell));

v = str2double(VECT_cell);
result = reshape(v,[3 numel(v)/3]);

end % function

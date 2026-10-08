clc; clear all
%% LOAD AND CLEAN DEWE DATA
[file, path] = uigetfile('*.xlsx', 'Select the DEWE file');
if isequal(file,0) 
    return; 
end
dewe_matrix = readmatrix(fullfile(path, file), 'Sheet', 'Data1');

start_idx = find(dewe_matrix (3:end, 6) ~= 0, 1);

if isempty(start_idx)
    disp('No non-zero values found in column 6 from row 3.');
    return; 
end
start_idx = start_idx + 2;

dewe_trimmed_top = dewe_matrix(start_idx:end, :);

end_idx = find(dewe_trimmed_top(end:-1:1, 6) ~= 0, 1);

if isempty(end_idx)
    disp('No non-zero values found in column 6 from row 3.');
    return;
end

end_idx = size(dewe_trimmed_top, 1) - end_idx + 1;
dewe_clean = dewe_trimmed_top(1:end_idx, :);

% Clear temporary variables
clear dewe_trimmed_top file start_idx end_idx path 
%% LOAD EYE DATA
total_columns = 15; 

opts = spreadsheetImportOptions("NumVariables", total_columns);
opts.SelectedVariableNames = opts.VariableNames(1:total_columns);
opts.VariableTypes(:) = {'char'};
opts = setvaropts(opts, 1:total_columns, "WhitespaceRule", "preserve");
opts = setvaropts(opts, 1:total_columns, "EmptyFieldRule", "auto");

[file, path] = uigetfile('*.xlsx', 'Select the EYE file');

if isequal(file,0), return; end

eye_matrix = readtable(fullfile(path, file), opts, "UseExcel", false);

event_col = eye_matrix{:,3}; 

sync_on = find(strcmp(event_col, 'sync_on'), 1);
sync_off = find(strcmp(event_col, 'sync_off'), 1);

if isempty(sync_on) || isempty(sync_off)
    error('Sync events "sync_on" or "sync_off" not found.');
end

samples_between_sync = sync_off - sync_on + 1; 

fprintf("There are %d samples between 'sync_on' and 'sync_off'.\n", samples_between_sync);

% Clear temporary variables
clear event_col file opts path total_columns
%% FREQUENCY ADJUSTMENT
total_dewe_rows = length(dewe_clean);
reduction_factor = total_dewe_rows / samples_between_sync;
dewe_reduced = dewe_clean(1:reduction_factor:end, :);

% Clear temporary variables
clear total_dewe_rows samples_between_sync reduction_factor dewe_clean
%% MERGE WITH EYE TABLE
headers = string(["Time(s)_GPS","Steering","Speed","Throttle","Brake","INT","Longitude","Latitude","Velocity(km/h)","Direction(deg)","Distance(km)","SteeringAngle","DeltaV","Steering/VAR","Speed/VAR","Throttle/VAR","Brake/VAR"]);

dewe_str = string(dewe_reduced); 

[rows, cols] = size(dewe_str);
eye_total_rows = size(eye_matrix, 1);

empty_block = strings(eye_total_rows, cols);
empty_block(1, :) = headers;

empty_block(sync_on:sync_on+rows-1, :) = dewe_str;

eye_matrix(:, 16:15+cols) = array2table(empty_block);

if strlength(eye_matrix{sync_on, 16}) > 0 && strlength(eye_matrix{sync_off, 16}) > 0
    disp("✅ Data successfully integrated.");
else
    warning("⚠️ Missing information at row sync_on or sync_off in column 16.");
end

% Clear temporary variables
clear cols dewe_reduced dewe_str rows eye_total_rows new_headers empty_block
%% TRIM DATA TO THE SYNCHRONIZATION INTERVAL
eye_dewe_short = eye_matrix([1, sync_on:sync_off], :);

col_fix = table2cell(eye_dewe_short(:,4));
col_sac = table2cell(eye_dewe_short(:,9));

start_row = find((~cellfun(@isempty, col_fix(2:end)) | ~cellfun(@isempty, col_sac(2:end))), 1, 'first') + 1;

eye_dewe_short = eye_dewe_short([1, start_row:end], :);
sub_eye = eye_dewe_short(2:end, :);

new_matrix = cell(height(sub_eye), 2);
fix_counter = 1;
sac_counter = 1;

for i = 1:height(sub_eye)
    fix_id = sub_eye{i,4};
    fix_dur = sub_eye{i,7};
    sac_id = sub_eye{i,9};
    sac_dur = sub_eye{i,12};

    if ~isempty(fix_id) && ~strcmp(fix_id, '')
        new_matrix{i,1} = ['fix_' num2str(fix_counter)];
        new_matrix{i,2} = fix_dur;
        fix_counter = fix_counter + 1;
    elseif ~isempty(sac_id) && ~strcmp(sac_id, '')
        new_matrix{i,1} = ['sac_' num2str(sac_counter)];
        new_matrix{i,2} = sac_dur;
        sac_counter = sac_counter + 1;
    else
        new_matrix{i,1} = '';
        new_matrix{i,2} = '';
    end
end

for i = 2:size(new_matrix,1)
    if isempty(new_matrix{i,1})
        new_matrix{i,1} = new_matrix{i-1,1};
        new_matrix{i,2} = new_matrix{i-1,2};
    end
end

eye_dewe_short(2:end, 4) = cell2table(new_matrix(:,1));
eye_dewe_short(2:end, 5) = cell2table(new_matrix(:,2));

eye_dewe_short{1,1}  = {'Timestamp Eyetracking'};
eye_dewe_short{1,4}  = {'id'};
eye_dewe_short{1,5}  = {'id_value'};

eye_dewe_short(:,27:32) = []; 
eye_dewe_short(:,24:25) = []; 
eye_dewe_short(:,21) = []; 
eye_dewe_short(:, 6:13) = []; 
eye_dewe_short(:,2) = []; 

% Clear temporary variables
clear col_fix col_sac start_row sub_eye new_matrix fix_counter sac_counter fix_dur fix_id headers i sac_dur sac_id sync_off sync_on
%% GENERATE MUSIC-CONDITION LABELS
col_events = table2cell(eye_dewe_short(:,2));

idx_music_on  = find(strcmp(col_events, 'music_on'), 1);
idx_music_off = find(strcmp(col_events, 'music_off'), 1);

music_status = repmat({''}, height(eye_dewe_short), 1);

music_status(2:idx_music_on-1) = {'OFF'};  
music_status(idx_music_on:idx_music_off) = {'ON'};
music_status(idx_music_off+1:end) = {'OFF'};
music_status{1} = 'music';

eye_dewe_short_music = [eye_dewe_short(:,1), eye_dewe_short(:,2), cell2table(music_status), eye_dewe_short(:,3:end)];

% Clear temporary variables
clear col_events idx_music_off idx_music_on music_status
%% INSERT HEART-RATE DATA
[file, path] = uigetfile('*.tcx', 'Select the HR file');

if isequal(file,0), return; end

fullpath = fullfile(path, file);
HR_matrix = xmlread(fullpath);

root = HR_matrix.getDocumentElement();
allTrackpoints = root.getElementsByTagName('Trackpoint');

heartrates = [];

for i = 0:allTrackpoints.getLength-1
    tp = allTrackpoints.item(i);

    hrNode = tp.getElementsByTagName('HeartRateBpm');

    if hrNode.getLength > 0
        valueNode = hrNode.item(0).getElementsByTagName('Value');
        if valueNode.getLength > 0
            heartrates(end+1,1) = str2double(char(valueNode.item(0).getTextContent));
        else
            heartrates(end+1,1) = NaN;
        end
    else
        heartrates(end+1,1) = NaN;
    end
end

disp('✅ Heart-rate data imported successfully.');

% Clear temporary variables
clear allTrackpoints file fullpath HR_matrix hr_table hrNode i path root timeNode timestamps tp valueNode
%% RESAMPLE HEART-RATE DATA

factor = 200 / 0.2;  

nan_start = find(~isnan(heartrates), 1, 'first');
nan_end   = find(~isnan(heartrates), 1, 'last');

if nan_start > 1 || nan_end < length(heartrates)
    heartrates = heartrates(nan_start:nan_end);
    disp('🧹 NaNs removed from the beginning or end of heart-rate data.');
else
    disp('✅ No NaNs found at the beginning or end of heart-rate data.');
end

expanded_hr = repelem(heartrates, factor);

n_rows = height(eye_dewe_short_music);

if length(expanded_hr) > n_rows
    expanded_hr = expanded_hr(1:n_rows);
    disp('🔔 Heart-rate data truncated to match the target table length.');
else
    disp('✅ Heart-rate data length is within the target table length.');
end

% Clear temporary variables
clear factor n_rows 
%% INSERT HEART-RATE DATA
hr_start_idx = find(strcmp(eye_dewe_short_music{:,2}, 'HR_start'), 1, 'first');

if isempty(hr_start_idx)
    error('HR_start not found in column 2.');
end

eye_dewe_short_music_HR = [eye_dewe_short_music(1,:); eye_dewe_short_music(hr_start_idx:end,:)];
disp(['✅ Table truncated from row ' num2str(hr_start_idx) ' (HR_start) to the end, preserving the header.']);

expanded_hr_cell = num2cell(expanded_hr);
expanded_hr_cell = [{'HeartRate'}; expanded_hr_cell];

n_rows_target = height(eye_dewe_short_music_HR);

if length(expanded_hr_cell) > n_rows_target
    expanded_hr_cell = expanded_hr_cell(1:n_rows_target);
    disp('🔪 Heart-rate data truncated to match the target table.');
elseif length(expanded_hr_cell) < n_rows_target
    expanded_hr_cell(end+1:n_rows_target) = {NaN};
    disp('➕ Heart-rate data padded with NaN values.');
else
    disp('✅ Heart-rate data matches the target table length.');
end

eye_dewe_short_music_HR(:,2) = cell2table(expanded_hr_cell);

% Clear temporary variables
clear heartrates expanded_hr expanded_hr_cell hr_start_idx n_rows_target nan_end nan_start
%% RENUMBER FIXATION AND SACCADE IDENTIFIERS
id_col = eye_dewe_short_music_HR{:,4};

fix_map = containers.Map();
sac_map = containers.Map();

fix_counter = 1;
sac_counter = 1;

for i = 2:height(eye_dewe_short_music_HR)
    val = id_col{i};
    if ischar(val) || isstring(val)
        if startsWith(val, 'fix_')
            if ~isKey(fix_map, val)
                fix_map(val) = ['fix_' num2str(fix_counter)];
                fix_counter = fix_counter + 1;
            end
            id_col{i} = fix_map(val);
        elseif startsWith(val, 'sac_')
            if ~isKey(sac_map, val)
                sac_map(val) = ['sac_' num2str(sac_counter)];
                sac_counter = sac_counter + 1;
            end
            id_col{i} = sac_map(val);
        end
    end
end

eye_dewe_short_music_HR(:,4) = cell2table(id_col);

disp('🔁 Fixation and saccade identifiers renumbered.');

% Clear temporary variables
clear fix_counter fix_map fname fpath i id_col sac_counter sac_map val
%% EXPORT TO CSV
[fname, fpath] = uiputfile('*.csv', 'Save file as');
if fname ~= 0
    writetable(eye_dewe_short_music_HR, fullfile(fpath, fname), 'WriteVariableNames', false, 'Delimiter', ';');
end

disp('Data successfully saved to CSV.');

function [data, out] = get_owon_data(os)
%% Function to get 
% This is only as a guide. For multiple channels, modify the following code
% 
[data.sample_rate, chs_disp]= get_sample_rate(os);
%% 
% Counter and Preallocation
current_len = 0;
% OBS: Check always your InputBufferSize
step_len = 50000; % Test your step. The max data length that the device reads per time is 256k
if step_len > os.InputBufferSize/2-50
    step_len = os.InputBufferSize/2-50;
end
total_len = 10e6;  % Manual set from the DEPMEM query
data.points = nan(total_len,sum(chs_disp));
%%
if isequal(chs_disp,[1 0]) || isequal(chs_disp,[1 1])
    str_command = ':WAV:BEG CH1';
else
    str_command = ':WAV:BEG CH2';
end
fprintf(os, str_command);
fprintf(os, '*WAI');
% The read data by one time is #9000001024XXXX: among which, 9 indicates the bytes quantity,
% 000001024 describes the length of the waveform (input signal) data, say, 1024 bytes. The value of N
% calculated by introducing 2 functions: "partial string" and "decimal numeric string to numeric conversion".
fprintf(os, ':WAV:PRE?');
fprintf(os, '*WAI');
%% 
% Can't read it correctly. From the NI I/O Trace, I'm getting 1035 bytes
% binblockread works, but what's the correct format... int16, char? 
out = fscanf(os, '%c'); 
% out = binblockread(os, 'char');
fprintf(os, '*WAI');
%%
% Data loop
try
    while current_len < total_len
    str_range_command = sprintf(':WAV:RANG %d,%d',current_len, step_len);
    fprintf(os, str_range_command);
    fprintf(os, '*WAI');
    fprintf(os, ':WAV:FETC?');
    fprintf(os, '*WAI');
    % The read data consists of two parts - TMC header and data packet, like #900000ddddXXXX..., among
    % which, dddd reflects the length of the valid data packet in the data stream, XXXX... indicates the data
    % from the data packet, every 2 bytes forms one effective data, to be 16-bit signed integer data
    data.points(current_len+1:current_len+step_len,1) = binblockread(os, 'int16');
    % DUAL channel status
        if isequal(chs_disp,[1 1])
            str_beg_command = ':WAV:BEG CH2';
            fprintf(os, str_beg_command);
            fprintf(os, str_range_command);
            fprintf(os, '*WAI');
            fprintf(os, ':WAV:FETC?');
            fprintf(os, '*WAI');
            data.points(current_len+1:current_len+step_len,2) = binblockread(os, 'int16');
            str_beg_command = ':WAV:BEG CH1';
            fprintf(os, str_beg_command);
        end
    current_len = current_len + step_len;
    end
catch ME
    % Sometimes there's no an effective
    % data-packet read within the loop
    fprintf(os, ':WAV:END');
    fprintf(os, '*WAI');
    fclose(os);
    rethrow(ME);
end
%%
fprintf(os, ':WAV:END');
end
%%
function [sample, chs_status] = get_sample_rate(os)
%% MAPs
map = get_config_map_owon();
%% Query instrument
% Ch Status
ch1stat = query(os, ':CH1:DISP?'); chs2stat = query(os, ':CH2:DISP?');
if strcmp(strcat(ch1stat), 'ON->') && strcmp(strcat(chs2stat), 'ON->')
    CH_status = 'dual'; chs_status = [1 1];
elseif strcmp(strcat(ch1stat), 'OFF->') && strcmp(strcat(chs2stat), 'OFF->')
    warning('All channels OFF... Turning ON CH1')
    fprintf(os, ':CH1:DISP ON');
    CH_status = 'single'; chs_status = [1 0];
elseif strcmp(strcat(ch1stat), 'ON->') && strcmp(strcat(chs2stat), 'OFF->')
    CH_status = 'single'; chs_status = [1 0];
elseif strcmp(strcat(ch1stat), 'OFF->') && strcmp(strcat(chs2stat), 'ON->')
    CH_status = 'single'; chs_status = [0 1];
end
% Timebase
tbase = query(os, ':HORI:SCAL?');
% Depth mem
depmem = query(os, ':ACQ:DEPMEM?');
%% Sample struct output
maxRate = map.maxrate(CH_status);
samplePts = map.samplepts(strcat(depmem));
timebase = map.timebase(strcat(tbase));
% Sample rule
if maxRate > samplePts/timebase
    sample = samplePts/timebase;
else
    sample = maxRate;
end
end
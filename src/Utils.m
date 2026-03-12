classdef Utils
    methods (Static)

        %% Unpack track CSV into struct
        function [track] = unpackTrack(filepath)
            track_data = readtable(filepath);
            track.x = track_data.x;
            track.y = track_data.y;
            track.R = track_data.R;
        end

        %% Read Torque Curve from filepath
        function car = load_torque_curve(car)
            % Check if the filepath exists in the struct
            if ~isfield(car, 'ptrain_data_filepath')
                error('The car struct must contain a "ptrain_data_filepath" field.');
            end
        
            ptrain_data = readtable(car.ptrain_data_filepath);
            rpm_for = ptrain_data.RPM;
            
            if mean(rpm_for) < 1000
                rpm_for = rpm_for .* 1000;
            end
            
            T = ptrain_data.Torque_Nm;  
            
            car.engine_speed = rpm_for;
            car.engine_torque = T;
        end


        %% Generate Straight line track
        function track = create_straight_track(length_m, step_m)
            x_pts = 0:step_m:length_m;
            
            % Catch edge case: if step_m doesn't divide perfectly into length_m, 
            % append the exact final length to cap off the track
            if x_pts(end) < length_m
                x_pts = [x_pts, length_m];
            end
            
            y_pts = zeros(size(x_pts));
            
            % Generate Radius of Curvature (R) array
            R_pts = 10000 * ones(size(x_pts));
          
            track.x = x_pts(:);
            track.y = y_pts(:);
            track.R = R_pts(:);
        end
        

        %% Parse i2 Log files
        function log_data = parse_motec_csv(filepath)
            % PARSE_MOTEC_CSV Reads a MoTeC exported CSV and extracts lap sim validation data.
            
            % fprintf('Parsing MoTeC log file: %s...\n', filepath);
        
            opts = detectImportOptions(filepath, 'NumHeaderLines', 14);
            opts.VariableNamingRule = 'preserve'; % Keep exact names to search later
            opts.DataLines = [19, Inf];           % Skip the units row and blank rows
            
            % Read the actual numerical data
            try
                raw_table = readtable(filepath, opts);
            catch
                error('Could not read CSV. Check that it is a valid MoTeC export.');
            end
            vars = raw_table.Properties.VariableNames;
            
            dist_col = Utils.get_first_match(vars, {'Distance', 'Dist'});
            lat_col  = Utils.get_first_match(vars, {'Lateral Acceleration', 'Lat G', 'G Force Lat', 'Lat_G'});
            long_col = Utils.get_first_match(vars, {'Longitudonal', 'Longitudinal', 'Long G', 'G Force Long', 'Long_G'});
            
            log_data.distance = raw_table{:, dist_col};
            log_data.lat_g    = raw_table{:, lat_col};
            log_data.long_g   = raw_table{:, long_col};
            
            try
                speed_col = Utils.get_first_match(vars, {'Vehicle Speed', 'GPS_Speed', 'Speed'});
                log_data.speed = raw_table{:, speed_col};
            catch
                % Speed not found, ignore
            end
            
            % 5. Clean up missing data (Remove NaNs/blanks from the very end of the log)
            valid_idx = ~isnan(log_data.distance) & ~isnan(log_data.lat_g);
            log_data.distance = log_data.distance(valid_idx);
            log_data.lat_g    = log_data.lat_g(valid_idx);
            log_data.long_g   = log_data.long_g(valid_idx);
            
            if isfield(log_data, 'speed')
                log_data.speed = log_data.speed(valid_idx);
            end
        
            % fprintf('Log successfully parsed.\n');
        end
        
        %% Local Helper Function for Keyword Matching
        function col_name = get_first_match(vars, search_terms)
            for i = 1:length(search_terms)
                % Search through the table variable names for the keyword
                idx = find(contains(vars, search_terms{i}, 'IgnoreCase', true), 1, 'first');
                if ~isempty(idx)
                    col_name = vars{idx};
                    return;
                end
            end
            error('Could not find column matching any of: %s', strjoin(search_terms, ', '));
        end

        %% Update Parallel loop load bar
        function updateWaitbar(data, h, total)
            persistent count
            
            % Check for the reset signal
            if ischar(data) && strcmp(data, 'reset')
                count = 0;
                return; % Exit the function early
            end
            
            if isempty(count)
                count = 0;
            end
            
            % Standard update behavior
            count = count + 1;
            waitbar(count / total, h, sprintf('Simulating: %d / %d', count, total));
        end


        %% Export Sim results to excel sheet
        function save_sim_results(results, filepath, sheet_name)
            % SAVE_SIM_RESULTS Separates data, scalars, and mismatched arrays safely 
            
        % 1. Initialize storage
            fields = fieldnames(results);
            summary_data = {'Parameter', 'Value'}; 
            array_struct = struct();               
            
            % Get the master length of the telemetry data 
            % (We know 'dist' will always be the correct track length)
            N_telemetry = length(results.dist);
            
            % 2. Dynamically sort the data
            for i = 1:length(fields)
                fname = fields{i};
                val = results.(fname);
        
                if isnumeric(val) && ~isinteger(val)
                    val = round(val, 3);
                end
                
                % Check if it's a numeric array that perfectly matches the telemetry length
                if isnumeric(val) && (numel(val) == N_telemetry)
                    array_struct.(fname) = val(:); % Force into column vector
                else
                    % It is a scalar, string, empty array, or mismatched array.
                    % Convert mismatched numeric arrays to a string so Excel accepts them in one cell
                    if isnumeric(val) || islogical(val)
                        if numel(val) > 1
                            val = mat2str(val); % e.g., turns [1 2 3] into "[1 2 3]"
                        elseif isempty(val)
                            val = '[]';
                        end
                    end
                    
                    % Add to the summary column
                    summary_data(end+1, :) = {fname, val}; %#ok<AGROW>
                end
            end
            
            % 3. Write Summary Data to columns A and B
            writecell(summary_data, filepath, 'Sheet', sheet_name, 'Range', 'A1');
            
            % 4. Write Telemetry Data to column D
            data_table = struct2table(array_struct);
            writetable(data_table, filepath, 'Sheet', sheet_name, 'Range', 'D1');
            
            % Auto-adjust column widths (Optional Windows COM server trick)
            try
                excel = actxserver('Excel.Application');filename
                workbook = excel.Workbooks.Open(fullfile(pwd, filepath));
                sheet = workbook.Sheets.Item(sheet_name);
                sheet.Columns.AutoFit;
                workbook.Save;
                workbook.Close;
                excel.Quit;
            catch
                % Fails gracefully
            end 
        end


        %% Calculates Energy used during idle
        function energy_used = calculate_energy_used(power_usage, time_idling)
            energy_used = power_usage * time_idling;
        end


        %% Calculate fuel liters used
        function liters_used = energy_to_fuel_volume(fuel_specs, energy_used_joules)
            if ~isfield(fuel_specs, 'energy_density')
                error('Fuel specs not found.');
            end
            
            % Calculate fuel volume
            liters_used = energy_used_joules / fuel_specs.energy_density;
        end


        %% Convert one lap of endurance to full endurance
        function [corr_lap_time, tot_energy_used, tot_fuel_used] = process_endurance_results(car, results, num_laps, pace_factor, cones, idle_time)
            % Corr lap time
            ideal_time = results.lap_time * num_laps;
            time_driving = ideal_time * pace_factor;

            corr_lap_time =  time_driving + (cones * 2.0);

            % Total fuel used
            ideal_energy_used = results.energy_used * num_laps;
        
            % account for time lost and time spent idling
            extra_time = (time_driving - ideal_time) + idle_time;
            
            non_driving_energy = Utils.calculate_energy_used(car.idle_power_usage, extra_time);

            tot_energy_used = ideal_energy_used + non_driving_energy;
            tot_fuel_used = Utils.energy_to_fuel_volume(car.fuel, tot_energy_used);
        end
    end
end
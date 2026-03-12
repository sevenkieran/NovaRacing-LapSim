clear; close all;

%% Simulation Configuration
% Events to run
config.RunAccelSim = true;
config.RunSkidpadSim = true;
config.RunEnduranceSim = true;
config.RunAutocrossSim = true;

%% Load Car Model
car = Default_car();

%% Tracks
track.accel.distance = 75; % m
track.autocross.filepath = "Tracks/2025 Autocross_Open_Forward.csv";
track.skidpad.filepath   = "Tracks/FSAE_Skidpad_Track";
track.Endurance.filepath = "Tracks/2025 Endurance_Closed_Forward.csv";


track.Endurance.num_laps = 10;
% pace factor is applied to total lap time to account for driver inconsistency
track.Endurance.pace_factor = 1.1;
track.Endurance.cone_penalties = 2;
track.Endurance.idle_time = 150; % s in endurance spent idling


%% Sweep setup
sweeps = struct();
idx = 0;

% idx = idx+1;
% sweeps(idx).name = 'car_mass';
% sweeps(idx).values = 200:1:218;

% idx = idx+1;
% sweeps(idx).name = 'power_scalar';
% sweeps(idx).values = 0.7:0.1:1.5;

idx = idx+1;
sweeps(idx).name = 'drag_scale';
sweeps(idx).values = 0.5:0.1:2.5;

idx = idx+1;
sweeps(idx).name = 'downforce_scale';
sweeps(idx).values = 0.5:0.5:2.5;

% idx = idx+1;
% sweeps(idx).name = 'h_cg';
% sweeps(idx).values = 0.25:0.01:0.4;

% idx = idx+1;
% sweeps(idx).name = 'shift_time';
% sweeps(idx).values = 0.08:0.01:.2;

% idx = idx+1;
% sweeps(idx).name = 'CoP';
% sweeps(idx).values = 0.4:0.01:0.6;


%% Points Setup
Points.Accel.tmin = 4.169;
Points.Skidpad.tmin = 5.08;
Points.Autocross.tmin = 48.878;
Points.Endurance.tmin = 1295.297;

% Efficiency setup
Points.Efficiency.tmin = 129.53; % s
Points.Efficiency.min_CO2_per_lap = 0.5534; % kg
Points.Efficiency.max_CO2_per_lap = 1.3214; % kg
Points.Efficiency.min_eff_factor = 0.289;
Points.Efficiency.max_eff_factor = 0.815;


%% Plot Config
config.plotSensitivity = true;
config.plotPoints = true;


%% Event Specific Settings
% Accel
config.accel.distance = 75; % [m] length of straight






%%%%%%%%%%%%%%%%%%% End Set up %%%%%%%%%%%%%%%%%%%%%%%%
%% Initialize base car
car = Utils.load_torque_curve(car);
car = load_fuelSpecs(car);


%% Sweep Logic
param_names = {sweeps.name};
param_values = {sweeps.values};

grids = cell(1, numel(param_values));
[grids{:}] = ndgrid(param_values{:});

% Flatten the grids
param_combinations = cellfun(@(x) x(:), grids, 'UniformOutput', false);
design_matrix = [param_combinations{:}]; 

num_sims = size(design_matrix, 1);
num_params = length(param_names);

%% Parallel Setup
fprintf('Queueing %d simulations for %d parameters...\n', num_sims, num_params);

if isempty(gcp('nocreate'))
    parpool; % Starts the default cluster (usually equal to # of CPU cores)
end

% Preallocate arrays for Raw Metrics
accel_results = zeros(num_sims, 1);
skid_results  = zeros(num_sims, 1);
autox_results = zeros(num_sims, 1);
endur_raw     = zeros(num_sims, 1);
endur_corr    = zeros(num_sims, 1);
fuel_used     = zeros(num_sims, 1);

% Preallocate arrays for Points
pts_accel     = zeros(num_sims, 1);
pts_skidpad   = zeros(num_sims, 1);
pts_autox     = zeros(num_sims, 1);
pts_endur     = zeros(num_sims, 1);
pts_eff       = zeros(num_sims, 1);
pts_total     = zeros(num_sims, 1);

D = parallel.pool.DataQueue;
h = waitbar(0, 'Starting Parallel Sim...');
afterEach(D, @(x) Utils.updateWaitbar(x, h, num_sims));
N_done = 0; % Counter for the callback

Utils.updateWaitbar('reset', h, num_sims);
timer_start = tic;

%% Unpack tracks
track.accel = Utils.create_straight_track(track.accel.distance, 0.5);
track.skidpad = Utils.unpackTrack(track.skidpad.filepath);
track.autocross = Utils.unpackTrack(track.autocross.filepath);
track.endurance = Utils.unpackTrack(track.Endurance.filepath);

track.endurance.num_laps = track.Endurance.num_laps;
track.endurance.pace_factor = track.Endurance.pace_factor;
track.endurance.cone_penalties = track.Endurance.cone_penalties;
track.endurance.idle_time = track.Endurance.idle_time;

points_calc = FsaePointsCalculator(Points, track.endurance.num_laps);

%% Base run
base_results = sim_runner(car, config, track);

%% 4. The Batch Loop
%% The Batch Loop
parfor i = 1:num_sims
    temp_car = car; 
    
    % 1. Apply Swept Parameters
    current_params = design_matrix(i, :);
    for p = 1:num_params
        field_name = param_names{p};
        temp_car.(field_name) = current_params(p);
    end
    
    % Run Simulation
    sim_res = sim_runner(temp_car, config, track);
    
    % Calculate Points
    run_pts = points_calc.calculate_all_scores(sim_res, temp_car.fuel.conversion_factor);
    
    % 4. Store Raw Lap Times & Fuel
    accel_results(i) = sim_res.accel_time;
    skid_results(i)  = sim_res.skidpad_time;
    autox_results(i) = sim_res.autocross_time;
    endur_raw(i)     = sim_res.endurance_time;
    
    % 5. Store Points
    pts_accel(i)   = run_pts.accel;
    pts_skidpad(i) = run_pts.skidpad;
    pts_autox(i)   = run_pts.autox;
    pts_endur(i)   = run_pts.endurance;
    pts_eff(i)     = run_pts.efficiency_score;
    pts_total(i)   = run_pts.total;

    % Handle fields that might not exist if Endurance was toggled off
    if isfield(sim_res, 'endurance_corr_time')
        endur_corr(i) = sim_res.endurance_corr_time;
        fuel_used(i)  = sim_res.endurance_fuel_used;
    end
    
    % 6. Update Progress
    send(D, 1); 
end
close(h);
fprintf('Parallel Run Complete in %.2f seconds.\n', toc(timer_start));

%% Compile Results Table
results = array2table(design_matrix, 'VariableNames', param_names);

% Add Lap Times
results.AccelTime = accel_results;
results.SkidpadTime = skid_results;
results.AutocrossTime = autox_results;
results.EnduranceRawTime = endur_raw;
results.EnduranceCorrTime = endur_corr;
results.FuelUsed = fuel_used;

% Add Points
results.PtsAccel = pts_accel;
results.PtsSkidpad = pts_skidpad;
results.PtsAutox = pts_autox;
results.PtsEndurance = pts_endur;
results.PtsEfficiency = pts_eff;
results.TotalPoints = pts_total;

% Sort by highest Total Points to find the best configuration
results = sortrows(results, 'TotalPoints', 'descend');

%% Display Results
disp('Top 5 Configurations (By Total Points):');
disp(results(1:min(5, height(results)), :));

%% Calculate and Display Sensitivities
disp(' ');

% Ensure base points are calculated so we have a baseline for the Points sensitivity
if ~exist('base_pts', 'var')
    base_pts = points_calc.calculate_all_scores(base_results, car.fuel.conversion_factor);
end


%% Calculate and Display Sensitivities (Trade Rates)
disp(' ');
% Ensure base points are calculated so we have a baseline for the Points sensitivity
if ~exist('base_pts', 'var')
    base_pts = points_calc.calculate_all_scores(base_results, car.fuel.conversion_factor);
end

% Map: {Base Value, Table Column Name, Display Name}
metrics_map = {
    base_pts.accel,             'PtsAccel',      'Accel Points';
    base_pts.skidpad,           'PtsSkidpad',    'Skidpad Points';
    base_pts.autox,             'PtsAutox',      'Autox Points';
    base_pts.endurance,         'PtsEndurance',  'Endur Points';
    base_pts.efficiency_score,  'PtsEfficiency', 'Eff Points';
    base_pts.total,             'TotalPoints',   'Total Points'
};

num_metrics = size(metrics_map, 1);

% Define specific engineering increments for Trade Rates
% This maps the parameter to a realistic, favorable change
trade_config = struct();
trade_config.car_mass.increment = -1;      % 1 kg drop
trade_config.car_mass.label = '1 kg drop';

trade_config.power_scalar.increment = 0.05;  % 5% power bump
trade_config.power_scalar.label = '5% power bump';

trade_config.drag_scale.increment = -0.05;   % 5% drag reduction
trade_config.drag_scale.label = '5% drag reduction';

trade_config.downforce_scale.increment = 0.05; % 5% downforce bump
trade_config.downforce_scale.label = '5% downforce bump';

trade_config.h_cg.increment = -0.01;
trade_config.h_cg.label = "10mm CoG drop";

trade_config.shift_time.increment = -0.01;
trade_config.shift_time.label = "10ms shift time drop";

trade_config.CoP.increment = 0.01;
trade_config.CoP.label = "1% CoP movement to front";

for p = 1:num_params
    p_name = param_names{p};
    
    % Get base value of the parameter
    if isfield(car, p_name)
        x_base = car.(p_name);
    else
        x_base = median(results.(p_name)); 
    end
    
    % Absolute change in the input parameter (X)
    x_delta = results.(p_name) - x_base;
    
    % Skip if parameter was static
    if max(x_delta) - min(x_delta) < 1e-6
        continue;
    end
    
    % Lookup the target increment from our config, or use a default
    if isfield(trade_config, p_name)
        inc_val = trade_config.(p_name).increment;
        inc_label = trade_config.(p_name).label;
    else
        inc_val = 1; 
        inc_label = '1 unit change';
    end
    
    fprintf('\nParameter: **%s** (Base Value: %.2f)\n', p_name, x_base);
    fprintf('Trade Rate for a %s:\n', inc_label);
    
    for m = 1:num_metrics
        y_base = metrics_map{m, 1};
        table_col = metrics_map{m, 2};
        display_name = metrics_map{m, 3};
        
        % Check if the event was actually run 
        if y_base == 0 || isnan(y_base)
            continue; 
        end
        
        % Calculate absolute change in the output metric (Y)
        y_delta = results.(table_col) - y_base;
        
        % Linear fit to find the slope (Delta Y / Delta X)
        fit_coeffs = polyfit(x_delta, y_delta, 1);
        slope = fit_coeffs(1);
        
        % Calculate the specific impact for our targeted increment
        impact = slope * inc_val;
        
        % Format the output string with appropriate units
        if contains(table_col, 'Time')
            unit_str = 'sec';
        else
            unit_str = 'pts';
        end
        
        % Highlight Total Points to make it stand out
        if strcmp(table_col, 'TotalPoints')
            fprintf('  --------------------------------------------------------\n');
            fprintf('  %12s: %+.3f %s\n', 'TOTAL SCORE', impact, unit_str);
            fprintf('  --------------------------------------------------------\n');
        else
            fprintf('  %12s: %+.3f %s\n', display_name, impact, unit_str);
        end
    end
end
disp('--------------------------------------------------------------');


% Map: {Base Value, Table Column Name, Display Name}
metrics_map = {
    base_results.accel_time,          'AccelTime',         'Accel Time';
    base_results.skidpad_time,        'SkidpadTime',       'Skidpad Time';
    base_results.autocross_time,      'AutocrossTime',     'Autox Time';
    base_results.endurance_corr_time, 'EnduranceCorrTime', 'Endur Time';
    base_pts.efficiency_score,        'PtsEfficiency',     'Eff Points';
    base_pts.total,                   'TotalPoints',       'Total Points'
};

num_metrics = size(metrics_map, 1);


for p = 1:num_params
    p_name = param_names{p};

    % Get base value of the parameter from the default car
    if isfield(car, p_name)
        x_base = car.(p_name);
    else
        % Fallback if the field isn't in the base car struct
        x_base = median(results.(p_name)); 
    end

    % Calculate percentage change in the input parameter (X)
    x_pct_change = (results.(p_name) - x_base) ./ x_base * 100;

    % Skip if parameter was static (to avoid dividing by zero)
    if max(x_pct_change) - min(x_pct_change) < 1e-6
        continue;
    end

    fprintf('\nParameter: **%s** (Base Value: %.2f)\n', p_name, x_base);

    time_sensitivities = []; % Initialize array to hold just the time sensitivities

    for m = 1:num_metrics
        y_base = metrics_map{m, 1};
        table_col = metrics_map{m, 2};
        display_name = metrics_map{m, 3};

        % Check if the event was actually run 
        if y_base == 0 || isnan(y_base)
            continue; 
        end

        % Calculate percentage change in the output metric (Y)
        y_pct_change = (results.(table_col) - y_base) ./ y_base * 100;

        % Linear fit to find the sensitivity (% output / % input)
        fit_coeffs = polyfit(x_pct_change, y_pct_change, 1);
        sensitivity = fit_coeffs(1);

        % Format the output string
        fprintf('  %12s: a 1%% change results in a %+.4f%% change.\n', display_name, sensitivity);

        % Group the lap time sensitivities to calculate an average
        if ~strcmp(table_col, 'TotalPoints')
            time_sensitivities(end+1) = sensitivity;
        end
    end

    % Print the average time sensitivity for this specific parameter
    if ~isempty(time_sensitivities)
        fprintf('  --------------------------------------------------------\n');
        fprintf('  %12s: a 1%% change results in a %+.4f%% change.\n', 'Avg Lap Time', mean(time_sensitivities));
    end
end
disp('--------------------------------------------------------------');

%% Plot Points vs. Sweep Value (1D Sweep Only)
if num_params == 1 && config.plotSensitivity
    p_name = param_names{1};
    
    % Re-sort the data by the swept parameter to ensure clean, continuous lines
    plot_data = sortrows(results, p_name, 'ascend');
    x_vals = plot_data.(p_name);
    clean_p_name = strrep(p_name, '_', ' '); 
    
    figure('Name', sprintf('Points vs %s', clean_p_name), 'Color', 'w');
    
    % --- Left Axis: Individual Events ---
    yyaxis left
    hold on; grid on;
    
    color_accel = [0.8500, 0.3250, 0.0980]; % Orange/Red
    color_skid  = [0.4660, 0.6740, 0.1880]; % Green
    color_autox = [0.0000, 0.4470, 0.7410]; % Blue
    color_endur = [0.4940, 0.1840, 0.5560]; % Purple
    color_eff   = [0.9290, 0.6940, 0.1250]; % Yellow/Gold
    
    % Plot each event with distinct, explicitly defined colors
    plot(x_vals, plot_data.PtsAccel, 'Color', color_accel, 'LineWidth', 2, 'DisplayName', 'Accel');
    plot(x_vals, plot_data.PtsSkidpad, 'Color', color_skid, 'LineWidth', 2, 'DisplayName', 'Skidpad');
    plot(x_vals, plot_data.PtsAutox, 'Color', color_autox, 'LineWidth', 2, 'DisplayName', 'Autox');
    plot(x_vals, plot_data.PtsEndurance, 'Color', color_endur, 'LineWidth', 2, 'DisplayName', 'Endurance');
    plot(x_vals, plot_data.PtsEfficiency, 'Color', color_eff, 'LineWidth', 2, 'DisplayName', 'Efficiency');
    
    ylabel('Individual Event Points');
    % Adjust Y-limits slightly so lines don't ride the absolute bottom of the plot
    ylim([20, max(plot_data.PtsEndurance)*1.1]); 
    
    % --- Right Axis: Total Points ---
    yyaxis right
    % Use a thick black line to make the master trend stand out
    plot(x_vals, plot_data.TotalPoints, 'k-', 'LineWidth', 3, 'DisplayName', 'Total Points');
    ylabel('Total Dynamic Points', 'color', 'k');
    
    % Ensure the right axis isn't squashed
    % ylim([min(plot_data.TotalPoints)*0.95, max(plot_data.TotalPoints)*1.05]);
    ylim([400, 675]);
       
    
    title(sprintf('Points vs %s', clean_p_name));
    xlabel(clean_p_name);
    
    % Format the legend into two columns so it doesn't block the data
    legend('Location', 'best', 'NumColumns', 2);
    
    hold off;
%% Plot 2D Contour for Two Swept Parameters
elseif num_params == 2 && config.plotSensitivity
    p1_name = param_names{1};
    p2_name = param_names{2};
    
    % Extract unique swept values to create the axes
    x_vals = unique(results.(p1_name));
    y_vals = unique(results.(p2_name));
    [X, Y] = meshgrid(x_vals, y_vals);
    
    % Interpolate the Total Points data back onto the 2D grid
    % (This works perfectly even though the results table is sorted by points)
    Z_pts = griddata(results.(p1_name), results.(p2_name), results.TotalPoints, X, Y);
    
    % Create the figure
    figure('Name', sprintf('2D Sensitivity: %s vs %s', p1_name, p2_name), 'Color', 'w');
    
    % Plot the filled contour map (30 levels for smooth gradients)
    contourf(X, Y, Z_pts, 30, 'LineStyle', 'none');
    hold on;
    
    % Overlay solid black contour lines to make it easy to read specific point values
    contour(X, Y, Z_pts, 10, 'k-', 'LineWidth', 0.5);
    
    % Find the absolute best configuration from the results table
    [max_pts, max_idx] = max(results.TotalPoints);
    opt_x = results.(p1_name)(max_idx);
    opt_y = results.(p2_name)(max_idx);
    
    % Plot base car
    if isfield(car, p1_name), base_x = car.(p1_name); else, base_x = median(results.(p1_name)); end
    if isfield(car, p2_name), base_y = car.(p2_name); else, base_y = median(results.(p2_name)); end
    % Ensure base points are calculated for the legend
    if ~exist('base_pts', 'var')
        base_pts = points_calc.calculate_all_scores(base_results, car.fuel.conversion_factor);
    end
    
    plot(base_x, base_y, 'o', 'MarkerSize', 10, 'MarkerFaceColor', 'r', ...
         'MarkerEdgeColor', 'k', 'LineWidth', 1.5, ...
         'DisplayName', sprintf('Base Car: %.1f pts', base_pts.total));
    
    try colormap('turbo'); catch, colormap('parula'); end
    
    cb = colorbar;
    cb.Label.String = 'Total Dynamic Points';
    cb.Label.FontSize = 11;
    
    % Clean up underscores for the labels
    clean_p1 = strrep(p1_name, '_', ' ');
    clean_p2 = strrep(p2_name, '_', ' ');
    
    title(sprintf('Total Points Contour Plot\n%s vs. %s', clean_p1, clean_p2));
    xlabel(clean_p1);
    ylabel(clean_p2);
    
    % legend('Location', 'northeast');
    hold off;
%% Plot 3D Scatter for Three Swept Parameters
elseif num_params == 3 && config.plotSensitivity
    p1_name = param_names{1};
    p2_name = param_names{2};
    p3_name = param_names{3};
    
    x_vals = results.(p1_name);
    y_vals = results.(p2_name);
    z_vals = results.(p3_name);
    pts    = results.TotalPoints;
    
    figure('Name', '3D Sensitivity Suite', 'Color', 'w');
    
    % Plot a 3D scatter. 'filled' makes the points solid, and 'pts' sets the color.
    % The '60' dictates the marker size.
    scatter3(x_vals, y_vals, z_vals, 60, pts, 'filled', 'MarkerEdgeColor', 'k', 'LineWidth', 0.5);
    hold on; grid on;
    
    % --- Find and Plot the Optimal Configuration ---
    [max_pts, max_idx] = max(pts);
    plot3(x_vals(max_idx), y_vals(max_idx), z_vals(max_idx), 'p', ...
          'MarkerSize', 20, 'MarkerFaceColor', 'y', 'MarkerEdgeColor', 'k', ...
          'LineWidth', 2, 'DisplayName', sprintf('Optimum: %.1f pts', max_pts));
          
    % --- Find and Plot the Base Car ---
    if isfield(car, p1_name), base_x = car.(p1_name); else, base_x = median(x_vals); end
    if isfield(car, p2_name), base_y = car.(p2_name); else, base_y = median(y_vals); end
    if isfield(car, p3_name), base_z = car.(p3_name); else, base_z = median(z_vals); end
    
    if ~exist('base_pts', 'var')
        base_pts = points_calc.calculate_all_scores(base_results, car.fuel.conversion_factor);
    end
    
    plot3(base_x, base_y, base_z, 'o', 'MarkerSize', 12, 'MarkerFaceColor', 'r', ...
          'MarkerEdgeColor', 'k', 'LineWidth', 2, ...
          'DisplayName', sprintf('Base Car: %.1f pts', base_pts.total));
    
    % --- Formatting ---
    try colormap('turbo'); catch, colormap('parula'); end
    cb = colorbar;
    cb.Label.String = 'Total Dynamic Points';
    cb.Label.FontSize = 11;
    
    title('4D Optimization Space (Color = Total Points)');
    xlabel(strrep(p1_name, '_', ' '));
    ylabel(strrep(p2_name, '_', ' '));
    zlabel(strrep(p3_name, '_', ' '));
    
    % Set initial viewing angle (Azimuth, Elevation)
    view(45, 30);
    legend('Location', 'best');
    hold off;
end
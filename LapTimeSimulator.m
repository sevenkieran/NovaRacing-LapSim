clear; close;

%% Simulation Configuration
% Events to run
config.RunAccelSim     = true;
config.RunSkidpadSim   = true;
config.RunAutocrossSim = true;
config.RunEnduranceSim = true;

% Debug plots
config.disableAllPlots = true;

config.PlotAero = false;
config.PlotTractiveForce = false;
config.PlotGGV = false;
config.plotThermalEfficiency = false;

config.exportResults = true; % exports results to excel file

%% Define Car Model

% see CarConcepts Directory
car = WR450_car();

%% Tracks
track.autocross.filepath = "Tracks/2025 Autocross_Open_Forward.csv";
track.skidpad.filepath = "Tracks/FSAE_Skidpad_Track";
track.endurance.filepath = "Tracks/2025 Endurance_Closed_Forward.csv";


%% Points Calculation
% All times in seconds
Points.Accel.tmin = 4.169;
Points.Skidpad.tmin = 5.08;
Points.Autocross.tmin = 48.878;
Points.Endurance.tmin = 1295.297;

Points.Endurance.num_laps = 10;
% pace factor is applied to total lap time to account for driver inconsistency
Points.Endurance.pace_factor = 1.1;
Points.Endurance.cone_penalties = 2;

% Efficiency setup
Points.Efficiency.tmin = 129.53; % s
Points.Efficiency.min_CO2_per_lap = 0.5534; % kg
Points.Efficiency.max_CO2_per_lap = 1.3214; % kg
Points.Efficiency.min_eff_factor = 0.289;
Points.Efficiency.max_eff_factor = 0.815;
Points.Efficiency.idle_time = 150; % s in endurance spent idling

%% Logged Data for validation
config.autocross.log_filepath = "LoggedData/Autocross_Michigan2025_lap3.csv";
config.endurance.log_filepath = "LoggedData/Endurance_Michigan2025.csv";


%% Event Specific Settings

% Accel
track.Accel.distance = 75; % [m] length of straight




%% Starting Lap Sim
fprintf('\n============ Starting Lap Sim ============\n');

Points.Efficiency.num_laps = Points.Endurance.num_laps;
CalcPoints = FsaePointsCalculator(Points, Points.Efficiency.num_laps);

car = Utils.load_torque_curve(car);
car = load_fuelSpecs(car);
fprintf(car.name + ' loaded\n\n');

runningEventSimulation = (config.RunAccelSim || config.RunSkidpadSim || config.RunAutocrossSim || config.RunEnduranceSim);

if config.disableAllPlots
    set(0,'DefaultFigureVisible','off')
else
    set(0,'DefaultFigureVisible','on')
end



%% Generate GGV
fprintf('Generating GGV Diagram for ' + car.name + '...\n');
ggv = generate_GGV(car);
fprintf('GGV Diagram Complete\n');

if config.PlotAero || config.PlotGGV || config.PlotTractiveForce
    fprintf('Creating GGV Plots...\n');
end

%% === 3D GGV Plot ===
if config.PlotGGV
    PlotBuilder.plotGGV(ggv);
end

%% Tractive Force
if config.PlotTractiveForce
    PlotBuilder.plotTractiveForce(ggv);
end

%% Aero
if config.PlotAero
    PlotBuilder.plotAeroData(ggv, car.rho, car.frontal_area);
end
if config.PlotAero || config.PlotGGV || config.PlotTractiveForce
    fprintf('Plots Complete\n');
end

%% Thermal Efficiency
if config.plotThermalEfficiency
    PlotBuilder.plotThermalEfficiency(car);
end

%% Output results formatting
if runningEventSimulation && config.exportResults
    fprintf('Running Simulation on ' + car.name + '...\n\n');

    output_dir = fullfile("Results", car.name);
    if ~exist(output_dir, 'dir')
        mkdir(output_dir);
    end
    timestamp = string(datetime('now', 'Format', 'yyyy-MM-dd_HH-mm-ss'));
    output_filepath = fullfile(output_dir, "SimResults_" + timestamp + ".xlsx");
end


%% Run the accel sim
if config.RunAccelSim
    accel_results = run_accel_sim(car, ggv, track.Accel.distance);

    % track.Accel = Utils.create_straight_track(track.Accel.distance, 0.5);
    % accel_results = run_lap_sim(car, ggv, track.Accel);

    fprintf('Accel Lap Time:        %.3f s\n', accel_results.lap_time);
    
    % Visualization
    PlotBuilder.plotAccelVsDistance(accel_results);
    PlotBuilder.plotLongAccelVsVelocity(accel_results);
end

%% Run Skidpad Sim
if config.RunSkidpadSim
    % skid_res = run_skidpad_sim(car, ggv, config.skidpad);

    track.skidpad = Utils.unpackTrack(track.skidpad.filepath);

    skid_res = run_lap_sim(car, ggv, track.skidpad);
    skid_res.lap_time = skid_res.lap_time / 4;
    fprintf('Skidpad Lap Time:      %.3f s\n', skid_res.lap_time);
    
    % Plotting
    PlotBuilder.plotSpeedAndLatgOnTrack(skid_res, "Skidpad");
    % PlotBuilder.plotSkidpadAnalysis(ggv, skid_res);
end

%% Run Autocross Sim
if config.RunAutocrossSim
    % Track Setup
    track.autocross = Utils.unpackTrack(track.autocross.filepath);

    autocross_results = run_lap_sim(car, ggv, track.autocross);
    fprintf('Autocross Lap Time:   %.2f  s\n', autocross_results.lap_time);

    % PlotBuilder.plotSpeedMap(autocross_results);

    % Plot Validation
    logged_autox_data = Utils.parse_motec_csv(config.autocross.log_filepath);
    logged_autox_data.lat_g = logged_autox_data.lat_g * -1; % logged data is switched for some reason
    PlotBuilder.plotGForceValidation(autocross_results, logged_autox_data, '2025 Autocross', false);
    PlotBuilder.plotSpeedComparisonMap(autocross_results, logged_autox_data, '2025 Autocross');
end

%% Run Endurance Sim
if config.RunEnduranceSim
    track.endurance = Utils.unpackTrack(track.endurance.filepath);

    endurance_results = run_lap_sim(car, ggv, track.endurance);
    fprintf('Endurance Lap Time:  %.2f  s\n', endurance_results.lap_time);

    % PlotBuilder.plotSpeedMap(endurance_results);
    % PlotBuilder.plotGearMap(endurance_results);
    PlotBuilder.plotAccelerationAnalysis(endurance_results);
    % PlotBuilder.engineRpmHistogram(endurance_results.engine_rpm);
    
    % Plot Validation
    logged_data = Utils.parse_motec_csv(config.endurance.log_filepath);
    PlotBuilder.plotGForceValidation(endurance_results, logged_data, '2025 Endurance', true);
    PlotBuilder.plotSpeedComparisonMap(endurance_results, logged_data, '2025 Endurance');
end

%% Finalize Results
if runningEventSimulation
    %% Calculate Points
    fprintf('\n============ Points Summary ============\n');
    total_points = 0;
    max_points = 0;

    if config.RunAccelSim
        accel_results.score = CalcPoints.calculate_accel_points(accel_results.lap_time, Points.Accel.tmin);
        total_points = total_points + accel_results.score;
        fprintf('Acceleration: %6.2f / 100.0 pts\n', accel_results.score);

        max_points = max_points + 100;
    end
    
    if config.RunSkidpadSim
        skid_res.score = CalcPoints.calculate_skidpad_points(skid_res.lap_time, Points.Skidpad.tmin);
        total_points = total_points + skid_res.score;
        fprintf('Skidpad:      %6.2f /  75.0 pts\n', skid_res.score);

        max_points = max_points + 75;
    end
    
    if config.RunAutocrossSim
        autocross_results.score = CalcPoints.calculate_autocross_points(autocross_results.lap_time, Points.Autocross.tmin);
        total_points = total_points + autocross_results.score;
        fprintf('Autocross:    %6.2f / 125.0 pts\n', autocross_results.score);

        max_points = max_points + 125;
    end
    
    if config.RunEnduranceSim
        % Calc total endurance lap time and Apply inconsistency penalties
        ideal_time = endurance_results.lap_time * Points.Endurance.num_laps;
        time_driving = ideal_time * Points.Endurance.pace_factor;

        endurance_results.corr_total_time =  time_driving + ...
            (Points.Endurance.cone_penalties * 2.0);

        endurance_results.score = CalcPoints.calculate_endurance_points(endurance_results.corr_total_time, Points.Endurance.tmin);
        total_points = total_points + endurance_results.score;
        fprintf('Endurance:    %6.2f / 275.0 pts\n', endurance_results.score);

        %%% Calculate efficiency score
        ideal_energy_used = endurance_results.energy_used * Points.Efficiency.num_laps;
        
        % account for time lost and time spent idling
        extra_time = (time_driving - ideal_time) + Points.Efficiency.idle_time;
        
        non_driving_energy = Utils.calculate_energy_used(car.idle_power_usage, extra_time);
        endurance_results.total_energy_used = ideal_energy_used + non_driving_energy;
        endurance_results.total_fuel_used = Utils.energy_to_fuel_volume(car.fuel, endurance_results.total_energy_used);

        [endurance_results.efficiency_factor, eff_status] = CalcPoints.calculate_efficiency_factor( ...
            car.fuel.conversion_factor, endurance_results);
        
        endurance_results.efficiency_score = CalcPoints.calculate_efficiency_score( ...
            endurance_results.efficiency_factor, Points.Efficiency.min_eff_factor, Points.Efficiency.max_eff_factor);

        total_points = total_points + endurance_results.efficiency_score;

        % Convert units to mega Joules for readability
        endurance_results.energy_used = endurance_results.energy_used * 1e-6;
        endurance_results.total_energy_used = endurance_results.total_energy_used * 1e-6;

        if endurance_results.efficiency_factor == 0
            fprintf("Efficiency: %s", eff_status);
        else
            fprintf('Efficiency:   %6.2f / 100.0 pts\n', endurance_results.efficiency_score);
        end
        max_points = max_points + 375;
    end
    fprintf('\nTotal Points: %6.2f / %5.1f pts\n', total_points, max_points);

    %% Export to Excel
    if config.exportResults
        fprintf('\nExporting Results to Excel...');
    
        if config.RunAccelSim
            Utils.save_sim_results(accel_results, output_filepath, 'Accel');
        end
        if config.RunSkidpadSim
            Utils.save_sim_results(skid_res, output_filepath, 'Skidpad');
        end
        if config.RunAutocrossSim
            Utils.save_sim_results(autocross_results, output_filepath, 'AutoX');
        end
        if config.RunEnduranceSim
            Utils.save_sim_results(endurance_results, output_filepath, 'Endurance');
        end
        
        fprintf('\nResults saved to: %s\n', output_filepath);
    end

end

set(0,'DefaultFigureVisible','on')
fprintf('============ Lap Sim Complete ============\n\n');
function results = sim_runner(car, config, track)
    % SOLVE_LAP Runs the simulation for a single car configuration
    % Returns a structure with lap times and key metrics.

    % Initialize results to NaN in case a module is disabled
    results.accel_time = NaN;
    results.skidpad_time = NaN;
    results.endurance_time = NaN;

    ggv = generate_GGV(car);


    %% Run Accel
    if config.RunAccelSim
        % accel_res = run_accel_sim(car, ggv, config.accel);
        accel_res = run_lap_sim(car, ggv, track.accel);
        results.accel_time = accel_res.lap_time;

    end

    %% Run Skidpad
    if config.RunSkidpadSim
        skid_res = run_lap_sim(car, ggv, track.skidpad);
        results.skidpad_time = skid_res.lap_time / 4;
    end

    %% Run Autocross
    if config.RunAutocrossSim
        autox_res = run_lap_sim(car, ggv, track.autocross);
        results.autocross_time = autox_res.lap_time;
    end

    %% Run Endurance
    if config.RunEnduranceSim
        endurance_res = run_lap_sim(car, ggv, track.endurance);
        results.endurance_time = endurance_res.lap_time;

        [results.endurance_corr_time, ~, results.endurance_fuel_used] = Utils.process_endurance_results(...
            car, endurance_res, track.endurance.num_laps, track.endurance.pace_factor, ...
            track.endurance.cone_penalties, track.endurance.idle_time);

    end
end
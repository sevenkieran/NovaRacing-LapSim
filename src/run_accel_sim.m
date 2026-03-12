function best_results = run_accel_sim(car, ggv, target_distance)
    % Runs a time-based straight-line acceleration simulation.
    % Automatically tests multiple gear strategies and returns the fastest.
    
    if nargin < 2
        target_distance = 75; 
    end

    candidates = {}; 
    
    %% --- Strategy A: Baseline (All Gears) ---
    car_A = car;
    GGV_A = ggv;
    res_A = simulate_run(car_A, GGV_A, target_distance);
    res_A.strategy = 'Baseline (Start 1st, Max Upshifts)';
    candidates{end+1} = res_A;
    
    %% --- Strategy B: Restricted (Drop the highest gear used) ---
    max_gear_used = max(res_A.gear);
    if max_gear_used > 1
        car_B = car;
        % Truncate the array to remove the final gear the baseline used
        car_B.gear_ratios = car_B.gear_ratios(1:max_gear_used-1);
        GGV_B = generate_GGV(car_B);
        res_B = simulate_run(car_B, GGV_B, target_distance);
        res_B.strategy = sprintf('Restricted (Start 1st, Dropped %dth Gear)', max_gear_used);
        candidates{end+1} = res_B;
    end
    
    %% --- Strategy C: Skip 1st Gear ---
    if length(car.gear_ratios) >= 2
        car_C = car;
        % Remove 1st gear entirely from the array
        car_C.gear_ratios = car_C.gear_ratios(2:end);
        GGV_C = generate_GGV(car_C);
        res_C = simulate_run(car_C, GGV_C, target_distance);
        res_C.strategy = 'Skip 1st (Started in 2nd)';
        
        % Adjust the output log so it correctly shows gears 2, 3, 4 instead of 1, 2, 3
        res_C.gear = res_C.gear + 1; 
        candidates{end+1} = res_C;
    end

    %% Strategy D: skip 1st and drop highest gear used
    if length(car.gear_ratios) >= 2
        car_D = car;
        car_D.gear_ratios = car_D.gear_ratios(2:max_gear_used-1);
        GGV_D = generate_GGV(car_D);
        res_D = simulate_run(car_D, GGV_D, target_distance);
        res_D.strategy = sprintf('Skip 1st, drop %dth gear', max_gear_used);
        res_D.gear = res_D.gear + 2;
        candidates{end+1} = res_D;
    end
    
    %% --- Determine the Winner ---
    best_time = inf;
    best_idx = 1;
    for k = 1:length(candidates)
        if candidates{k}.lap_time < best_time
            best_time = candidates{k}.lap_time;
            best_idx = k;
        end
    end

    best_results = candidates{best_idx};
end

%% Local Helper Function containing the Physics Loop
function results = simulate_run(car, GGV, target_distance)
    dt = 0.001;                 
    max_steps = 15000;          
    
    g = 9.81;
    mass = car.car_mass + car.driver_mass;
    rads_to_rpm = 60 / (2 * pi);
    
    LAUNCH_RPM = min(car.engine_speed); 
    MAX_ENGINE_RPM = max(car.engine_speed);
    
    launch_ramp_speed = 2.5;
    min_shift_torque = 0.45;    % [%]
    
    time_log  = zeros(max_steps, 1);
    dist_log  = zeros(max_steps, 1);
    vel_log   = zeros(max_steps, 1);
    accel_log = zeros(max_steps, 1);
    gear_log  = zeros(max_steps, 1);
    rpm_log   = zeros(max_steps, 1);
    
    v = 0.1; 
    x = 0;
    t = 0;
    current_gear = 1;
    shift_timer = 0;
    
    for i = 1:max_steps
        v_clamp = max(min(GGV.speed_mps), min(v, max(GGV.speed_mps)));
        
        F_drag = interp1(GGV.speed_mps, GGV.TractiveForce.drag, v_clamp, 'linear');
        F_rr   = interp1(GGV.speed_mps, GGV.TractiveForce.rolling_res, v_clamp, 'linear');
        F_grip_max = interp1(GGV.speed_mps, GGV.TractiveForce.grip_limit, v_clamp, 'linear');
        
        launch_multiplier = min(1.0, (v / launch_ramp_speed)^0.5);
        F_grip_actual = F_grip_max * launch_multiplier;
        
        G_current = car.gear_ratios(current_gear) * car.final_drive * car.primary_reduction;
        rpm_wheel = (v / car.r_tire) * G_current * rads_to_rpm;
        rpm_engine = max(LAUNCH_RPM, rpm_wheel);
        
        % -- Optimal Shift Logic --
        if (current_gear < length(car.gear_ratios)) && (shift_timer <= 0)
            T_eng_curr = interp1(car.engine_speed, car.engine_torque, rpm_engine, 'linear', 0);
            F_trac_curr_ideal = (T_eng_curr * G_current * car.drivetrain_efficiency * car.power_scalar) / car.r_tire;
            
            G_next = car.gear_ratios(current_gear + 1) * car.final_drive * car.primary_reduction;
            rpm_next = (v / car.r_tire) * G_next * rads_to_rpm;
            T_eng_next = interp1(car.engine_speed, car.engine_torque, rpm_next, 'linear', 0);
            F_trac_next_ideal = (T_eng_next * G_next * car.drivetrain_efficiency * car.power_scalar) / car.r_tire;
            
            force_crossover = F_trac_next_ideal > F_trac_curr_ideal;
            hitting_limiter = rpm_engine >= (MAX_ENGINE_RPM - 50); 
            
            if force_crossover || hitting_limiter
                shift_timer = car.shift_time;
                current_gear = current_gear + 1;
                
                G_current = G_next;
                rpm_engine = rpm_next;
            end
        end
        
        % -- Soft Limiter & Tractive Force --
        if rpm_engine >= MAX_ENGINE_RPM
            F_trac_engine = F_drag + F_rr; 
        else
            T_eng = interp1(car.engine_speed, car.engine_torque, rpm_engine, 'linear', 0);
            F_trac_engine = (T_eng * G_current * car.drivetrain_efficiency * car.power_scalar) / car.r_tire;
        end
        
        if shift_timer > 0
            progress = 1 - (shift_timer / car.shift_time); 
            shift_multiplier = min_shift_torque + (1 - min_shift_torque) * abs(2 * progress - 1);
            F_trac_engine = F_trac_engine * shift_multiplier;
            shift_timer = shift_timer - dt;
        end
        
        F_trac = min(F_trac_engine, F_grip_actual);
        ax = (F_trac - F_drag - F_rr) / mass;
        
        v = v + ax * dt;
        x = x + v * dt;
        t = t + dt;
        
        time_log(i)  = t;
        dist_log(i)  = x;
        vel_log(i)   = v;
        accel_log(i) = ax / g;
        gear_log(i)  = current_gear;
        rpm_log(i)   = rpm_engine;
        
        if x >= target_distance
            break;
        end
    end
 
    % -- Trim Arrays & Store Results --
    valid_idx = 1:i;
    results.time_s     = time_log(valid_idx);
    results.dist = dist_log(valid_idx);
    results.vel  = vel_log(valid_idx);
    results.speed_mph  = vel_log(valid_idx) * 2.237;
    results.long_g     = accel_log(valid_idx);
    results.gear       = gear_log(valid_idx);
    results.engine_rpm = rpm_log(valid_idx);
    results.lap_time = t;
end
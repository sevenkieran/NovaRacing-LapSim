function results = run_lap_sim(car, GGV, track)  
    %% 1. Track Prep
    x = track.x; y = track.y; R = abs(track.R);
    if max(abs(x)) > 5000, x=x/1000; y=y/1000; R=R/1000; end
    R(R < 0.5 | isnan(R)) = 1e6;
    
    dx = diff(x); dy = diff(y);
    ds = sqrt(dx.^2 + dy.^2); ds = [ds; ds(end)];
    S = [0; cumsum(ds(1:end-1))];
    N = length(x);
    
    %% 2. Physics Setup
    g = 9.81;
    mass = car.car_mass + car.driver_mass;

    % Clamp Helpers to prevent interp2 from throwing NaNs at the extremes
    v_min = min(GGV.speed_mps); 
    v_max = max(GGV.speed_mps);
    clamp_v = @(v) max(v_min, min(v, v_max));
    clamp_lat = @(lr) max(0, min(lr, 1.0));
    
    % 1D Interpolation for pure lateral G (used for normalizing the request)
    get_lat_g = @(v) interp1(GGV.speed_mps, GGV.max_lat_g, clamp_v(v), 'linear');
    
    %% 3. Pass 1: Corner Limits (Apex Speeds)
    v_limit = zeros(N, 1);
    for i = 1:N
        if R(i) > 500
            v_limit(i) = v_max;
        else
            % Solve v^2/R = LatG (Iterative)
            v_g = sqrt(1.5 * g * R(i));
            for k=1:3
                v_g = sqrt(get_lat_g(v_g) * g * R(i));
            end
            v_limit(i) = v_g;
        end
    end
    v_limit = min(v_limit, v_max);
    
    %% 4. Pass 2: Forward Integration (Acceleration)
    v_fwd = zeros(N, 1);
    v_fwd(1) = v_min; % start from a stop
    
    for i = 1:N-1
        v = v_fwd(i);
        
        % Calculate required lateral grip and normalize it (0 to 1)
        lat_accel = v^2 / R(i);
        lat_ratio = clamp_lat((lat_accel/g) / (get_lat_g(v) + 1e-6));
        
        % 2D Lookup: Find net max forward G for this specific Speed & Lat G
        ax_g = interp2(GGV.lat_ratios, GGV.speed_mps, GGV.ax_accel_surface, lat_ratio, clamp_v(v), 'linear');
        ax = ax_g * g; 
        
        % Kinematic step
        v_next = sqrt(max(0, v^2 + 2 * ax * ds(i)));
        v_fwd(i+1) = min(v_next, v_limit(i+1));
    end
    
    %% 5. Pass 3: Backward Integration (Braking)
    v_bwd = zeros(N, 1);
    v_bwd(N) = v_fwd(N);
    
    for i = N:-1:2
        v = v_bwd(i);
        
        % Calculate required lateral grip and normalize it (0 to 1)
        lat_accel = v^2 / R(i);
        lat_ratio = clamp_lat((lat_accel/g) / (get_lat_g(v) + 1e-6));
        
        % 2D Lookup: Find net max deceleration G for this specific Speed & Lat G
        ax_decel_g = interp2(GGV.lat_ratios, GGV.speed_mps, GGV.ax_brake_surface, lat_ratio, clamp_v(v), 'linear');
        ax_decel = ax_decel_g * g; 
        
        % Kinematic step (Deceleration is positive in the backward pass)
        v_prev = sqrt(max(0, v^2 + 2 * ax_decel * ds(i-1)));
        v_bwd(i-1) = min(v_prev, v_limit(i-1));
    end
    
    %% 6. Finalize & Time Integration
    v_final = min(v_fwd, v_bwd);
    results.speed_mps = v_final;
    results.distance_m = S;
    
    % Calculate exact lateral G's
    corner_direction = sign(track.R);
    corner_direction(isnan(track.R) | isinf(track.R)) = 0;
    results.lat_g = corner_direction .* (v_final.^2 ./ R) / g;
    
    % Calculate exact longitudinal G's
    results.long_g = zeros(N, 1);
    for i = 1:N-1
        results.long_g(i) = (v_final(i+1)^2 - v_final(i)^2) / (2 * ds(i) * g);
    end
    results.long_g(N) = results.long_g(N-1);
    
    % Trapezoidal Time Integration
    t_cum = zeros(N, 1);
    for i = 1:N-1
        v1 = max(v_final(i), 0.1); 
        v2 = max(v_final(i+1), 0.1);
        
        % Use average speed across the segment (Trapezoidal rule)
        dt = (2 * ds(i)) / (v1 + v2); 
        t_cum(i+1) = t_cum(i) + dt;
    end
    results.time_s = t_cum;

    %% Back calculate Gear
    MAX_RPM = 15000;              % Hard limit
    SHIFT_RPM = MAX_RPM - 500;    % Driver shifts slightly before limiter
    DOWNSHIFT_RPM = 6000;         % Don't let bog down too much
    
    num_gears = length(car.gear_ratios);
    gear_log = ones(N, 1); 
    rpm_log = zeros(N, 1);
    
    % Initialize state (Assume start in 1st gear)
    current_gear = 1;
    
    % Shift Counter
    upshift_count = 0;
    downshift_count = 0;

    % Conversion factor
    rads_to_rpm = 60 / (2 * pi);

    for i = 1:N
        v = v_final(i);
        
        % 1. Calculate RPM in CURRENT gear
        G_current = car.gear_ratios(current_gear) * car.final_drive * car.primary_reduction;
        rpm_current = (v / car.r_tire) * G_current * rads_to_rpm;
        
        % 2. Check for UPSHIFT
        if (rpm_current > SHIFT_RPM) && (current_gear < num_gears)
            % Perform Upshift
            current_gear = current_gear + 1;
            upshift_count = upshift_count + 1;
            
            % Recalculate RPM in new gear for logging
            G_new = car.gear_ratios(current_gear) * car.final_drive * car.primary_reduction;
            rpm_current = (v / car.r_tire) * G_new * rads_to_rpm;
            
        % 3. Check for DOWNSHIFT
        elseif (rpm_current < DOWNSHIFT_RPM) && (current_gear > 1)
            % BEFORE downshifting, check if lower gear would over-rev!
            G_lower = car.gear_ratios(current_gear - 1) * car.final_drive * car.primary_reduction;
            rpm_lower = (v / car.r_tire) * G_lower * rads_to_rpm;
            
            if rpm_lower < SHIFT_RPM - 500 % Buffer to avoid instant upshift
                current_gear = current_gear - 1;
                downshift_count = downshift_count + 1;
                rpm_current = rpm_lower;
            end
        end
        
        % 4. Log State
        gear_log(i) = current_gear;
        rpm_log(i) = rpm_current;
    end

    %% Calculate energy consumption
    clamp = @(v) max(v_min, min(v, v_max));
    get_drag     = @(v) interp1(GGV.speed_mps, GGV.TractiveForce.drag, clamp(v), 'linear');
    get_roll_res = @(v) interp1(GGV.speed_mps, GGV.TractiveForce.rolling_res, clamp(v), 'linear');

    fuel_power_watts = zeros(N, 1);

    for i = 1:N-1
        ax_total = results.long_g(i) * g;
        F_resist = get_drag(v_final(i)) + get_roll_res(v_final(i));
        F_tire_req = (mass * ax_total) + F_resist;
        
        if F_tire_req > 0
            % Accelerating: Dynamically look up thermal efficiency based on current RPM
            current_rpm = rpm_log(i);
            current_eff = interp1(car.fuel.rpm_vector, car.fuel.eff_curve, current_rpm, 'linear', 'extrap');
            
            wheel_power = F_tire_req * v_final(i);
            crank_power = wheel_power / car.drivetrain_energy_efficiency;
            fuel_power_watts(i) = crank_power / current_eff;
        else
            % Braking or coasting (Decel chemical power remains consistent across fuels)
            fuel_power_watts(i) = car.decel_power_usage;
        end
    end

    energy_joules = zeros(N, 1);
    for i = 1:N-1
        dt = results.time_s(i+1) - results.time_s(i);
        power_avg = (fuel_power_watts(i) + fuel_power_watts(i+1)) / 2;
        energy_joules(i+1) = energy_joules(i) + (power_avg * dt);
    end

    %% Store Results
    
    results.x = x;
    results.y = y;
    
    results.dist = S;
    results.vel = v_final;
    results.speed_mph = v_final * 2.237;
    results.shift_penalty = upshift_count * car.shift_time;
    results.lap_time = t_cum(end) + results.shift_penalty;
    results.gear = int32(gear_log);
    results.upshift_count = upshift_count;
    results.downshift_count = downshift_count;
    results.engine_rpm = rpm_log;
    results.energy_used = energy_joules(end) * car.energy_usage_scalar;
    results.fuel_used = Utils.energy_to_fuel_volume(car.fuel, results.energy_used);
    
end
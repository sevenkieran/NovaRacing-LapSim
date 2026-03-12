function [GGV] = generate_GGV(car)

% Constants
g = 9.81;
mass = car.car_mass + car.driver_mass;

%% Powertrain Model
T = car.engine_torque;  % Nm
rpm_for = car.engine_speed;

G_dt = car.gear_ratios * car.final_drive * car.primary_reduction;
max_wheel_speed = (max(rpm_for).* 2*pi/60)./(G_dt); % rad/s
max_speed = max_wheel_speed .* car.r_tire; % mps



%% Aero Model
% Drag and Downforce
if car.aero_mode == "static"
    GGV.Aero.Cd_interp = @(v) (car.Cd * car.drag_scale) * ones(size(v));
    GGV.Aero.Cl_interp = @(v) (car.Cl * car.downforce_scale) * ones(size(v));
    GGV.Aero.Cl_interp_safe = GGV.Aero.Cl_interp;

    % Create data for debugging plots
    GGV.Aero.raw_mph = linspace(0, 150, 50)';
    dummy_mps = GGV.Aero.raw_mph ./ 2.237;
    dynamic_q = 0.5 * car.rho * car.frontal_area .* (dummy_mps.^2);
    
    % Save raw data
    GGV.Aero.raw_downforce = car.Cl * dynamic_q;
    GGV.Aero.raw_drag = car.Cd * dynamic_q;
else
    aero_data = readtable(car.aero_data_filepath);
    aero_mph = aero_data.Speed_mph;
    aero_mps = aero_mph./2.237;
    aero_downforce = aero_data.Downforce_N;
    aero_drag =  aero_data.Drag_N;

    aero_Cd = car.drag_scale * aero_drag ./ (0.5 * car.rho * car.frontal_area * aero_mps.^2);
    aero_Cl = car.downforce_scale * aero_downforce ./ (0.5 * car.rho * car.frontal_area * aero_mps.^2);
    
    aero_Cd(1) = 0;
    aero_Cl(1) = 0;
    
    % Aero interp functions
    GGV.Aero.Cd_interp = @(v) interp1(aero_mps, aero_Cd, v, 'pchip', aero_Cd(end));
    GGV.Aero.Cl_interp = @(v) interp1(aero_mps, aero_Cl, v, 'pchip', aero_Cl(end));
    GGV.Aero.Cl_interp_safe = @(v) GGV.Aero.Cl_interp(min(max(v, min(aero_mps)), max(aero_mps)));

    % save raw data
    GGV.Aero.raw_mph = aero_mph;
    GGV.Aero.raw_downforce = aero_downforce;
    GGV.Aero.raw_drag = aero_drag;
end

% aero balance
if car.aero_balance_mode == "static"
    GGV.Aero.Bal_interp = @(v) (car.aero_balance + car.aero_balance_offset) * ones(size(v));

    GGV.Aero.raw_balance = car.aero_balance * ones(size(GGV.Aero.raw_mph));
else
    if ~exist('aero_data', 'var')
        aero_data = readtable(car.aero_data_filepath);
        aero_mph = aero_data.Speed_mph;
        aero_mps = aero_mph ./ 2.237;

        GGV.Aero.raw_mph = aero_mph;
        dynamic_q = 0.5 * car.rho * car.frontal_area .* (aero_mps.^2);
        GGV.Aero.raw_downforce = car.Cl * dynamic_q;
        GGV.Aero.raw_drag = car.Cd * dynamic_q;
    end
    aero_balance = aero_data.Balance; % percent on front
    
    % Make sure aero balance in a decimal not a percent
    if mean(aero_balance) > 2
        aero_balance = aero_balance / 100;
    end
    GGV.Aero.Bal_interp = @(v) (interp1(aero_mps, aero_balance, v, ...
        'pchip', aero_balance(end)) + car.aero_balance_offset);
    GGV.Aero.raw_balance = aero_balance;
end


%% GGV MAP GENERATION

GGV.speed_mps = linspace(0.1, max(max_speed), 50); % Start at 0.1 to avoid divide-by-zero
N = size(GGV.speed_mps);

% Initialize limit arrays
GGV.max_lat_g   = zeros(N);
GGV.max_brake_g = zeros(N);
GGV.max_accel_g  = zeros(N);

dist_cg_front = car.wb * (1 - car.wd);
dist_cg_rear = car.wb * car.wd;

Fz_static_front = mass * g * (1-car.wd);
Fz_static_rear = mass * g * car.wd;

num_lat_pts = 15;
GGV.lat_ratios = linspace(0, 1, num_lat_pts);

GGV.ax_brake_surface = zeros(N(2), num_lat_pts);
GGV.ax_accel_surface = zeros(N(2), num_lat_pts);

% 2. Physics Loop
for k = 1:length(GGV.speed_mps)
    v = GGV.speed_mps(k);
    
    %% A. Aero Forces
    F_down_total = 0.5 * car.rho * car.frontal_area *  GGV.Aero.Cl_interp_safe(v) * v^2;
    F_drag       = 0.5 * car.rho * car.frontal_area * GGV.Aero.Cd_interp(v) * v^2;
    F_rr         = car.rolling_res * (mass * g + F_down_total);

    % Apply Aero Balance Migration
    front_aero_bal = GGV.Aero.Bal_interp(v); % Look up balance at this speed
    front_aero_bal = max(0, min(1, front_aero_bal));
    
    F_aero_fr = F_down_total * front_aero_bal;
    F_aero_rear  = F_down_total * (1 - front_aero_bal);
    
    %% B. Lateral Limit
    ay_guess = 1.5; 
    for iter = 1:15
        % Weight Transfer
        delta_Fz_f = (mass * ay_guess * g * car.h_cg * car.lltd) / car.tw_f;
        delta_Fz_r = (mass * ay_guess * g * car.h_cg * (1 - car.lltd)) / car.tw_r;
        
        % Front Axle Capability
        Fz_f_static = Fz_static_front + F_aero_fr;
        Fz_fl = max(0, (Fz_f_static/2) - delta_Fz_f); 
        Fz_fr = max(0, (Fz_f_static/2) + delta_Fz_f);
        
        mu_fl = car.mu_lat + car.tire_load_sensitivity * (Fz_static_front/2 - Fz_fl);
        mu_fr = car.mu_lat + car.tire_load_sensitivity * (Fz_static_front/2 - Fz_fr);
        Fy_front_cap = (Fz_fl * mu_fl) + (Fz_fr * mu_fr);
        
        % Rear Axle Capability
        Fz_r_static = Fz_static_rear + F_aero_rear;
        Fz_rl = max(0, (Fz_r_static/2) - delta_Fz_r);
        Fz_rr = max(0, (Fz_r_static/2) + delta_Fz_r);
        
        mu_rl = car.mu_lat + car.tire_load_sensitivity * (Fz_static_rear/2 - Fz_rl);
        mu_rr = car.mu_lat + car.tire_load_sensitivity * (Fz_static_rear/2 - Fz_rr);
        Fy_rear_cap = (Fz_rl * mu_rl) + (Fz_rr * mu_rr);
        
        % Moment Balance Check: The car is limited by the WEAKEST axle
        Fy_limit_us = Fy_front_cap * (1 + dist_cg_front/dist_cg_rear);
        
        % If Rear limits (Oversteer): Total = Rear + (Rear * b/a)
        Fy_limit_os = Fy_rear_cap * (1 + dist_cg_rear/dist_cg_front);
        
        Fy_total = min(Fy_limit_us, Fy_limit_os);
        
        % Update Guess
        ay_new = Fy_total / (mass * g);
        ay_guess = 0.5*ay_guess + 0.5*ay_new;
    end
    GGV.max_lat_g(k) = ay_guess;

    %% Engine initialization
    wheel_omega = v / car.r_tire; % rad/s
    eng_rpms = wheel_omega .* G_dt .* (60 / (2*pi));     
    eng_rpms_clamped = max(min(rpm_for), min(max(rpm_for), eng_rpms));
    
    available_torque = interp1(rpm_for, T, eng_rpms_clamped, 'linear', 0);
    available_torque(eng_rpms > max(rpm_for)) = 0; 
    
    % Calculate Tractive Force at the contact patch for each gear
    tractive_force_per_gear = (available_torque .* G_dt .* car.drivetrain_efficiency .* car.power_scalar) ./ car.r_tire;
    
    F_tractive_limit = max(tractive_force_per_gear);

    % save some data for plotting
    GGV.TractiveForce.gears(k, :) = tractive_force_per_gear; 
    GGV.TractiveForce.engine_limit(k) = F_tractive_limit;
    

    %% C. Calculate combined GGV limits

    for j = 1:num_lat_pts
        % Current lateral state for this cell in the grid
        ay_curr = GGV.lat_ratios(j) * GGV.max_lat_g(k);

        %% Calculate combined braking and lateral limits
        ax_brake_guess = 1.5;
        for iter = 1:15
            % diagonal load transfer
            delta_Fz_lat_f = (mass * ay_curr * g * car.h_cg * car.lltd) / car.tw_f;
            delta_Fz_lat_r = (mass * ay_curr * g * car.h_cg * (1 - car.lltd)) / car.tw_r;


            delta_Fz_long_inertia = (mass * ax_brake_guess * g * car.h_cg) / car.wb;
            delta_Fz_long_aero = (F_drag * car.h_cg) / car.wb;
            delta_Fz_long = delta_Fz_long_inertia - delta_Fz_long_aero;
            
            % 4 corner loads
            Fz_f_base = Fz_static_front + F_aero_fr + delta_Fz_long;
            Fz_r_base = Fz_static_rear + F_aero_rear - delta_Fz_long;
            Fz_r_base = max(0, Fz_r_base);
    
            Fz_fl = max(0, Fz_f_base/2 - delta_Fz_lat_f);
            Fz_fr = max(0, Fz_f_base/2 + delta_Fz_lat_f);
            Fz_rl = max(0, Fz_r_base/2 - delta_Fz_lat_r);
            Fz_rr = max(0, Fz_r_base/2 + delta_Fz_lat_r);
            
            % 4 corner tire sensitivities
            mu_lat_fl = car.mu_lat + car.tire_load_sensitivity * (Fz_static_front/2 - Fz_fl);
            mu_lat_fr = car.mu_lat + car.tire_load_sensitivity * (Fz_static_front/2 - Fz_fr);
            mu_lat_rl = car.mu_lat + car.tire_load_sensitivity * (Fz_static_rear/2 - Fz_rl);
            mu_lat_rr = car.mu_lat + car.tire_load_sensitivity * (Fz_static_rear/2 - Fz_rr);

            mu_brk_fl = car.mu_brake + car.tire_load_sensitivity * (Fz_static_front/2 - Fz_fl);
            mu_brk_fr = car.mu_brake + car.tire_load_sensitivity * (Fz_static_front/2 - Fz_fr);
            mu_brk_rl = car.mu_brake + car.tire_load_sensitivity * (Fz_static_rear/2 - Fz_rl);
            mu_brk_rr = car.mu_brake + car.tire_load_sensitivity * (Fz_static_rear/2 - Fz_rr);

            % Axle lateral capacity vs requirement
            Fy_cap_f = (Fz_fl * mu_lat_fl) + (Fz_fr * mu_lat_fr);
            Fy_cap_r = (Fz_rl * mu_lat_rl) + (Fz_rr * mu_lat_rr);
            
            Fy_req_f = mass * ay_curr * g * (dist_cg_rear / car.wb);
            Fy_req_r = mass * ay_curr * g * (dist_cg_front / car.wb);
    
            % Axle utilization ratio
            U_f = min(1.0, Fy_req_f / (Fy_cap_f + 1e-6));
            U_r = min(1.0, Fy_req_r / (Fy_cap_r + 1e-6));

            % Available Braking Potential using Tire-Level Ellipse
            F_brk_cap_f = (Fz_fl * mu_brk_fl + Fz_fr * mu_brk_fr) * sqrt(1 - U_f^2);
            F_brk_cap_r = (Fz_rl * mu_brk_rl + Fz_rr * mu_brk_rr) * sqrt(1 - U_r^2);
            
            % Apply Mechanical Brake Bias
            F_brake_fr_lock = F_brk_cap_f / car.brake_bias;
            F_brake_r_lock = F_brk_cap_r / (1 - car.brake_bias);
            F_brake_potential = min(F_brake_fr_lock, F_brake_r_lock);
            
            ax_new = (F_brake_potential + F_drag + F_rr) / (mass * g);
            ax_brake_guess = 0.5 * ax_brake_guess + 0.5 * ax_new;
        end
        GGV.ax_brake_surface(k, j) = ax_brake_guess;
    
        %% Combined acceleration limits

        ax_accel_guess = 1.5; % Initial guess for convergence
        for iter = 1:15
            delta_Fz_lat_r = (mass * ay_curr * g * car.h_cg * (1 - car.lltd)) / car.tw_r;
            delta_Fz_long_accel = (mass * ax_accel_guess * g * car.h_cg) / car.wb;
            
            Fz_r_base = Fz_static_rear + F_aero_rear + delta_Fz_long_accel;
            
            % Rear Axle Loading
            Fz_rl = max(0, Fz_r_base/2 - delta_Fz_lat_r);
            Fz_rr = max(0, Fz_r_base/2 + delta_Fz_lat_r);
            
            mu_lat_rl = car.mu_lat + car.tire_load_sensitivity * (Fz_static_rear/2 - Fz_rl);
            mu_lat_rr = car.mu_lat + car.tire_load_sensitivity * (Fz_static_rear/2 - Fz_rr);
            
            mu_lon_rl = car.mu_long + car.tire_load_sensitivity * (Fz_static_rear/2 - Fz_rl);
            mu_lon_rr = car.mu_long + car.tire_load_sensitivity * (Fz_static_rear/2 - Fz_rr);
            
            % Rear Lateral Utilization
            Fy_cap_r = (Fz_rl * mu_lat_rl) + (Fz_rr * mu_lat_rr);
            Fy_req_r = mass * ay_curr * g * (dist_cg_front / car.wb);
            U_r = min(1.0, Fy_req_r / (Fy_cap_r + 1e-6));
            
            % Available Forward Traction
            F_trac_cap = (Fz_rl * mu_lon_rl + Fz_rr * mu_lon_rr) * sqrt(1 - U_r^2);
            F_accel_potential = min(F_tractive_limit, F_trac_cap);

            % pure long grip limit when there is no lateral force being
            % used by tire
            if j == 1
                GGV.TractiveForce.grip_limit(k) = F_trac_cap;
            end
            
            ax_new = (F_accel_potential - F_drag - F_rr) / (mass * g);
            ax_accel_guess = 0.5 * ax_accel_guess + 0.5 * ax_new;
        end
        GGV.ax_accel_surface(k, j) = ax_accel_guess;
    end
    GGV.max_brake_g(k) = GGV.ax_brake_surface(k, 1);
    GGV.max_accel_g(k) = GGV.ax_accel_surface(k, 1);

    % Save useful parameters
    GGV.TractiveForce.drag(k) = F_drag;
    GGV.TractiveForce.rolling_res(k) = F_rr;
end
end
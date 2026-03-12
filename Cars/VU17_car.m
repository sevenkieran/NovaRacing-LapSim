function [car] = VU17_car()
    %% Car Model Inputs
    
    car.name = "VU17";

    % Tires
    car.mu_lat = 1.48;    % Tire coefficients are calibrated
    car.mu_long = 1.45;   % to measured G forces
    car.mu_brake = 1;
    car.r_tire = 0.203;     % m, 8in. in freedom units
    car.tire_load_sensitivity = 0.0003; % [1/N] Sensitivity: Grip drops as load i
    car.rolling_res = 0.03;   % Rolling Resistance Coeff
    
    % Mass
    car.car_mass = 200;     % kg
    car.driver_mass = 75;   % kg
    
    % Suspension
    car.wb = 1.525;          % Wheelbase [m]
    car.h_cg = 0.2921;       % CoG Height [m]
    car.wd = 0.51;           % Weight Distribution [%] on rear
    car.tw_f = 1.219; % [m] Front Track width
    car.tw_r = 1.219; % [m] rear track width
    car.lltd = 0.53;  % Lateral load transfer definition
    
    % Aero
    car.frontal_area = 1.05;           % Frontal Area [m^2]
    car.rho = 1.162;        % kg/m^3 from 2025 spec sheet
    car.drag_scale = 1;
    car.downforce_scale = 1.8;
    car.CoP_offset = 0.07; % Ex. 0.05 adds 5% to the Front, -0.05 adds to the rear

     % Aero
    car.aero_mode = "data"; % "data" or "static"
    car.Cd = 1.10;            % Coefficient used with static mode
    car.Cl = 3.20;            % Coefficient used with static mode

    car.frontal_area = 1.05;           % Frontal Area [m^2]
    car.rho = 1.162;        % kg/m^3 from 2025 spec sheet
    car.drag_scale = 1;
    car.downforce_scale = 1;

    car.aero_balance_mode = "static"; % or "static"
    car.aero_balance_offset = 0.0; % Ex. 0.05 adds 5% to the Front
    car.aero_balance = 0.5; % [%] on front, only used in static mode
    
    % Powertrain
    car.power_scalar = 1.0;

    % Drivetrain
    car.final_drive = 40.0 / 11;
    car.gear_ratios = [2, 1.667, 1.444, 1.36, 1.15];
    car.primary_reduction = 85.0 / 41;
    car.drivetrain_efficiency = 0.89; % VU17 is simulated at the engine
    car.shift_time =  0.08;   % [s] Time lost per shift 
    
    % Brakes
    car.brake_bias = 0.6; % bias [%] on front

    % Only used in Fuel Efficiency calculations
    car.fuel_type = "100 Octane";
    car.drivetrain_energy_efficiency = 0.88; % only used in fuel efficiency calculations
    car.energy_usage_scalar = 1.0;
    
    % Convert logged fuel flow in ml/s to watts
    % Power [w] = fuel flow [mL/s] * energy density [MJ/L] * 1e3
    % See src/load_fuelSpecs for energy density of fuel types
    % car.idle_power_usage = 15280; % Watts
    car.idle_power_usage = 13700; % Watts
    % car.decel_power_usage = 33616; % Watts
    car.decel_power_usage = 30000; % Watts
 
    % example fuel flows with 100 octane
    % idle_fuel_flow = 0.0005; % L/s
    % car.decel_fuel_flow = 0.0015; % L/s


    % File Paths
    car.aero_data_filepath = "Cars/ReferenceAeroData/VU16_aero_data.xlsx";
    car.ptrain_data_filepath = "Cars/ReferenceEngineData/VU17_sim_ptrain_data.xlsx";
end
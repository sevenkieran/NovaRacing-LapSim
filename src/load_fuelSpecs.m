function car = load_fuelSpecs(car)
    % conversion factors come from 2026 FSAE rules
    % energy densities are calculated from fuel specs when possible
    % peak thermal efficiencies are guesses

    switch lower(car.fuel_type)
        % Sunoco 260 gt race fuel
        case {'100 octane', '100octane'}
            car.fuel.conversion_factor = 2.31; 
            car.fuel.energy_density = 30.56 * 1e6; 
            car.fuel.peak_thermal_efficiency = 0.31;
        
        % Generic 93 octane
        case {'93 octane', '93octane'}
            car.fuel.conversion_factor = 2.31; 
            car.fuel.energy_density = 31.32 * 1e6; 
            car.fuel.peak_thermal_efficiency = 0.29;
            
        % Sunoco E85R race fuel
        case {'e85', 'e85r'}
            car.fuel.conversion_factor = 1.65; 
            car.fuel.energy_density = 22.97 * 1e6; 
            car.fuel.peak_thermal_efficiency = 0.34;
            
        otherwise
            error('Unknown fuel type: %s. Please use E85, 100 Octane, or 93 Octane.', car.fuel_type);
    end
    
    % Generate the dynamic efficiency curve for the active fuel
    car.fuel.rpm_vector = car.engine_speed;
    car.fuel.eff_curve = generate_eff_curve(car.engine_speed, car.engine_torque, car.fuel.peak_thermal_efficiency);
end

%% scales thermal efficiency on RPM
function eff_curve = generate_eff_curve(rpm, torque, peak_eff)
    [max_tq, idx_peak] = max(torque);
    norm_tq = torque / max_tq;
    eff_curve = peak_eff .* norm_tq;
    
    rpm_peak = rpm(idx_peak);
    rpm_max = max(rpm);
    
    for i = idx_peak:length(rpm)
        if rpm_max > rpm_peak
            penalty_factor = 1.0 - 0.12 * ((rpm(i) - rpm_peak) / (rpm_max - rpm_peak));
            eff_curve(i) = max(0.2, eff_curve(i) * penalty_factor);
        end
    end
end
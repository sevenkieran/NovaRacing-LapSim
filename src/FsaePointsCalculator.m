classdef FsaePointsCalculator
    % Calculate FSAE points with 2026 rules
    
    properties
        Accel
        Skidpad
        Autocross
        Endurance
        Efficiency
        num_laps
    end
    
    methods
        function obj = FsaePointsCalculator(CompData, num_laps)
            % Construct an instance of this class
            obj.Accel = CompData.Accel;
            obj.Skidpad = CompData.Skidpad;
            obj.Autocross = CompData.Autocross;
            obj.Endurance = CompData.Endurance;
            obj.Efficiency = CompData.Efficiency;
            obj.num_laps = num_laps;
        end
        
        %% Calculate All Scores
        function pts = calculate_all_scores(obj, sim_results, fuel_conversion_factor)
            % Initialize the output structure with defaults
            pts.accel = 0;
            pts.skidpad = 0;
            pts.autox = 0;
            pts.endurance = 0;
            pts.efficiency_score = 0;
            pts.efficiency_factor = 0;
            pts.efficiency_status = "Not Run";
            
            % Acceleration
            if isfield(sim_results, 'accel_time') && sim_results.accel_time > 0
                pts.accel = FsaePointsCalculator.calculate_accel_points(sim_results.accel_time, obj.Accel.tmin);
            end
            
            % Skidpad
            if isfield(sim_results, 'skidpad_time') && sim_results.skidpad_time > 0
                pts.skidpad = FsaePointsCalculator.calculate_skidpad_points(sim_results.skidpad_time, obj.Skidpad.tmin);
            end
            
            % Autocross
            if isfield(sim_results, 'autocross_time') && sim_results.autocross_time > 0
                pts.autox = FsaePointsCalculator.calculate_autocross_points(sim_results.autocross_time, obj.Autocross.tmin);
            end
            
            % Endurance & Efficiency
            if isfield(sim_results, 'endurance_corr_time') && sim_results.endurance_corr_time > 0
                pts.endurance = FsaePointsCalculator.calculate_endurance_points(sim_results.endurance_corr_time, obj.Endurance.tmin);
                
                [pts.efficiency_factor, pts.efficiency_status] = ...
                    obj.calculate_efficiency_factor(fuel_conversion_factor, sim_results);

                if pts.efficiency_status ~= "OK"
                    fprintf("%s", pts.efficiency_status)
                end
                
                pts.efficiency_score = FsaePointsCalculator.calculate_efficiency_score(...
                    pts.efficiency_factor, obj.Efficiency.min_eff_factor, obj.Efficiency.max_eff_factor);
            end
            
            % Optional: Calculate a total score right here for convenience
            pts.total = pts.accel + pts.skidpad + pts.autox + pts.endurance + pts.efficiency_score;
        end
        
        %% Calculate Efficiency factor based on 2026 rules
        function [efficiency_factor, status] = calculate_efficiency_factor(obj, fuel_conversion_factor, sim_results)
            % Requires sim_results to have .total_fuel_used and .corr_total_time
            
            % Safety check to ensure required fields exist
            if isfield(sim_results, 'total_fuel_used') && isfield(sim_results, 'corr_total_time')
                tot_fuel_used = sim_results.total_fuel_used;
                tot_time = sim_results.corr_total_time;
            elseif isfield(sim_results, 'endurance_corr_time') && isfield(sim_results, 'endurance_fuel_used')
                tot_fuel_used = sim_results.endurance_fuel_used;
                tot_time = sim_results.endurance_corr_time;
            else
                efficiency_factor = 0;
                status = "Missing fuel or time data";
                return;
            end
            
            total_CO2 = tot_fuel_used * fuel_conversion_factor;
            
            % Get average lap time and CO2
            Tyour = tot_time / obj.num_laps;
            CO2_your = total_CO2 / obj.num_laps;
            tmax = obj.Efficiency.tmin * 1.45;
            
            % Calculate the raw factor
            efficiency_factor = (obj.Efficiency.tmin / Tyour) * ...
                (obj.Efficiency.min_CO2_per_lap / CO2_your);
            
            % Apply rulebook thresholds and set status
            if Tyour > tmax 
                status = "Lap time too slow";
                efficiency_factor = 0;
            elseif CO2_your > obj.Efficiency.max_CO2_per_lap
                status = "CO2 usage too high";
                efficiency_factor = 0;
            elseif efficiency_factor > obj.Efficiency.max_eff_factor
                status = "Efficiency factor capped";
                efficiency_factor = obj.Efficiency.max_eff_factor;
            else
                status = "OK";
            end
        end
    end
    
    methods (Static)
        %% 2026 Accel Points
        function pts = calculate_accel_points(tyour, tmin)
            tmax = 1.5 * tmin;
            if tyour > tmax
                pts = 4.5;
            else
                pts = 95.5 * ((tmax / tyour - 1) / (tmax / tmin - 1)) + 4.5;
            end
            pts = max(4.5, min(100, pts));
        end
        
        %% 2026 Skidpad Points
        function pts = calculate_skidpad_points(tyour, tmin)
            tmax = 1.25 * tmin;
            if tyour > tmax
                pts = 3.5;
            else
                % Skidpad uses a squared ratio in its formula
                pts = 71.5 * ((tmax / tyour)^2 - 1) / ((tmax / tmin)^2 - 1) + 3.5;
            end
            pts = max(3.5, min(75, pts));
        end
        
        %% 2026 Autocross Points
        function pts = calculate_autocross_points(tyour, tmin)
            tmax = 1.45 * tmin;
            if tyour > tmax
                pts = 6.5;
            else
                pts = 118.5 * (tmax / tyour - 1) / (tmax / tmin - 1) + 6.5;
            end
            pts = max(6.5, min(125, pts));
        end
        
        %% 2026 Endurance Points
        function pts = calculate_endurance_points(tyour, tmin)
            tmax = 1.45 * tmin;
            if tyour > tmax
                pts = 25.0;
            else
                pts = 250 * (tmax / tyour - 1) / (tmax / tmin - 1) + 25;
            end
            pts = max(25.0, min(275, pts));
        end
        
        %% Calculate Efficiency Score
        function score = calculate_efficiency_score(efficiency_factor, min_eff_factor, max_eff_factor)
            if efficiency_factor <= 0
                score = 0;
            else
                score = (efficiency_factor - min_eff_factor) / ...
                    (max_eff_factor - min_eff_factor) * 100;
            end
            % Cap score at 100 just in case
            score = max(0, min(100, score)); 
        end
    end
end
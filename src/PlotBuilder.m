classdef PlotBuilder
    methods (Static)
        
        %% Speed over Track Plot
        function plotSpeedMap(results, event)
            figure('Name', strcat(event, ' Speed Track Map'), 'Color', 'w');
            scatter(results.x, results.y, 20, results.speed_mph, 'filled');
            colormap(jet);
            c = colorbar;
            c.Label.String = 'Speed [mph]';
            axis equal; grid on;
            title(sprintf('%s Lap Time: %.2f s', event, results.lap_time));
            xlabel('X Position [m]'); ylabel('Y Position [m]');
        end
        
        %% Gear over Track
        function plotGearMap(results)
            figure('Name', 'Endurance Gearing Track Map', 'Color', 'w');
            scatter(results.x, results.y, 20, results.gear, 'filled');
            max_gear = max(results.gear);
            colormap(jet(max_gear));
            c = colorbar;
            c.Ticks = 1:max_gear;
            clim([0.5, max_gear + 0.5]);
            c.Label.String = 'Gear';
            axis equal; grid on;
            title(sprintf('Endurance Lap Time: %.2f s | Upshift Count: %d', ...
                     results.lap_time, results.upshift_count));
            xlabel('X Position [m]'); ylabel('Y Position [m]');
        end
        
        %% Plot G Force Analysis
        function plotAccelerationAnalysis(results)
            figure('Name', 'Acceleration Analysis', 'Color', 'w');
            t = tiledlayout(2, 3, 'TileSpacing', 'compact');
            
            % 1. Realized G-G Diagram
            nexttile([2 1]);
            hold on; grid on; axis equal;
            xline(0, 'k--', 'Alpha', 0.5); yline(0, 'k--', 'Alpha', 0.5);
            scatter(results.lat_g, results.long_g, 15, results.speed_mph, 'filled', 'MarkerFaceAlpha', 0.6);
            colormap(gca, 'turbo'); 
            cb = colorbar; cb.Location = 'southoutside';
            cb.Label.String = 'Speed [mph]'; cb.Label.FontWeight = 'bold';
            xlabel('Lat Accel [G]', 'FontWeight', 'bold');
            ylabel('Long Accel [G]', 'FontWeight', 'bold');
            title('G-G Diagram');
            xlim([-2.5 2.5]); ylim([-2.5 2.5]); box on;
            
            % 2. Lateral G vs Distance
            nexttile([1 2]);
            hold on; grid on;
            plot(results.dist, results.lat_g, 'b');
            yline(0, 'k-', 'LineWidth', 1, 'Alpha', 0.5);
            ylabel('Lat Accel [G]', 'FontWeight', 'bold');
            title('Lateral G vs. Distance');
            xlim([0 max(results.dist)]); ylim([-2.5 2.5]); box on;
            
            % 3. Longitudinal G vs Distance
            nexttile([1 2]);
            hold on; grid on;
            plot(results.dist, results.long_g, 'r');
            yline(0, 'k-', 'LineWidth', 1, 'Alpha', 0.5);
            xlabel('Track Distance [m]', 'FontWeight', 'bold');
            ylabel('Long Accel [G]', 'FontWeight', 'bold');
            title('Longitudinal G vs. Distance');
            xlim([0 max(results.dist)]); ylim([-2.5 2.5]); box on;
        end

        %% Plot Skidpad analysis
        function plotSkidpadAnalysis(ggv, results)
            figure('Name', 'Skidpad Analysis', 'Color', 'w');
            hold on; grid on;
            
            % 1. Plot the Car's Capability (Supply)
            v_range = linspace(0, 30, 100);
            lat_g_cap = interp1(ggv.speed_mps, ggv.max_lat_g, v_range, 'linear');
            plot(v_range * 2.237, lat_g_cap, 'k', 'LineWidth', 2);
            
            % 2. Plot the Physics Limit (Demand)
            lat_g_req = (v_range.^2) ./ results.turn_radius ./ 9.81;
            plot(v_range * 2.237, lat_g_req, 'r--', 'LineWidth', 2);
            
            % 3. Highlight the Intersection
            v_mph = results.cornering_speed_mph;
            g_val = results.max_lat_g;
            plot(v_mph, g_val, 'bo', 'MarkerFaceColor', 'b', 'MarkerSize', 8);
            
            % Labels
            xlabel('Vehicle Speed [mph]');
            ylabel('Lateral Acceleration [g]');
            legend('Car Capability (GGV)', 'Physics Demand (v^2/R)', 'Skidpad Limit');
            title(['Skidpad Limit: ' num2str(results.max_lat_g, '%.2f') 'g @ ' ...
                   num2str(results.cornering_speed_mph, '%.1f') ' mph']);
            
            % Text annotation for Aero
            text(5, 2.2, ['Lap Time: ' num2str(results.lap_time, '%.3f') ' s'], 'FontSize', 12);
            xlim([0 40]);
            ylim([0 3]);
        end

        %% Plot accel event data vs distance
        function plotAccelVsDistance(results)
            figure('Name', 'Accel Performance');
            subplot(4,1,1);
            plot(results.dist, results.vel * 2.237, 'LineWidth', 2);
            ylabel('Speed (mph)'); grid on;
            title(['Accel Run: ' num2str(results.lap_time, '%.3f') ' s']);
            
            subplot(4,1,2);
            plot(results.dist, results.long_g, 'LineWidth', 2);
            ylabel('Long Accel (g)'); grid on;
            % ylim([0 2]);
            
            subplot(4,1,3);
            plot(results.dist, results.gear, 'LineWidth', 2);
            ylim([1 6]);
            ylabel('Gear'); xlabel('Distance (m)'); grid on;

            subplot(4,1,4);
            plot(results.dist, results.engine_rpm, 'LineWidth', 2);
            ylabel('Engine RPM'); xlabel('Distance (m)'); grid on;
        end

        %% Plot Long Accel vs Speed
        function plotLongAccelVsVelocity(results)
            figure('Name', 'Accel Event Long Accel');
            set(gcf, 'Color', 'w'); % Make background white
            
            plot(results.vel .* 2.237, results.long_g, 'LineWidth', 2, 'Color', 'r');
            grid on;
            xlabel('Speed [mph]');
            ylabel('Longitudinal Acceleration [g]');
            title('Accel: Long G vs Vehicle Speed');
            ylim([0, max(results.long_g)+.2])
        end

        %% Aero Plots
        function plotAeroData(ggv, rho, frontal_area)
            figure('Name', 'Aero', 'Color', 'w');
    
            % 1. Downforce Plotgrid on;
            % Plot the raw data points from Excel
            subplot(2, 2, 1);
            plot(ggv.Aero.raw_mph, ggv.Aero.raw_downforce, 'bo', 'MarkerFaceColor', 'b', 'DisplayName', 'Raw Excel Data');
            
            % Re-calculate the "Modeled" force to verify the interpolation + scaling
            % using the speed vector from the GGV struct
            v_test = ggv.speed_mps;
            v_test_mph = v_test * 2.237;
            F_down_modeled = 0.5 * rho * frontal_area * ggv.Aero.Cl_interp_safe(v_test) .* v_test.^2;
            
            plot(v_test_mph, F_down_modeled, 'b-', 'LineWidth', 1.5, 'DisplayName', 'Model (Cl Interp)');
            xlabel('Speed [mph]');
            ylabel('Downforce [N]');
            title('Downforce');
            legend('Location', 'Best');
            
            % 2. Drag Plot
            subplot(2, 2, 2);
            
            plot(ggv.Aero.raw_mph, ggv.Aero.raw_drag, 'ro', 'MarkerFaceColor', 'r', 'DisplayName', 'Raw Excel Data');
            
            F_drag_modeled = 0.5 * rho * frontal_area * ggv.Aero.Cd_interp(v_test) .* v_test.^2;
            
            plot(v_test_mph, F_drag_modeled, 'r-', 'LineWidth', 1.5, 'DisplayName', 'Model (Cd Interp)');
            xlabel('Speed [mph]');
            ylabel('Drag [N]');
            title('Drag');
            legend('Location', 'Best');
            
            % 3. Balance (CoP) Plot
            subplot(2, 2, 3);
            grid on;
            % Convert decimal back to % for readability
            plot(ggv.Aero.raw_mph, ggv.Aero.raw_balance * 100, 'ko', 'MarkerFaceColor', 'k', 'DisplayName', 'Raw Data');
            
            bal_modeled = ggv.Aero.Bal_interp(v_test) * 100;
            plot(v_test_mph, bal_modeled, 'k-', 'LineWidth', 1.5, 'DisplayName', 'Model (Interp)');
            
            xlabel('Speed [mph]');
            ylabel('Front Aero Balance [%]');
            ylim([0 100]); % Force 0-100% scale
            title('Aero Balance Migration');
            legend('Location', 'Best');
            
            % 4. Efficiency (L/D) Plot
            subplot(2, 2, 4);
            grid on;
            % Calculate L/D for Raw Data
            L_D_raw = ggv.Aero.raw_downforce ./ ggv.Aero.raw_drag;
            plot(ggv.Aero.raw_mph, L_D_raw, 'mo', 'MarkerFaceColor', 'm', 'DisplayName', 'Raw L/D');
            
            % Calculate L/D for Model
            L_D_model = F_down_modeled ./ F_drag_modeled;
            plot(v_test_mph, L_D_model, 'm-', 'LineWidth', 1.5, 'DisplayName', 'Model L/D');
            
            xlabel('Speed [mph]');
            ylabel('L/D Ratio');
            title('Aerodynamic Efficiency');
            legend('Location', 'Best');
        end

        %% Plot Tractive Force Chart
        function plotTractiveForce(ggv)
            figure('Name', 'Tractive Force', 'Color', 'w');
            hold on;
            grid on;
            
            % 1. Plot Individual Gear Curves (Grey/Dashed)
            % Assumes ggv.TractiveForce.gears is [N_speeds x N_gears]
            [~, n_gears] = size(ggv.TractiveForce.gears);
            
            % Define colors for gears (fading from dark to light usually looks nice)
            gear_colors = winter(n_gears); 
            
            for g = 1:n_gears
                % Exclude the gear lines from the legend so it stays clean
                plot(ggv.speed_mps * 2.237, ggv.TractiveForce.gears(:, g), ...
                     '--','LineWidth', 1, 'Color', [0.6 0.6 0.6], 'HandleVisibility', 'off'); 
            end
            
            % 2. Plot the Forward Limits
            % Engine Limit (Thick Blue)
            plot(ggv.speed_mps * 2.237, ggv.TractiveForce.engine_limit, ...
                 'b', 'LineWidth', 2, 'DisplayName', 'Engine Tractive Limit');
            
            % Grip Limit (Thick Red)
            plot(ggv.speed_mps * 2.237, ggv.TractiveForce.grip_limit, ...
                 'r', 'LineWidth', 2, 'DisplayName', 'Tire Grip Limit');
            
            % 3. Plot the Resistive Forces
            total_resistance = ggv.TractiveForce.drag + ggv.TractiveForce.rolling_res;
            
            % Total Resistance (Thick Green)
            plot(ggv.speed_mps * 2.237, total_resistance, ...
                 'g', 'LineWidth', 2, 'DisplayName', 'Drag');
            
            
            % 4. Plot the "limiting" path (What the car actually does)
            % The minimum of Engine vs Grip
            actual_force = min(ggv.TractiveForce.engine_limit, ggv.TractiveForce.grip_limit);
            plot(ggv.speed_mps * 2.237, actual_force, ...
                 'k-.', 'LineWidth', 1.5, 'DisplayName', 'Actual Tractive Force');
            
            % Formatting
            ylim([0, inf]);
            xlabel('Speed [mph]');
            ylabel('Longitudinal Force [N]');
            title('Tractive Force vs Speed');
            legend('Location', 'Best');
        end

        %% Plot GGV and Grip limits vs Vehicle Speed
        function plotGGV(GGV)
            % Create a wide figure window
            figure('Name', 'GGV Map');
            
            %% Prepare Data for 3D Surface
            % Ensure column vectors for matrix math
            v_col = GGV.speed_mps(:); 
            lat_ratios = GGV.lat_ratios(:)'; 
            
            % Z-Axis: Speed grid
            Z_speed = repmat(v_col, 1, length(lat_ratios));
            
            % X-Axis: Lateral G grid (Right turns)
            X_lat_right = GGV.max_lat_g(:) * lat_ratios;
            
            % Y-Axis: Longitudinal G grids 
            Y_accel_right = GGV.ax_accel_surface;
            Y_brake_right = -GGV.ax_brake_surface; % Negated to point backwards
            
            % Mirror the data to create a full left-to-right envelope
            % We drop the first column (lat_ratio = 0) of the flipped array so we don't duplicate the centerline
            X_lat_full = [-fliplr(X_lat_right(:, 2:end)), X_lat_right];
            Y_accel_full = [fliplr(Y_accel_right(:, 2:end)), Y_accel_right];
            Y_brake_full = [fliplr(Y_brake_right(:, 2:end)), Y_brake_right];
            Z_speed_full = [fliplr(Z_speed(:, 2:end)), Z_speed];
            
            %% Subplot 1: 3D GGV Surface
            subplot(1, 2, 1);
            hold on; grid on;
            
            X_unified = [X_lat_full, fliplr(X_lat_full), X_lat_full(:,1)];
            Y_unified = [Y_brake_full, fliplr(Y_accel_full), Y_brake_full(:,1)];
            Z_unified = [Z_speed_full, fliplr(Z_speed_full), Z_speed_full(:,1)];

            % Plot as one perfectly sealed 3D manifold
            surf(X_unified, Y_unified, Z_unified, 'FaceAlpha', 0.8, 'EdgeColor', 'interp');

            title('3D GGV Surface');
            xlabel('Lateral G (A_y)');
            ylabel('Longitudinal G (A_x)');
            zlabel('Speed (m/s)');
            
            % Set viewing angle
            view(-35, 25); 
            
            % Force X and Y to have a 1:1 aspect ratio so the friction circle isn't distorted,
            % but scale Z down so the plot isn't stretched into a tall needle
            z_scale = max(v_col) / max(X_lat_full(:)) * 0.5; 
            daspect([1 1 z_scale]); 
            
            %% Subplot 2: 2D Pure Limits vs Speed
            subplot(1, 2, 2);
            hold on; grid on;
            
            % Plot the pure, uncombined limits extracted directly from the GGV array
            plot(v_col, GGV.max_lat_g(:), 'b-', 'LineWidth', 2, 'DisplayName', 'Max Lateral G');
            plot(v_col, GGV.max_accel_g(:), 'g-', 'LineWidth', 2, 'DisplayName', 'Max Accel G');
            plot(v_col, GGV.max_brake_g(:), 'r-', 'LineWidth', 2, 'DisplayName', 'Max Brake G (Magnitude)');
            
            title('Pure Physical Limits vs Speed');
            xlabel('Vehicle Speed (m/s)');
            ylabel('Absolute Acceleration (G)');
            legend('Location', 'best');
            
            % Add a subtle zero-line to ground the viewer
            yline(0, 'k--', 'HandleVisibility', 'off'); 
            
            % Optional: Add a secondary X-axis for mph if you prefer reading speeds in mph
            ax1 = gca;
            ax2 = axes('Position', ax1.Position, 'XAxisLocation', 'top', 'YAxisLocation', 'right', 'Color', 'none');
            ax2.XLim = ax1.XLim * 2.237; % Convert m/s limits to mph
            ax2.YLim = ax1.YLim;
            ax2.YTick = []; % Hide the right Y-axis ticks
            xlabel(ax2, 'Speed (mph)');
        end
        
        %% Plot Simulated Data against Logged Data
        function plotGForceValidation(sim_results, logged_data, event, filter)
            %   sim_results - struct from lap sim (needs distance, lat_g, long_g)
            %   logged_data - struct/table from real car (needs distance, lat_g, long_g)
        
            figure('Name', strcat(event, ' Validation Data Vs Distance'), 'Color', 'w');
            
            % Apply smooth to logged data
            if filter
                window_size = 5;
                logged_lat_g = smoothdata(logged_data.lat_g, 'sgolay', window_size);
                logged_long_g = smoothdata(logged_data.long_g, 'sgolay', window_size);
            else
                logged_lat_g = logged_data.lat_g;
                logged_long_g = logged_data.long_g;
            end

            % --- Subplot 1: Lateral Gs ---
            ax1 = subplot(3, 1, 1);
            hold on; grid on; box on;
            plot(sim_results.dist, sim_results.lat_g, 'b-',  'DisplayName', 'Simulated');
            plot(logged_data.distance, logged_lat_g, 'r-',  'DisplayName', 'Logged');
            
            title('Lateral Acceleration vs Distance');
            ylabel('Lateral G [g]');
            legend('Location', 'best');
        
            % --- Subplot 2: Longitudinal Gs ---
            ax2 = subplot(3, 1, 2);
            hold on; grid on; box on;
            plot(sim_results.dist, sim_results.long_g, 'b-', 'DisplayName', 'Simulated');
            plot(logged_data.distance, logged_long_g, 'r-',  'DisplayName', 'Logged');
            
            title('Longitudinal Acceleration vs Distance');
            xlabel('Distance [m]');
            ylabel('Longitudinal G [g]');
            legend('Location', 'best');

            % ---- Subplot 3: Vehicle Speed
            ax3 = subplot(3, 1, 3);
            hold on; grid on; box on;
            plot(sim_results.dist, sim_results.speed_mph, 'b-', 'DisplayName', 'Simulated');
            plot(logged_data.distance, logged_data.speed, 'r-', 'DisplayName', 'Logged');
            title('Vehicle Speed vs Distance');
            xlabel('Distance [m]');
            ylabel('Velocity [mph]');
            legend('Location', 'best');
        
            % Link the X-axes so zooming/panning is synchronized between the two plots
            linkaxes([ax1, ax2, ax3], 'x');
            
            % sgtitle('Lap Sim Validation: Simulated vs Logged Data', 'FontSize', 14, 'FontWeight', 'bold');
        end


        %% Plot Simulated and Logged Vehicle speed on a track map
        function plotSpeedComparisonMap(sim_results, logged_data, event)            
            % 1. Check if logged data has speed
            if ~isfield(logged_data, 'speed')
                error('Logged data does not contain a speed field. Check parse_motec_csv.');
            end

            [unique_dist, unique_idx] = unique(logged_data.distance, 'stable');
            unique_speed = logged_data.speed(unique_idx);
            unique_latg = logged_data.lat_g(unique_idx);
            
            % 2. Interpolate logged speed onto the simulated track's distance mesh
            % This aligns the real car's speed perfectly to the simulated X,Y coordinates
            logged_speed_interp = interp1(unique_dist, unique_speed, sim_results.dist, 'linear', 'extrap');
            logged_latg_interp = interp1(unique_dist, unique_latg, sim_results.dist, 'linear', 'extrap');
            
            % 3. Set up patch arrays
            % Patch requires row vectors ending in NaN to draw a continuous colored line
            x = sim_results.x(:)';
            y = sim_results.y(:)';
            z = zeros(size(x)); % 2D plot, so Z is zero
            
            % 4. Figure Setup
            figure('Name', strcat(event, ' Speed Map Comparison'), 'Color', 'w');
            
            % Find global min and max speeds so both colorbars use the exact same scale
            min_spd = min([min(sim_results.speed_mph), min(logged_speed_interp)]);
            max_spd = max([max(sim_results.speed_mph), max(logged_speed_interp)]);

            min_latg = min([min(sim_results.lat_g), min(logged_latg_interp)]);
            max_latg = max([max(sim_results.lat_g), max(logged_latg_interp)]);
            
            % --- Subplot 1: Simulated Speed ---
            ax1 = subplot(2, 2, 1);
            hold on; axis equal; grid on; box on;
            
            % Draw the continuous colored line
            patch([x nan], [y nan], [z nan], [sim_results.speed_mph(:)' nan], ...
                'FaceColor', 'none', 'EdgeColor', 'interp', 'LineWidth', 4);
            
            title('Simulated Speed');
            xlabel('X [m]'); ylabel('Y [m]');
            colormap(ax1, 'jet'); % 'jet' or 'parula' are best for speed maps
            c1 = colorbar;
            c1.Label.String = 'Speed';
            clim([min_spd, max_spd]); % Lock color scale
            
            % --- Subplot 2: Logged Speed ---
            ax2 = subplot(2, 2, 2);
            hold on; axis equal; grid on; box on;
            
            % Draw the continuous colored line
            patch([x nan], [y nan], [z nan], [logged_speed_interp(:)' nan], ...
                'FaceColor', 'none', 'EdgeColor', 'interp', 'LineWidth', 4);
            
            title('Real Logged Speed');
            xlabel('X [m]'); ylabel('Y [m]');
            colormap(ax2, 'jet');
            c2 = colorbar;
            c2.Label.String = 'Speed';
            clim([min_spd, max_spd]); % Lock color scale

            % Subplot 3: simulated Lateral G over track map
            ax3 = subplot(2, 2, 3);
            hold on; axis equal; grid on; box on;
            patch([x nan], [y nan], [z nan], [sim_results.lat_g(:)' nan], ...
                'FaceColor', 'none', 'EdgeColor', 'interp', 'LineWidth', 4);

            title('Simulated Lateral Gs');
            xlabel('X [m]'); ylabel('Y [m]');
            colormap(ax3, 'jet');
            c3 = colorbar;
            c3.Label.String = 'G';
            clim([min_latg, max_latg]); % Lock color scale

            % Subplot 4: logged Lateral G over track map
            ax3 = subplot(2, 2, 4);
            hold on; axis equal; grid on; box on;
            patch([x nan], [y nan], [z nan], [logged_latg_interp(:)' nan], ...
                'FaceColor', 'none', 'EdgeColor', 'interp', 'LineWidth', 4);

            title('Logged Lateral Gs');
            xlabel('X [m]'); ylabel('Y [m]');
            colormap(ax3, 'jet');
            c3 = colorbar;
            c3.Label.String = 'G';
            clim([min_latg, max_latg]); % Lock color scale

            
            % Link the X and Y axes! 
            % When you zoom in on a corner in Plot 1, Plot 2 will zoom to the exact same spot.
            linkaxes([ax1, ax2], 'xy');
            
            sgtitle('Track Map Speed Overlay: Simulated vs Real Car', 'FontSize', 14, 'FontWeight', 'bold');
        end

        function plotSpeedAndLatgOnTrack(results, event)
            figure('Name', sprintf('%s Track Maps', event));
            
            % Calculate Averages
            avg_speed = mean(results.speed_mph, 'omitnan');
            avg_lat_g = mean(abs(results.lat_g), 'omitnan'); % Absolute value to prevent left/right canceling out
            
            sgtitle(sprintf('%s Track Maps  |  Lap Time: %.2f s', event, results.lap_time), 'FontSize', 14, 'FontWeight', 'bold');
            
            % --- Left Subplot: Speed Overlay ---
            ax1 = subplot(1, 2, 1);
            scatter(results.x, results.y, 20, results.speed_mph, 'filled');
            colormap(ax1, jet); 
            c1 = colorbar;
            c1.Label.String = 'Speed [mph]';
            axis equal; grid on; box on;
            title(sprintf('Speed Map | Avg Speed: %.1f mph\n', avg_speed));
            xlabel('X Position [m]'); 
            ylabel('Y Position [m]');
            
            % --- Right Subplot: Lateral G Overlay ---
            ax2 = subplot(1, 2, 2);
            scatter(results.x, results.y, 20, results.lat_g, 'filled');
            
            % Center the color scale around 0 Gs for left/right symmetry
            max_g = max(abs(results.lat_g)); 
            clim(ax2, [-max_g, max_g]); % Use caxis([-max_g, max_g]) if on an older MATLAB version
            
            colormap(ax2, jet); 
            c2 = colorbar;
            c2.Label.String = 'Lateral G [g]';
            axis equal; grid on; box on;
            title(sprintf('Lateral G Map | Avg Lat G: %.2f g\n', avg_lat_g));
            xlabel('X Position [m]'); 
            ylabel('Y Position [m]');
            
            % Link the X and Y axes for synchronized zooming and panning
            linkaxes([ax1, ax2], 'xy');
        end

        function plotThermalEfficiency(car)
            % Create a new figure window
            figure('Name', 'Thermal Efficiency Verification', 'Color', 'w');
            
            % Set up the left Y-axis for Thermal Efficiency
            yyaxis left;
            hold on;
            grid on;
            
            % Define the fuels to test and their visual properties
            fuels = {'e85', '100octane', '93 octane'};
            labels = {'Sunoco E85R', 'Sunoco 260 GT (100 Oct)', '93 Octane'};
            colors = {'#0072BD', '#D95319', '#EDB120'}; % MATLAB default blue, orange, yellow
            
            % Save the original fuel type to restore it later
            if isfield(car, 'fuel_type')
                original_fuel = car.fuel_type;
            else
                original_fuel = '100 octane'; % Safe fallback
            end
            
            % Loop through each fuel, load its specs, and plot the curve
            for i = 1:length(fuels)
                car.fuel_type = fuels{i};
                car = load_fuelSpecs(car);
                
                % Convert decimal efficiency to percentage for readability
                eff_percent = car.fuel.eff_curve * 100;
                
                plot(car.engine_speed, eff_percent, 'Color', colors{i}, 'LineWidth', 2, 'DisplayName', labels{i});
            end
            
            % Format the primary axes
            ylabel('Brake Thermal Efficiency (%)', 'FontWeight', 'bold');
            ylim([15, 40]); % Lock bounds to realistic ICE efficiency ranges
            
            % Set up the right Y-axis for Engine Torque
            yyaxis right;
            plot(car.engine_speed, car.engine_torque, '--k', 'LineWidth', 1.5, 'DisplayName', 'Engine Torque');
            ylabel('Engine Torque (Nm)', 'FontWeight', 'bold');
            ylim([20, 60]);
            
            % Format the overall plot
            title('Brake Thermal Efficiency vs. Engine Speed', 'FontSize', 14);
            xlabel('Engine Speed (RPM)', 'FontWeight', 'bold');
            xlim([min(car.engine_speed), max(car.engine_speed)]);
            
            % Add legend
            legend('Location', 'northwest', 'FontSize', 10);
            
            % Restore the car struct to its original state
            car.fuel_type = original_fuel;
            car = load_fuelSpecs(car);
            hold off;
        end


        %% Plot engine histogram
        function engineRpmHistogram(engine_rpm)
            figure('Name', 'Engine Speed Histogram');
            histogram(engine_rpm);

            xlim([2000, max(engine_rpm + 500)]);
            xlabel("Engine Speed (RPM)");
            ylabel("Frequency");
            title("Engine Speed Histogram");

        end
    end
end
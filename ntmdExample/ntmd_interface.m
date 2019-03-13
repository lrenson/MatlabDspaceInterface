classdef ntmd_interface < dspace_interface
    % NTMD_INTERFACE  Interface to the NTMD rig.
    % Simulink model associated with Simulink model `CBCVacc.mdl'
    
    % To create the interface, simply type `rtc = ntmd_interface();' in
    % Matlab's command line. The variable `rtc' will allow to read and
    % modify the parameters of the Simulink model defined in the
    % constructor function below.
    
    % V0 by David A.W. Barton (david.barton@bristol.ac.uk) 2015
    % V1 by Ludovic Renson (l.renson@bristol.ac.uk) 2016
    
    properties
        fourier;
        datafields;
        averaging;
    end
    
    methods
        function obj = ntmd_interface()
            %NTMD_INTERFACE  Interface to the NTMD rig.
            
            % Add known dSpace variables
            obj.add_dspace_var('x', 'Labels/RelativeX');
            obj.add_dspace_var('x_coeffs', 'Labels/FourierX2');
            obj.add_computed_var('x_coeffs_ave', @(x)x.averaging.x_coeffs_ave);
            obj.add_computed_var('x_coeffs_var', @(x)x.averaging.x_coeffs_var);

            obj.add_dspace_var('x_target', 'Labels/Target');
            obj.add_dspace_var('x_target_coeffs', 'Model Root/ForceGen/Target/Value');

            obj.add_dspace_var('x_control', 'Model Root/ControlSwitch/Value');
            obj.add_dspace_var('x_Kp', 'Model Root/Controller/Kp/Value');
            obj.add_dspace_var('x_Kd', 'Model Root/Controller/Kd/Value');

            obj.add_dspace_var('out', 'Labels/ShakerInput');
            obj.add_dspace_var('out_coeffs', 'Labels/FourierShaker');
            obj.add_computed_var('out_coeffs_ave', @(x)x.averaging.out_coeffs_ave);
            obj.add_computed_var('out_coeffs_var', @(x)x.averaging.out_coeffs_var);

            obj.add_dspace_var('forcing_freq', 'Model Root/Freq/Value');
            obj.add_dspace_var('forcing_amp', 'Model Root/Ampl/Value');

            obj.add_dspace_var('base', 'Labels/x1');
            obj.add_dspace_var('base_control', 'Model Root/controlSwitchBase/Value');
            obj.add_dspace_var('base_Kp', 'Model Root/ControllerBase/Kp/Value');
            obj.add_dspace_var('base_Kd', 'Model Root/ControllerBase/Kd/Value');

            obj.add_dspace_var('mass', 'Labels/x2_abs');
            obj.add_dspace_var('force', 'Labels/LoadCell');
            
            obj.add_dspace_var('base_centre', 'Model Root/cent_x1/Value');
            obj.add_dspace_var('mass_centre', 'Model Root/cent_x2/Value');
            
            obj.add_dspace_var('run', 'Model Root/Start/Value');
            
            % Indices into the array of Fourier variables
            n_coeff = length(obj.par.x_coeffs);
            obj.fourier.n_modes = (n_coeff - 1)/2;
            obj.fourier.n_ave = 7; % Number of periods that are averaged to get the result
            obj.fourier.idx_DC = 1;
            obj.fourier.idx_AC = 2:n_coeff;
            obj.fourier.idx_fund = [2, 2 + obj.fourier.n_modes];
            obj.fourier.idx_higher = [(3:1 + obj.fourier.n_modes), (3 + obj.fourier.n_modes:n_coeff)];
            obj.fourier.idx_sin =  2 + obj.fourier.n_modes:n_coeff;
            obj.fourier.idx_cos = 2:1 + obj.fourier.n_modes;

            % Default options for the experiment
            obj.opt.samples = 1000; % Number of samples to record
            obj.opt.downsample = 0; % Number of samples to ignore for every sample recorded
            obj.opt.wait_time = 3; % Time (in secs) to wait for Fourier coefficients to settle
            obj.opt.max_waits = 15; % Maximum number of times to wait
            obj.opt.max_picard_iter = 7; % Maximum number of Picard iterations to do
            obj.opt.x_coeffs_var_tol_rel = 5e-3; % Maximum (normalised) variance of Fourier coefficients for steady-state behaviour
            obj.opt.x_coeffs_var_tol_abs = 5e-3; % Maximum (absolute) variance of Fourier coefficients for steady-state behaviour
            obj.opt.x_coeffs_tol = 1e-1; % Maximum tolerance for difference between two Fourier coefficients (mm)

            % Data recording fields
            obj.datafields.stream_id = 1; % The stream to use for data recording (N/A)
            obj.datafields.static_fields = {'x_Kp', 'x_Kd', 'x_control', ...
                                'base_Kp', 'base_Kd', 'base_control', ...
                                'sample_freq', 'base_centre', 'mass_centre'};
            obj.datafields.dynamic_fields = {'forcing_freq', 'forcing_amp', ...
                                'x_coeffs_ave', 'x_coeffs_var', ...
                                'x_target_coeffs', ...
                                'out_coeffs_ave', 'out_coeffs_var'};
            obj.datafields.stream_fields = {'x', 'x_target', ...
                                'base', 'mass', 'force', 'out'}; 
            
            % Default control gains (that work!)
            obj.par.base_Kp = 0.02;
            obj.par.base_Kd = 0.001;
            obj.par.base_control = 1;
            obj.par.x_Kp = -0.008;
            obj.par.x_Kd = -0.0004;

            % Create variables for averaging
            obj.opt.n_ave = 5;
            obj.averaging.x_coeffs_ave = zeros(1, n_coeff);
            obj.averaging.x_coeffs_var = zeros(1, n_coeff);
            obj.averaging.x_coeffs_arr = zeros(obj.fourier.n_ave, n_coeff);
            obj.averaging.out_coeffs_ave = zeros(1, n_coeff);
            obj.averaging.out_coeffs_var = zeros(1, n_coeff);
            obj.averaging.out_coeffs_arr = zeros(obj.fourier.n_ave, n_coeff);
            obj.averaging.last_freq = obj.get_par('forcing_freq');
            obj.averaging.timer = timer('BusyMode', 'drop', 'ExecutionMode', 'fixedRate', 'TimerFcn', @obj.update_averages);
            obj.averaging.timer.Period = max([round((1/obj.averaging.last_freq)*1000)/1000, 0.1]); % Limit to 10 Hz updates
            start(obj.averaging.timer);

            % Set the underlying device name
            obj.opt.device = [obj.opt.device ' - NTMD'];
            
            % Set the center point
            obj.par.mass_centre = 135;
            
            % Set everything moving
            obj.par.run = 1;
        end

        function delete(obj)
            % DELETE  Destroy the interface to dSpace.
            stop(obj.averaging.timer);
            delete(obj.averaging.timer);
        end
        
        function update_averages(obj, varargin)
            % UPDATE_AVERAGES  Get new data for the x and out coefficients and update
            % the respective averages and variances.
            obj.averaging.x_coeffs_arr(1:end-1, :) = obj.averaging.x_coeffs_arr(2:end, :);
            obj.averaging.x_coeffs_arr(end, :) = obj.get_par('x_coeffs');
            obj.averaging.x_coeffs_ave = mean(obj.averaging.x_coeffs_arr);
            obj.averaging.x_coeffs_var = var(obj.averaging.x_coeffs_arr);
            obj.averaging.out_coeffs_arr(1:end-1, :) = obj.averaging.out_coeffs_arr(2:end, :);
            obj.averaging.out_coeffs_arr(end, :) = obj.get_par('out_coeffs');
            obj.averaging.out_coeffs_ave = mean(obj.averaging.out_coeffs_arr);
            obj.averaging.out_coeffs_var = var(obj.averaging.out_coeffs_arr);
            forcing_freq = obj.get_par('forcing_freq');
            if obj.averaging.last_freq ~= forcing_freq
                obj.averaging.last_freq = forcing_freq;
                stop(obj.averaging.timer);
                obj.averaging.timer.Period = max([round((1/obj.averaging.last_freq)*1000)/1000, 0.1]); % Limit to 10 Hz updates
                start(obj.averaging.timer);
            end
        end
    end
    
end

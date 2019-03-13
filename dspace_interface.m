classdef (ConstructOnLoad) dspace_interface < handle
    % DSPACE_INTERFACE  Interface to the dSpace device.
    
    % !!! May not be compatible with most recent versions of Dspace and
    % ControlDesk !!!
    
    % V0 by David A.W. Barton (david.barton@bristol.ac.uk) 2015
    % V1 by Ludovic Renson (l.renson@bristol.ac.uk) 2016
    
    properties (Hidden)
        stream_opts;
    end
    
    properties
        dspace_vars;
        computed_vars;
        par;
        opt;
    end
    
    methods
        
        function obj = dspace_interface()
            %DSPACE_INTERFACE  Interface to the dSpace device.
            
            % Set up what board we are using
            mlib('SelectBoard', 'DS1104');
            % Create a parameters object
            obj.par = dspace_parameters(obj);
            % Add the time step to the list of dSpace variables
            obj.add_dspace_var('time_step', 'modelStepSize');
            % Add the sample frequency to the list of computed variables
            obj.add_computed_var('sample_freq', @(x)(round(1/x.get_par('time_step'))));
            % Set the underlying device name
            obj.opt.device = 'dSpace';
        end
        
        function add_dspace_var(obj, var_name, var_address)
            % ADD_DSPACE_VAR  Add a variable to the list of known variables.
            % 
            % OBJ.ADD_DSPACE_VAR(NAME, ADDRESS) adds the variable known as NAME to the
            % list of known variables. ADDRESS is the address of that variable known to
            % dSpace (for example, 'Model Root/X/Value').

            % Store the handle to the variable
            obj.dspace_vars.(var_name) = mlib('GetTrcVar', var_address);
            obj.par.add_property(var_name);
        end

        function add_computed_var(obj, var_name, var_func)
            % ADD_COMPUTED_VAR  Add a variable to the list of computed variables.
            % 
            % OBJ.ADD_COMPUTED_VAR(NAME, FUNC) adds the variable known as NAME to the
            % list of computed variables. FUNC is called with OBJ as the first
            % parameter to compute the value of the variable. For example,
            %
            % obj.add_computed_var('sample_freq', @(x)round(1/x.get_par('time_step')));
            
            % Store the function to compute the value of the variable
            obj.computed_vars.(var_name) = var_func;
            obj.par.add_property(var_name);
        end
        
        function set_par(obj, names, values)
            % SET_PAR  Set the values of the specified parameters.
            %
            % OBJ.SET_PAR(NAME, VALUE) sets the value of the parameter NAME to VALUE.
            % Both NAME and VALUE can be cell arrays in the case of setting multiple
            % parameter values simultaneously.
            if ~iscell(names)
                names = {names};
                values = {values};
            end
            % Iterate over the supplied names
            for i = 1:length(names)
                if isfield(obj.dspace_vars, names{i})
                    % Write to dSpace
                    mlib('Write', obj.dspace_vars.(names{i}), 'Data', values{i});
                elseif isfield(obj.computed_vars, names{i})
                    error('Read only variable: %s', names{i});
                else
                    error('Unknown variable: %s', names{i});
                end
            end
        end
        
        function values = get_par(obj, names)
            % GET_PAR  Get the values of the specified parameters.
            %
            % OBJ.GET_PAR(NAME) gets the value of the parameter NAME. NAME can be a
            % cell array to get multiple parameter values simultaneously.
            if ~iscell(names)
                names = {names};
                islist = false;
            else
                islist = true;
            end
            % Iterate over the supplied names
            values = cell(size(names));
            for i = 1:length(names)
                if isfield(obj.dspace_vars, names{i})
                    % Read from dSpace
                    values{i} = mlib('Read', obj.dspace_vars.(names{i}));
                elseif isfield(obj.computed_vars, names{i})
                    % Calculate computed value
                    values{i} = obj.computed_vars.(names{i})(obj);
                else
                    error('Unknown variable: %s', names{i});
                end
            end
            % Return as a list or raw data depending on what was passed originally
            if ~islist
                values = values{1};
            end
        end
        
        function set_stream(obj, ~, parameters, samples, downsample)
            % SET_STREAM  Set stream recording properties.
            %
            % OBJ.SET_STREAM(ID, NAMES, SAMPLES, DOWNSAMPLE) sets the stream with
            % identifier ID (where multiple streams are available) to record the
            % parameters given by the cell array NAMES. SAMPLES data points are
            % recorded and DOWNSAMPLE data points are discarded between each recorded
            % sample.
            %
            % Example
            %
            %   rtc.set_stream(0, {'x', 'out'}, 1000, 0);
            %
            % will set stream id 0 to record the parameters x and out. 1000 samples
            % will be returned with no data discarded.
            args = {'Set'}; 
            if exist('samples', 'var') && ~isempty(samples)
                if samples > 0
                    args = [args {'NumSamples', samples}];
                end
            end
            if exist('downsample', 'var') && ~isempty(downsample)
                if downsample >= 0
                    args = [args {'Downsampling', downsample+1}];
                end
            end
            if exist('parameters', 'var') && ~isempty(parameters)
                if ~iscell(parameters)
                    parameters = {parameters};
                end
                handles = [];
                for i = 1:length(parameters)
                    if ~isfield(obj.dspace_vars, parameters{i})
                        error('Unknown variable for streaming: %s', parameters{i});
                    end
                    handles = [handles; obj.dspace_vars.(parameters{i})]; %#ok<AGROW>
                end
                obj.stream_opts.parameters = parameters;
                args = [args {'TraceVars', handles}];
            end
            mlib(args{:});
        end
            
        function data = get_stream(obj, ~, return_struct)
            % GET_STREAM  Get the data from a particular stream.
            %
            % OBJ.GET_STREAM(ID) returns an array of data recorded in the stream given
            % by ID. If the stream is not ready, no data is returned.
            %
            % OBJ.GET_STREAM(ID, true) returns a structure with named fields containing
            % the data recorded in the stream given by ID.
            %
            % See also START_STREAM.
            if mlib('CaptureState') == 0
                raw_data = mlib('FetchData');
                if exist('return_struct', 'var') && return_struct
                    for i = 1:length(obj.stream_opts.parameters)
                        data.(obj.stream_opts.parameters{i}) = raw_data(i, :);
                    end
                else
                    data = raw_data;
                end
            else
                data = [];
            end
        end

        function result = start_stream(~, ~)
            % START_STREAM  Start a stream recording.
            %
            % OBJ.START_STREAM(ID) starts the stream given by ID recording data with
            % the current parameters from SET_STREAM.
            %
            % See also SET_STREAM.
            mlib('StartCapture');
            result = true;
        end

        function data = run_stream(obj, stream, varargin)
            % RUN_STREAM  Start a stream recording and then return the captured data.
            %
            % OBJ.RUN_STREAM(ID) starts the stream given by ID and then returns the
            % captured data.
            %
            % OBJ.RUN_STREAM(ID, Name, Value) overrides the default options for running
            % the stream.
            %
            % Options
            %
            %     start: allowed values are true or false. Default true.
            %         Whether or not to start the stream running before waiting for
            %         available captured data.
            %
            %     wait_period: allowed values are a > 0. Default 0.1.
            %         The period of time the function should pause before checking if
            %         there is captured data available.
            %
            %     struct: allowed values are true or false. Default false.
            %         Whether or not to return the data as a structure.
            %
            % See also START_STREAM, GET_STREAM.
            p = inputParser();
            if ismethod(p, 'addParameter')
                % New versions of Matlab
                add_par = @p.addParameter;
            else
                % Old versions of Matlab
                add_par = @p.addParamValue;
            end
            add_par('start', true, @islogical);
            add_par('wait_period', 0.1, @(x)(x > 0));
            add_par('struct', false, @islogical);
            p.parse(varargin{:});
            if p.Results.start
                if ~obj.start_stream(stream)
                    error('Failed to start stream - perhaps bad parameters');
                end
            end
            while mlib('CaptureState') ~= 0
                pause(p.Results.wait_period);
            end
            data = obj.get_stream(stream, p.Results.struct);
        end
            
    end
    
end


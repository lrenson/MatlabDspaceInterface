classdef dspace_parameters < dynamicprops
    %DSPACE_PARAMETERS A helper class to easily access device parameters.
    % V0 by David A.W. Barton (david.barton@bristol.ac.uk) 2015
    % V1 by Ludovic Renson (l.renson@bristol.ac.uk) 2016
    properties (Hidden)
        dspace_;
        str_;
    end
    
    methods
        function disp(obj)
            fprintf(obj.str_);
        end
    end

    methods
        function obj = dspace_parameters(dspace)
            obj.dspace_ = dspace;
            obj.str_ = 'Accessible dSpace parameters:\n';
        end
        
        function add_property(obj, names)
            if ~iscell(names)
                names = {names};
            end
            for i = 1:length(names)
                name = names{i};
                obj.str_ = [obj.str_, '\t', name, '\n']; 
                prop = obj.addprop(name);
                prop.GetMethod = @(obj)obj.dspace_.get_par(name);
                prop.SetMethod = @(obj, value)obj.dspace_.set_par(name, value);
                prop.Dependent = true;
                prop.SetObservable = true;
                prop.Transient = false;
            end
        end
    end        
    
    methods (Static = true)
        function obj = loadobj(~)
            obj = [];
        end
    end
    
end

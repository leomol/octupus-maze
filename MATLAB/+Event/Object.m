classdef Object
    properties (Access = private)
        parent
        id
    end
    
    methods
        function obj = Object(parent, id)
            obj.parent = parent;
            obj.id = id;
        end
        
        function delete(obj)
            if Objects.isValid(obj.parent)
                obj.parent.unregister(obj.id);
            end
        end
    end
end
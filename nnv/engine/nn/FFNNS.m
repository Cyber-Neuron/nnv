classdef FFNNS < handle
    % FFNNS Class is a new feedforward network class used to replace the old
    % FFNN in the future, FFNNS does not support polyhedron-based
    % reachability analysis methods.
    % Author: Dung Tran
    % Date: 27/2/2019
    
    properties
        Layers = []; % An array of Layers, eg, Layers = [L1 L2 ...Ln]
        nL = 0; % number of Layers
        nN = 0; % number of Neurons
        nI = 0; % number of Inputs
        nO = 0; % number of Outputs
        
        % properties for reach set computation
        
        reachMethod = 'star';    % reachable set computation scheme, default - 'star'
        reachOption = []; % parallel option, default - non-parallel computing
        numCores = 0; % number of cores (workers) using in computation
        inputSet = [];  % input set
        reachSet = [];  % reachable set for each layers
        outputSet = []; % output reach set
        reachTime = []; % computation time for each layers
        totalReachTime = 0; % total computation time
        
    end
    
    
    methods % constructor, evaluation, sampling, print methods
        
        % constructor
        function obj = FFNNS(Layers)
            nL = size(Layers, 2); % number of Layer
            for i=1:nL
                L = Layers(i);
                if ~isa(L, 'LayerS')
                    error('Element %d of Layers array is not a LayerS object', i);
                end
            end
            
            % check consistency between layers
            for i=1:nL-1
                if size(Layers(i).W, 1) ~= size(Layers(i + 1).W, 2)
                    error('Inconsistent dimensions between Layer %d and Layer %d', i, i + 1);
                end
            end
            
            obj.Layers = Layers;
            obj.nL = nL;    % number of layers
            obj.nI = size(Layers(1).W, 2); % number of inputs
            obj.nO = size(Layers(nL).W, 1); % number of outputs
            
            nN = 0;
            for i=1:nL
                nN = nN + Layers(i).N;
            end
            obj.nN = nN; % number of neurons
            
        end
        
        
        % Evaluation of a FFNN
        function y = evaluate(obj, x)
            % Evaluation of this FFNN
            % @x: input vector x
            % @y: output vector y
            
            y = x; 
            for i=1:obj.nL
                y = obj.Layers(i).evaluate(y);
            end
        
        end
        
        % Sample of FFNN
        function Y = sample(obj, V)
            % sample the output of each layer in the FFNN based on the
            % vertices of input set I, this is useful for testing.
            % @V : array of vertices to evaluate
            % @Y : output which is a cell array
        
            In = V;
            for i=1:obj.nL
                In = obj.Layers(i).sample(In);
            end          
            Y = In;
        end
        
        
        % print information to a file
        function print(obj, file_name)
            % @file_name: name of file you want to store all data
            % information
            f = fopen(file_name, 'w');
            fprintf(f, 'Feedforward Neural Network Information\n');
            fprintf(f, '\nNumber of layers: %d', obj.nL);
            fprintf(f, '\nNumber of neurons: %d', obj.nN);
            fprintf(f, '\nNumber of inputs: %d', obj.nI);
            fprintf(f, '\nNumber of outputs: %d', obj.nO);
            
            if ~isempty(obj.reachSet)
                fprintf(f, '\n\nReach Set Information');
                fprintf(f, '\nReachability method: %s', obj.reachMethod);
                fprintf(f, '\nNumber of cores used in computation: %d', obj.numCores);
                
                for i=1:length(obj.reachSet)-1
                    fprintf(f, '\nLayer %d reach set consists of %d sets that are computed in %.5f seconds', i, length(obj.reachSet{1, i}), obj.reachTime(i));
                end
                fprintf(f, '\nOutput Layer reach set consists of %d sets that are computed in %.5f seconds', length(obj.reachSet{1, obj.nL}), obj.reachTime(obj.nL)); 
                fprintf(f, '\nTotal reachable set computation time: %.5f', obj.totalReachTime);
                
            end
               
        end
        
        
        % start parallel pool for computing
        function start_pool(obj)
            
            if obj.numCores > 1
                poolobj = gcp('nocreate'); % If no pool, do not create new one.
                if isempty(poolobj)
                    parpool('local', obj.numCores); 
                else
                    if poolobj.NumWorkers ~= obj.numCores
                        delete(poolobj); % delete the old poolobj
                        parpool('local', obj.numCores); % start the new one with new number of cores
                    end                    
                end
            end   
            
        end
        
        
         
    end
    
    
    methods % reachability analysis method
        
        function [S, t] = reach(varargin)            
            % @I: input set, a star set          
            % @method: = 'star' -> compute reach set using stars
            %            'abs-dom' -> compute reach set using abstract
            %            domain (support in the future)
            %            'face-latice' -> compute reach set using
            %            face-latice (support in the future)
            
            % @R: output set 
            % @t : computation time 
            
            % @numOfCores: number of cores you want to run the reachable
            % set computation, @numOfCores >= 1, maximum is the number of
            % cores in your computer. We also can run this method on a
            % clusters. You need to change: parpool('local', numOfCores) to
            % parcluster(your_cluster_profile), you also need to set up
            % your local clusters with installed MPT toolbox also. see: 
            % https://www.mathworks.com/help/distcomp/discover-clusters-and-use-cluster-profiles.html
           
            
            % parse inputs 
            switch nargin
                case 4
                    obj = varargin{1}; % FFNNS object
                    obj.inputSet = varargin{2}; % input set
                    obj.reachMethod = varargin{3}; % reachability analysis method
                    obj.numCores = varargin{4}; % number of cores used in computation
                    
                case 3
                    obj = varargin{1};
                    obj.inputSet = varargin{2};
                    obj.reachMethod = varargin{3};
                    obj.numCores = 1;
                    
                case 2
                    obj = varargin{1};
                    obj.inputSet = varargin{2};
                    obj.reachMethod = 'exact-star';
                    obj.numCores = 1;
                    
                otherwise
                    error('Invalid number of input arguments (should be 1, 2 or 3)');
            end
            
            
            % if reachability analysis method is an over-approximate
            % method, we use 1 core for computation
            if ~strcmp(obj.reachMethod, 'exact-star')
                obj.numCores = 1;
            end
            
            % Zonotope method accepts both star and zonotope input set
            if strcmp(obj.reachMethod, 'approx-zono') && isa(varargin{2}, 'Star')
                obj.inputSet = varargin{2}.getZono;
            end
            
            if obj.numCores == 1
                obj.reachOption = []; % don't use parallel computing
            else
                obj.reachOption = 'parallel';
            end
            
            obj.reachSet = cell(1, obj.nL);
            obj.reachTime = [];
            
            % start parallel pool in Matlab
            if obj.numCores > 1
                obj.start_pool;
            end
                        
            % compute reachable set
            In = obj.inputSet;
                        
            for i=1:obj.nL               
                
                fprintf('\nComputing reach set for Layer %d ...', i);
                
                % estimate reachability analysis time from the second layer
                if i > 1
                    nP = length(obj.reachSet{1, i - 1});
                    if i==2
                        nP1 = 1;
                    else
                        nP1 = length(obj.reachSet{1, i-2});
                    end
                    rt = obj.reachTime(i-1);
                    
                    estimatedTime = rt*(nP/nP1)*(obj.Layers(i).N / obj.Layers(i-1).N);
                    
                    fprintf('\nEstimated computation time: ~ %.5f seconds', estimatedTime);
                end
                
                st = tic;
                In = obj.Layers(i).reach(In, obj.reachMethod, obj.reachOption);
                t1 = toc(st);
                
                obj.reachSet{1, i} = In;
                obj.reachTime = [obj.reachTime t1];
                
                fprintf('\nExact computation time: %.5f seconds', t1);               
                fprintf('\nNumber of reachable set at the output of layer %d: %d', i, length(In));               
                               
            end
            
            obj.outputSet = In;
            obj.totalReachTime = sum(obj.reachTime);
            S = obj.outputSet;
            t = obj.totalReachTime;                      
            fprintf('\nTotal reach set computation time: %.5f seconds', obj.totalReachTime);
            fprintf('\nTotal number of output reach sets: %d', length(obj.outputSet));
            
        end
        
        
    end
    
    
    methods % checking safety method or falsify safety property
        
        function [safe, t, counter_inputs] = isSafe(varargin)
            % 1: @I: input set, need to be a star set
            % 2: @U: unsafe region, a set of HalfSpaces
            % 3: @method: = 'star' -> compute reach set using stars
            %            'abs-dom' -> compute reach set using abstract
            %            domain (support in the future)
            %            'face-latice' -> compute reach set using
            %            face-latice (support in the future)
            % 4: @numOfCores: number of cores you want to run the reachable
            % set computation, @numOfCores >= 1, maximum is the number of
            % cores in your computer.
            
            % 5: @n_samples : number of simulations used for falsification if
            % using over-approximate reachability analysis, i.e.,
            % 'approx-zono' or 'abs-dom' or 'abs-star'
            % note: n_samples = 0 -> do not do falsification
            
                       
            % @safe: = 1 -> safe, = 0 -> unsafe, = 2 -> uncertain 
            % @t : verification time 
            % @counter_inputs
            
            % author: Dung Tran
            % date: 3/27/2019
            
            % parse inputs 
            switch nargin
                
                case 6
                    
                    obj = varargin{1}; % FFNNS object
                    I = varargin{2};
                    U = varargin{3};
                    method = varargin{4};
                    n_samples = varargin{5}; 
                    numOfCores = varargin{6};
                    
                    
                 case 5
                    
                    obj = varargin{1}; % FFNNS object
                    I = varargin{2};
                    U = varargin{3};
                    method = varargin{4};
                    n_samples = varargin{5}; 
                    numOfCores = 1;
                    
                                                    
                case 4
                    
                    obj = varargin{1}; % FFNNS object
                    I = varargin{2};
                    U = varargin{3};
                    method = varargin{4};
                    n_samples = 1000; % using 1000 samples
                    numOfCores = 1;
     
                case 3
                    
                    obj = varargin{1}; % FFNNS object
                    I = varargin{2};
                    U = varargin{3};
                    method = 'exact-star';
                    n_samples = 0; 
                    numOfCores = 1;
                    
                otherwise
                    error('Invalid number of input arguments (should be 3, 4, 5 or 7), please look at ../tests/nn/ffnns/ for usages of this method');
            end
                              
            start = tic;
                        
            if isempty(U)
                error('Please specify unsafe region using Half-space class');
            end
            
            % performing reachability analysis
            [R, ~] = obj.reach(I, method, numOfCores);        
                      
            % check safety
            n = length(R);
            m = length(U); 
            R1 = [];
            for i=1:n
                if isa(R(i), 'Zono')
                    B = R(i).getBox;
                    R1 = [R1 B.toStar]; % transform to star sets;
                else
                    R1 = [R1 R(i)];
                end
            end
                                    
            violate_inputs = [];            
            
            if numOfCores == 1

                for i=1:n
                    
                    for j=1:m
                        
                        S = R1(i).intersectHalfSpace(U(j).G, U(j).g);
                        if ~isempty(S) && strcmp(method, 'exact-star')
                            I1 = Star(I.V, S.C, S.d); % violate input set
                            violate_inputs = [violate_inputs I1];
                        else
                            violate_inputs = [violate_inputs S];
                        end

                    end
                    
                end

            elseif numOfCores > 1

                parfor i=1:n 

                     for j=1:m
                        
                        S = R1(i).intersectHalfSpace(U(j).G, U(j).g);
                        if ~isempty(S) && strcmp(method, 'exact-star')
                            I1 = Star(I.V, S.C, S.d); % violate input set
                            violate_inputs = [violate_inputs I1];
                        else
                            violate_inputs = [violate_inputs S];
                        end

                    end

                end


            end
            
            
            if isempty(violate_inputs)
                
                safe = 1;  
                counter_inputs = []; 
                fprintf('\nThe network is safe');
                
            else

                if strcmp(method, 'exact-star')
                    
                    safe = 0;  
                    counter_inputs = violate_inputs; % exact-method return complete counter input set
                    fprintf('\nThe network is unsafe, counter inputs contains %d stars', length(counter_inputs));
                    
                else
                    
                    if n_samples == 0
                        fprintf('\nDo not do falsification since n_samples = 0, you can choose to do falsification by set n_samples value > 0');
                        safe = 2;
                        counter_inputs = [];
                    else
                        
                        counter_inputs = obj.falsify(I, U, n_samples);
                    
                        if isempty(counter_inputs)
                            safe = 2;
                            fprintf('\nSafety is uncertain under using %d samples to falsify the network', n_samples);
                            fprintf('\nYou can try to increase the samples for finding counter inputs');
                        else
                            safe = 0;
                            fprintf('\nThe network is unsafe, %d counter inputs are found using %d simulations', length(counter_inputs), n_samples);
                        end

                        
                    end
                    
                    
                end


            end

            t = toc(start);
             
            
        end
                
        
        % falsify safety property using random simulation        
        function counter_inputs = falsify(obj, I, U, n_samples)
            % @input: star set input
            % @U: unsafe region, a set of HalfSpaces
            % @n_samples: number of samples used in falsification
            % @counter_inputs: counter inputs that falsify the property
            
            % author: Dung Tran
            % date: 3/27/2019
            
            counter_inputs = [];
            
            if ~isa(I, 'Star')
                error('Input set is not a star set');
            end
            
            m = length(U);
            
            for i=1:m
                if ~isa(U(i), 'HalfSpace')
                    error('%d^th unsafe region is not a HalfSpace', i);
                end
            
            end
            
            if n_samples < 1
                error('Invalid number of samples');
            end
            
            V = I.sample(n_samples);
            
            n = size(V, 2); % number of samples 
           
            for i=1:n
                
                y = obj.evaluate(V(:, i));
                
                for j=1:m
                    if U(j).contains(y)
                        counter_inputs = [counter_inputs V(:, i)];
                    end
                end
                
            end
            
            
        end
        
         
    end
    
    
    methods % checking robustness and get robustness bound of feedforward networks
        
        
        % Problem description:
        % checking robustness of FFNN corresponding to an input and
        % L_infinity norm bound disturbance
        
        % x is input, x' is a disturbed input such that ||x'- x|| <= e
        % y = FFNN(x), and y' = FFNN(x')
        % FFNN is called robust if y' is in a robust region RB(y') defined by user
        % for example, let F is image classification network
        % inputs of F is an 28x28 = 784 pixel images, F has one output with
        % range between 0 to 9 to reconize 10 digits, 0, 1, 2 ..., 9
        
        % let consider digit one as an input x, we disturb digit one with
        % some bounded disturabnce e, we have ||x' - x|| <= e
        
        % to be called robust, F need produce the output sastify 0.5 <= y' <= 1.5
        % If output is violated this specification, F may misclasify digit
        % one. Thefore the un-robust regions in this case is S1 = y' < 0.5 and S2 = y'> 1.5
        
        % If robustness is not guaranteed, the method search for some
        % adverserial examples, i.e., find some x' that makes F violate the
        % robustness property.
        
        function [robust, t, adv_inputs] = isRobust(varargin)
            % 1: @input_vec: input vector x
            % 2: @dis_bound: disturbance bound
            % 3: @un_robust_reg: un-robust-region, a star
            % 4: @method: = 'exact-star' or 'approx-star' or 'approx-zono' or 'abs-dom'
            % 5: @lb_allowable: allowable lower bound of disturbed input:    lb_allowable(i) <= x'[i]
            % 6: @ub_allowable: allowable upper bound of disturbed output:    ub_allowable(i) >= x'[i] 
            % x' is the disturbed vector by disturbance bound, |x' - x| <= dis_bound
            % x'[i] >= lb_allowable, x'[i] <= ub_allowable[i]
            % 7: @n_samples: number of samples used to find counter examples
            % if using over-approximate reachability analysis methods
            % 8: @numCores:  number of cores used in computation
            
            
            % @robust: = 1-> robust
            %        : = 0 -> unrobust
            %        : = 2 -> uncertain, cannot find counter example
            % @adv_inputs: adverserial inputs
            
            % author: Dung Tran
            % date: 3/27/2019
            
            
            start = tic; 
            % parse inputs
            switch nargin
                case 9
                    obj = varargin{1}; % FFNNS object
                    input_vec = varargin{2}; % input vec
                    dis_bound = varargin{3}; % disturbance bound
                    un_robust_reg = varargin{4}; % un-robust region
                    method = varargin{5}; % reachability analysis method
                    lb_allowable = varargin{6}; % allowable lower bound on disturbed inputs
                    ub_allowable = varargin{7}; % allowable upper bound on disturbed inputs
                    n_samples = varargin{8}; % number of samples used for finding counter examples
                    num_cores = varargin{9}; % number of cores used in computation
                    
                    % check consistency
                    if ~isempty(lb_allowable) && ((length(lb_allowable) ~= length(ub_allowable)) || (length(lb_allowable) ~= length(input_vec)))
                        error('Inconsistent dimensions between allowable lower-, upper- bound vectors and input vector');
                    end
                    
                case 8
                    
                    obj = varargin{1}; % FFNNS object
                    input_vec = varargin{2}; % input vec
                    dis_bound = varargin{3}; % disturbance bound
                    un_robust_reg = varargin{4}; % un-robust region
                    method = varargin{5}; % reachability analysis method
                    lb_allowable = varargin{6}; % allowable lower bound on disturbed inputs
                    ub_allowable = varargin{7}; % allowable upper bound on disturbed inputs
                    n_samples = varargin{8}; % number of samples used for finding counter examples
                    num_cores = 1; % number of cores used in computation
                    
                case 6
                    
                    obj = varargin{1}; % FFNNS object
                    input_vec = varargin{2}; % input vec
                    dis_bound = varargin{3}; % disturbance bound
                    un_robust_reg = varargin{4}; % un-robust region
                    method = varargin{5}; % reachability analysis method
                    lb_allowable =[]; % allowable lower bound on disturbed inputs
                    ub_allowable = []; % allowable upper bound on disturbed inputs
                    n_samples = varargin{6}; % number of samples used for finding counter examples
                    num_cores = 1; % number of cores used in computation
                    
                case 5
                    
                    obj = varargin{1}; % FFNNS object
                    input_vec = varargin{2}; % input vec
                    dis_bound = varargin{3}; % disturbance bound
                    un_robust_reg = varargin{4}; % un-robust region
                    method = varargin{5}; % reachability analysis method
                    lb_allowable =[]; % allowable lower bound on disturbed inputs
                    ub_allowable = []; % allowable upper bound on disturbed inputs
                    n_samples = 1000; % use 1000 number of samples used for finding counter examples
                    num_cores = 1; % number of cores used in computation
                    
                    
                otherwise
                    error('Invalid number of input arguments (should be 4 or 5 or 8), please look at ../tests/nn/ffnns/ for usages of this method');
            end
            
            
            % construct input set
            n = length(input_vec);
            lb = input_vec;
            ub = input_vec;
            
            if nargin == 8
                
                for i=1:n
                    
                    if lb(i) - dis_bound > lb_allowable(i)
                        lb(i) = lb(i) - dis_bound;
                    else
                        lb(i) = lb_allowable(i);
                    end
                    if ub(i) + dis_bound < ub_allowable(i)
                        ub(i) = ub(i) + dis_bound;
                    else
                        ub(i) = ub_allowable(i);
                    end  
                    
                end
                
            else    
                for i=1:n    
                    lb(i) = lb(i) - dis_bound;
                    ub(i) = ub(i) + dis_bound;
                end
            end
            
            
            % input set to check robustness
            I = Star(lb, ub);
                        
            [robust, ~, adv_inputs] = obj.isSafe(I, un_robust_reg, method, n_samples, num_cores);
            
            if robust == 1
                fprintf('\nThe network is robust with the disturbance dis_bound = %.5f', dis_bound);
            elseif robust == 0
                fprintf('\nThe network is not robust with the disturbance dis_bound = %.5f, counter examples are found', dis_bound);
            elseif robust == 2
                fprintf('\nThe robustness of the network is uncertain with the disturbance dis_bound = %.5f, we cannot find counter examples, you can try again with a larger n_samples', dis_bound);
            end
                            
            t = toc(start);
                       
        end
        
        
        % find maximum robustness value, i.e., maximum disturbance bound
        % that the network is still robust
        
        function [robustness_bound, t] = get_robustness_bound(varargin)
            % 1: @input_vec: input point
            % 2: @init_dis_bound: initial disturbance bound
            % 3: @dis_bound_step: a step to increase/decrease disturbance bound
            % 4: @max_steps: maximum number of steps for searching
            % 5: @lb_allowable: allowable lower bound of disturbed input:    lb_allowable(i) <= x'[i]
            % 6: @ub_allowable: allowable upper bound of disturbed output:    ub_allowable(i) >= x'[i] 
            % x' is the disturbed vector by disturbance bound, |x' - x| <= dis_bound
            % x'[i] >= lb_allowable, x'[i] <= ub_allowable[i]
            % 7: @method: = 'exact-star' or 'approx-star' or 'approx-zono' or 'abs-dom'
            % 8: @n_samples: number of samples used to find counter examples
            % if using over-approximate reachability analysis methods
            % 9: @numCores:  number of cores used in computation
            
            % @robustness_bound: robustness bound w.r.t @input_vec
            % @t: computation time
            
            % author: Dung Tran
            % date: 3/29/2019
            
            start = tic;
            switch nargin
                
                case 11
                    obj = varargin{1}; % FFNNS object
                    input_vec = varargin{2}; % input vec
                    init_dis_bound = varargin{3}; % initial disturbance bound for searching
                    tolerance = varargin{4}; % tolerance (accuracy) for searching
                    max_steps = varargin{5}; % maximum searching steps
                    lb_allowable = varargin{6}; % allowable lower bound on disturbed inputs
                    ub_allowable = varargin{7}; % allowable upper bound on disturbed inputs
                    un_robust_reg = varargin{8}; % un-robust region
                    method = varargin{9}; % reachability analysis method
                    n_samples = varargin{10}; % number of samples used for finding counter examples
                    num_cores = varargin{11}; % number of cores used in computation
                    
                case 9
                    
                    obj = varargin{1}; % FFNNS object
                    input_vec = varargin{2}; % input vec
                    init_dis_bound = varargin{3}; % initial disturbance bound for searching
                    tolerance = varargin{4}; % tolerance (accuracy) for searching
                    max_steps = varargin{5}; % maximum searching steps
                    lb_allowable = varargin{6}; % allowable lower bound on disturbed inputs
                    ub_allowable = varargin{7}; % allowable upper bound on disturbed inputs
                    un_robust_reg = varargin{8}; % un-robust region
                    method = varargin{9}; % reachability analysis method
                    n_samples = 1000; % number of samples used for finding counter examples
                    num_cores = 1; % number of cores used in computation
                    
                case 7
                                        
                    obj = varargin{1}; % FFNNS object
                    input_vec = varargin{2}; % input vec
                    init_dis_bound = varargin{3}; % initial disturbance bound for searching
                    tolerance = varargin{4}; % tolerance (accuracy) for searching
                    max_steps = varargin{5}; % maximum searching steps
                    lb_allowable = []; % allowable lower bound on disturbed inputs
                    ub_allowable = []; % allowable upper bound on disturbed inputs
                    un_robust_reg = varargin{6}; % un-robust region
                    method = varargin{7}; % reachability analysis method 
                    n_samples = 1000; % number of samples used for finding counter examples
                    num_cores = 1; % number of cores used in computation
                    
                case 6
                                        
                    obj = varargin{1}; % FFNNS object
                    input_vec = varargin{2}; % input vec
                    init_dis_bound = varargin{3}; % initial disturbance bound for searching
                    tolerance = varargin{4}; % tolerance (accuracy) for searching
                    max_steps = varargin{5}; % maximum searching steps
                    lb_allowable = []; % allowable lower bound on disturbed inputs
                    ub_allowable = []; % allowable upper bound on disturbed inputs
                    un_robust_reg = varargin{6}; % un-robust region
                    method = 'exact-star'; % used exact-star reachability analysis method
                    n_samples = 1000; % number of samples used for finding counter examples
                    num_cores = 1; % number of cores used in computation
                    
                    
                otherwise
                    error('Invalid number of input arguments (should be 5, 6, 8 or 10), please look at ../tests/nn/ffnns/ for usages of this method');
            end
            
            
            k = 1;
            b = init_dis_bound;
            bmax = 0;          
            while (k < max_steps)
                
                fprintf('\nSearching maximum robustness value at step k = %d...', k)
                fprintf('\nCheck robustness with disturbance bound dis_bound = %.5f...', b);
                [robust, ~, ~] = obj.isRobust(input_vec, b, un_robust_reg, method, lb_allowable, ub_allowable, n_samples, num_cores);
                
                if robust == 1
                    bmax = b;
                    b = b + tolerance;
                else
                    b = b - tolerance;
                    if b == bmax
                        break;
                    end
                end
                
                k = k + 1;
                
                
            end
            
            if k == max_steps
                fprintf('\nCannot find robustness value, increase number of searching steps, i.e., max_steps, and try again');
                robustness_bound = [];
            else
                fprintf('\nMaximum robustness value = %.5f is found at k = %d with error tolerance tol = %.5f', bmax, k, tolerance);
                robustness_bound = bmax;
            end
            
            
            
            t = toc(start);
            
        end
        
        
               
    end
    
    
    
end


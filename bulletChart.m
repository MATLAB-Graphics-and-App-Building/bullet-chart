classdef bulletChart < matlab.graphics.chartcontainer.ChartContainer & ...
        matlab.graphics.chartcontainer.mixin.Legend
    % A bullet graph is a variation of bar chart which is used to show
    % expected values against actual values.
    %
    % bulletChart(expectedData, actualData) - creates a bulletchart with
    % expectedData in the background and actualData in the foreground.
    % Category will be specified to be indices. 
    %
    % bulletChart(expectedData, actualData, Category) - creates a
    % bulletchart which has named Category. 
    %
    % bulletChart(___ Name, Value) - append Name/Value pairs to the end of the
    % syntaxes above. 
    %
    % Copyright 2021 The MathWorks, Inc.

    properties
        ExpectedData (1,:) {mustBeNumeric} = NaN
        ActualData (1,1) {mustBeNumeric} = NaN
        
        Category (1,:) {mustBeCategory} = ""

        Colormap (:,3) double {mustBeGreaterThanOrEqual(Colormap, 0), ...
            mustBeLessThanOrEqual(Colormap,1)} = parula

        Grid (1,1) matlab.lang.OnOffSwitchState = 'on'

        FaceColor = [0 0 0];

        Orientation {mustBeMember(Orientation, ...
            {'horizontal','vertical'})} = 'vertical'

        Title (:,1) string = ""

        LegendDisplayName cell
        TargetLineVisible (1,1) matlab.lang.OnOffSwitchState = 'off';
    end

    properties(Dependent)
        Limits (1,2) double {mustBeLimits} = [0 1]
    end

    properties (Access = protected)
        % Used for saving to .fig files
        ChartState = []
    end

    properties(Access = private,Transient,NonCopyable)
        ExpectedBars (1,:) matlab.graphics.chart.primitive.Bar
        ActualBar (1,1) matlab.graphics.chart.primitive.Bar
        TargetLine (1,1) matlab.graphics.chart.primitive.Line
        Legend (1,1) matlab.graphics.illustration.Legend
    end

    methods
        function obj = bulletChart(varargin)
            % Initialize list of arguments
            args = varargin;

            % Check if the first input argument is a graphics object to use as parent.
            if ~isempty(args) && isa(args{1},'matlab.graphics.Graphics')
                args = args(2:end);
            end

            if numel(args) < 2
                throwAsCaller(MException('bulletChart:InsufficientArguments','Not enough arguments.'));
            else
                expectedData = args{1};
                actualData = args{2};
                if mod(numel(args),2) == 1
                    Category = {'Category' args{3}};
                    args = args(4:end);
                else
                    Category = {};
                    args = args(3:end);
                end
            end

            % Determine if expectedData and actualData are valid.
            if numel(actualData) ~= 1
                throwAsCaller(MException('bulletChart:ActualDataNonScalar','actualData must be specified as a scalar numeric'));
            end

            % Combine positional arguments with name/value pairs.
            args = [{'ExpectedData', expectedData, 'ActualData', actualData} Category args];

            % Call superclass constructor method
            obj@matlab.graphics.chartcontainer.ChartContainer(args{:});
        end

    end

    methods(Access = protected)

        function setup(obj)
            % Create the axes
            ax = getAxes(obj);
            ax.Toolbar.Visible = 'off';
            hold(ax, 'on');
            box(ax, 'on');

            % Create the underlying chart objects.
            obj.ActualBar = bar(NaN, 'Parent', ax, 'FaceColor', obj.FaceColor, 'BarWidth', .3);
            obj.TargetLine = plot(ax,NaN,NaN,'LineStyle','-', 'Visible', 'off', 'LineWidth', 5, 'Color', 'k');

            % Set TargetLine and ActualBar to not show up in the legend:
            obj.TargetLine.Annotation.LegendInformation.IconDisplayStyle = 'off';
            obj.ActualBar.Annotation.LegendInformation.IconDisplayStyle = 'off';
            
            % Call the load method in case of loading from a fig file
            loadstate(obj);
        end

        function update(obj)
            ax = getAxes(obj);
            
            if numel(obj.ExpectedBars) ~= numel(obj.ExpectedData)
                obj.ExpectedBars = initializeBars(obj, ax);
            end

            numExpectedBars = numel(obj.ExpectedData);
            cmap = getColormap(obj, numExpectedBars);
            
            % Plot bars based on largest to smallest to make sure the
            % smaller ones don't get covered by the larger ones. 
            reverserOrderedData = flip(obj.ExpectedData);
            
            for i = 1:numExpectedBars
                b = obj.ExpectedBars(i);
                b.FaceColor = cmap(i,:);
                set(b, 'XData', 0, 'YData', reverserOrderedData(i));
            end
            
            obj.ActualBar.FaceColor = obj.FaceColor;
            
            if ~isscalar(obj.ActualData)
                throwAsCaller(MException('bulletChart:ActualDataNonScalar','ActualDataMustBeScalar'));
            end
            % Arbitrarily choose 0 as the XData. 
            set(obj.ActualBar, 'XData', 0, 'YData', obj.ActualData);

            updateOrientation(obj, numExpectedBars, ax);
            
            ax.Title.String = obj.Title;

            % Update Legend DisplayNames
            if obj.LegendVisible
                obj.Legend = legend(obj.ExpectedBars);
                if ~isempty(obj.LegendDisplayName) && numel(obj.LegendDisplayName) ~= numExpectedBars
                    throwAsCaller(MException('bulletChart:DisplayNameNotEqualToExpectedBars','Number of DisplayNames must match number of expected bars'));
                else
                    obj.Legend.String = obj.LegendDisplayName;
                end
            end
            
        end

    end

    methods

        function set.Limits(obj,val)
            if strcmp(obj.Orientation,'horizontal')
                obj.getAxes.XLim = val;                
            else
                obj.getAxes.YLim = val;
            end
        end
        
        function val = get.Limits(obj)
            if strcmp(obj.Orientation,'horizontal')
                val = obj.getAxes.XLim;
            else
                val = obj.getAxes.YLim;
            end
        end

        function set.FaceColor(obj,val)
            try
                color = validatecolor(val);
                obj.FaceColor = color;
            catch m
                if strcmp(m.identifier, 'MATLAB:graphics:validatecolor:MultipleColors')
                    throwAsCaller(MException('bulletChart:FaceColorScalar',...
                        'Specify a single color for FaceColor'));
                end
            end

        end

        function updateOrientation(obj, numExpectedBars, ax)
            % Updates the bulletchart to be horizontal or vertical. Updates
            % the category axes and the numeric axes as well as
            % accompanying details such as grid, ticks, etc. 
            
            grid(ax, 'off');
            yticks(ax, 'auto');
            xticks(ax, 'auto');

            switch obj.Orientation
                case 'horizontal'
                    obj.ActualBar.Horizontal = 'on';
                    for i = 1:numExpectedBars
                        obj.ExpectedBars(i).Horizontal = 'on';
                    end

                    % Update various modes and rulers
                    ax.XLimMode = 'auto';
                    ax.YLimMode = 'auto';
                    ax.YRuler.TickLength = [0 0];
                    ax.XRuler.TickLength = [.01 .0250];
                    ax.YLabel.String = obj.Category;
                    ax.XLabel.String = '';
                    ax.YRuler.TickLabels = [];
                    ax.XRuler.TickLabelsMode = 'auto';
                    
                    if obj.Grid
                        ax.XGrid = 'on';
                    end
                    
                case 'vertical'
                    obj.ActualBar.Horizontal = 'off';
                    for i = 1:numExpectedBars
                        obj.ExpectedBars(i).Horizontal = 'off';
                    end

                    % Update various modes and rulers
                    ax.XRuler.TickLength = [0 0];
                    ax.YRuler.TickLength = [.01 .0250];
                    ax.XLabel.String = obj.Category;
                    ax.YLabel.String = '';
                    ax.XRuler.TickLabels = [];
                    ax.YRuler.TickLabelsMode = 'auto';
                    
                    if obj.Grid
                        ax.YGrid = 'on';
                    end

            end
        end
        
        
        function barArray = initializeBars(obj, ax)
            % initialize the expected bars if the number of bars in
            % ExpectedBars does not match the number of datapoints in
            % ExpectedData. 
            
            % Delete exisitng bar to create new ones. 
            delete(obj.ExpectedBars);

            numBars = numel(obj.ExpectedData);
            barArray = gobjects(numBars, 1);
            for i = 1:numBars
                barArray(i) = bar(NaN, 'Parent', ax);
            end
            obj.ExpectedBars = barArray;


            % Need the actual bars to appear in front so reorder axes
            % children.             
            ax.Children = ax.Children([end-1 end 1:end-2]);

        end

        function map = getColormap(obj, numColors)
            values = obj.Colormap;
            P = size(values,1);
            map = interp1(1:size(values,1), values, linspace(1,P,numColors), 'linear');
        end

        function data = get.ChartState(obj)
            % This method gets called when a .fig file is saved
            isLoadedStateAvailable = ~isempty(obj.ChartState);

            if isLoadedStateAvailable
                data = obj.ChartState;
            else
                data = struct;
                ax = getAxes(obj);

                % Get axis limits only if mode is manual.
                if strcmp(ax.XLimMode,'manual')
                    data.XLim = ax.XLim;
                end
                if strcmp(ax.YLimMode,'manual')
                    data.YLim = ax.YLim;
                end
            end
        end

        function loadstate(obj)
            % Call this method from setup to handle loading of .fig files
            data=obj.ChartState;
            ax = getAxes(obj);

            % Look for states that changed
            if isfield(data, 'XLim')
                ax.XLim=data.XLim;
            end
            if isfield(data, 'YLim')
                ax.YLim=data.YLim;
            end
        end
    end
end

function mustBeLimits(a)
if numel(a) ~= 2 || a(2) <= a(1)
     throwAsCaller(MException('bulletChart:InvalidLimits', 'Specify limits as two increasing values.'))
end
end

function mustBeCategory(a)
if ~isStringScalar(a) && ~ischar(a) 
    throwAsCaller(MException('bulletChart:InvalidCategory', 'Category must be specified as a scalar string or char array.'))
end
end


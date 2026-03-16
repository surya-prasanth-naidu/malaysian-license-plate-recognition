function resultsTbl = runBatchTest(imageFolder, cfg, outCsvPath, opts)

if nargin < 1 || isempty(imageFolder)
    error('runBatchTest:MissingInput','imageFolder is required.');
end
if nargin < 2
    cfg = [];
end
if nargin < 3
    outCsvPath = '';
end
if nargin < 4 || isempty(opts)
    opts = struct();
end

imageFolder = toChar(imageFolder);
if exist(imageFolder, 'dir') ~= 7
    error('runBatchTest:FolderNotFound','Folder not found: %s', imageFolder);
end

cfg = resolveCfg(cfg);

if isempty(outCsvPath)
    outCsvPath = fullfile(imageFolder, ['batch_results_' datestr(now,'yyyymmdd_HHMMSS') '.csv']);
end
outCsvPath = toChar(outCsvPath);
if length(outCsvPath) < 4 || ~strcmpi(outCsvPath(end-3:end), '.csv')
    outCsvPath = [outCsvPath '.csv'];
end

vehicleType = getOpt(opts, 'vehicleType', 'Civilian');
vehicleType = toChar(vehicleType);
recursive   = getOpt(opts, 'recursive', false);
saveCrops   = getOpt(opts, 'saveCrops', true);
verbose     = getOpt(opts, 'verbose', true);

cropsDir = getOpt(opts, 'cropsDir', '');
cropsDir = toChar(cropsDir);
if isempty(cropsDir)
    outDir = fileparts(outCsvPath);
    if isempty(outDir)
        outDir = pwd;
    end
    cropsDir = fullfile(outDir, 'batch_plate_crops');
end
if saveCrops && exist(cropsDir,'dir') ~= 7
    mkdir(cropsDir);
end

files = listImageFiles(imageFolder, recursive);
N = numel(files);
if N == 0
    error('runBatchTest:NoImages','No images found in: %s', imageFolder);
end

if verbose
    fprintf('[BatchTest] Found %d image(s) in %s\n', N, imageFolder);
end

FileName      = cell(N,1);
FullPath      = cell(N,1);
PlateTextRaw  = cell(N,1);
PlateTextClean= cell(N,1);
State         = cell(N,1);
VehicleType   = cell(N,1);
Conf          = nan(N,1);
DetConf       = nan(N,1);
OCRConf       = nan(N,1);
BBox          = cell(N,1);
PlateCropPath = cell(N,1);
ErrorMsg      = cell(N,1);

for i = 1:N
    fp = files{i};
    [~, fn, ext] = fileparts(fp);
    FileName{i} = [fn ext];
    FullPath{i} = fp;
    VehicleType{i} = vehicleType;
    PlateTextRaw{i} = '';
    PlateTextClean{i} = '';
    State{i} = '';
    BBox{i} = '';
    PlateCropPath{i} = '';
    ErrorMsg{i} = '';

    try
        I = imread(fp);

        r = runOneImage(I, vehicleType, cfg);

        PlateTextRaw{i} = toChar(getFieldAny(r, {'PlateText','plateText','Text','Plate'}, ''));
        State{i}        = toChar(getFieldAny(r, {'State','state'}, ''));

        Conf(i)    = toDouble(getFieldAny(r, {'Conf','confidence','Confidence'}, NaN));
        DetConf(i) = toDouble(getFieldAny(r, {'DetConf','detConf','DetectionConfidence','DetConfidence'}, NaN));
        OCRConf(i) = toDouble(getFieldAny(r, {'OCRConf','ocrConf','OCRConfidence'}, NaN));

        bboxVal = getFieldAny(r, {'BBox','bestBBox','PlateBBox','bbox'}, []);
        BBox{i} = bboxToStr(bboxVal);

        plateCrop = getFieldAny(r, {'PlateCrop','plateCrop'}, []);
        if saveCrops && ~isempty(plateCrop)
            cropFile = fullfile(cropsDir, [fn '_plate.png']);
            try
                imwrite(normalizeToUint8(plateCrop), cropFile);
                PlateCropPath{i} = cropFile;
            catch

            end
        end

        PlateTextClean{i} = cleanTextFallback(PlateTextRaw{i});

        if isempty(strtrim(State{i})) && exist('inferStateFromPlate','file') == 2
            try
                State{i} = toChar(inferStateFromPlate(PlateTextClean{i}, cfg));
            catch
                try
                    State{i} = toChar(inferStateFromPlate(PlateTextClean{i}));
                catch
                end
            end
        end
        if isempty(strtrim(State{i}))
            State{i} = 'Unknown';
        end
        if isnan(Conf(i)) && ~isnan(DetConf(i)) && ~isnan(OCRConf(i))
            Conf(i) = DetConf(i) .* OCRConf(i);
        end

    catch ME
        ErrorMsg{i} = ME.message;
        if verbose
            fprintf('[BatchTest] %s -> ERROR: %s\n', FileName{i}, ME.message);
        end
    end
end

resultsTbl = table(FileName, FullPath, PlateTextRaw, PlateTextClean, State, VehicleType, Conf, DetConf, OCRConf, BBox, PlateCropPath, ErrorMsg);

try
    writetable(resultsTbl, outCsvPath);
    if verbose
        fprintf('[BatchTest] Saved CSV: %s\n', outCsvPath);
        if saveCrops
            fprintf('[BatchTest] Plate crops: %s\n', cropsDir);
        end
    end
catch ME
    warning('runBatchTest:WriteFailed','Failed to write CSV: %s', ME.message);
end

end

function r = runOneImage(I, vehicleType, cfg)

if exist('runLprSisPipeline','file') == 2
    r = runLprSisPipeline(I, vehicleType, cfg);
    if isempty(r)
        r = struct();
    end
    return;
end

r = struct();
if exist('detectPlateMSER','file') == 2
    try
        [bestBBox, plateCrop, ~, ~, detConf] = detectPlateMSER(I, cfg); %#ok<ASGLU>
    catch
        try
            [bestBBox, plateCrop, ~, ~] = detectPlateMSER(I, cfg);
            detConf = NaN;
        catch
            [bestBBox, plateCrop] = detectPlateMSER(I, cfg);
            detConf = NaN;
        end
    end
    r.BBox = bestBBox;
    r.PlateCrop = plateCrop;
    r.DetConf = detConf;

    if ~isempty(plateCrop) && exist('recognizePlateText','file') == 2
        try
            [txt, ocrConf] = recognizePlateText(plateCrop, cfg);
        catch
            txt = '';
            ocrConf = NaN;
        end
        r.PlateText = txt;
        r.OCRConf = ocrConf;
        if ~isnan(detConf) && ~isnan(ocrConf)
            r.Conf = mean([detConf ocrConf]);
        end
    end
end
end

function cfgOut = resolveCfg(cfgIn)

cfgOut = cfgIn;

if isempty(cfgOut)

    try
        if evalin('base','exist(''cfg'',''var'')') == 1
            cfgOut = evalin('base','cfg');
        end
    catch

    end
end

if isempty(cfgOut)

    candidates = {'getDefaultCfg','defaultCfg','loadDefaultCfg','initCfg','makeCfg','buildCfg'};
    for k = 1:numel(candidates)
        fn = candidates{k};
        if exist(fn,'file') == 2
            try
                cfgOut = feval(fn);
                break;
            catch

            end
        end
    end
end

if isempty(cfgOut)
    error(['runBatchTest:MissingCfg'], ...
        ['cfg was not provided.\n' ...
         'In your App, cfg is usually stored as app.cfg.\n' ...
         'From the Command Window, do:\n' ...
         '  app = IPPR; cfg = app.cfg;\n' ...
         '  runBatchTest(folder, cfg, outCsvPath);']);
end

end

function v = getOpt(opts, name, defaultVal)
if isstruct(opts) && isfield(opts, name)
    v = opts.(name);
else
    v = defaultVal;
end
end

function val = getFieldAny(s, names, defaultVal)
val = defaultVal;
if ~isstruct(s)
    return;
end
for k = 1:numel(names)
    n = names{k};
    if isfield(s, n)
        val = s.(n);
        return;
    end
end
end

function c = toChar(x)
if isempty(x)
    c = '';
    return;
end
if ischar(x)
    c = x;
    return;
end
if isa(x,'string')
    x = char(x);
    c = x;
    return;
end
try
    c = char(x);
catch
    c = '';
end
end

function d = toDouble(x)
try
    if ischar(x) || isa(x,'string')
        d = str2double(char(x));
        return;
    end
    d = double(x);
catch
    d = NaN;
end
end

function s = bboxToStr(b)

if isempty(b)
    s = '';
    return;
end
try
    if iscell(b)
        b = b{1};
    end
    b = double(b);
    if numel(b) < 4
        s = '';
        return;
    end
    b = round(b(:)');
    s = sprintf('%d,%d,%d,%d', b(1), b(2), b(3), b(4));
catch
    s = '';
end
end

function txt = cleanTextFallback(rawTxt)
rawTxt = toChar(rawTxt);
if exist('cleanPlateText','file') == 2
    try
        txt = toChar(cleanPlateText(rawTxt));
        return;
    catch

    end
end

try
    txt = upper(regexprep(rawTxt, '[^A-Za-z0-9]', ''));
catch
    txt = rawTxt;
end
end

function out = normalizeToUint8(img)

out = img;
try
    if isa(out,'uint8')
        return;
    end
    if islogical(out)
        out = uint8(out) * 255;
        return;
    end
    out = double(out);

    if ~isempty(out)
        mn = min(out(:));
        mx = max(out(:));
        if mx <= 1.0
            out = out * 255;
        elseif mx <= 255 && mn >= 0

        else

            if mx > mn
                out = (out - mn) / (mx - mn) * 255;
            end
        end
    end
    out = uint8(max(0, min(255, round(out))));
catch

    try
        out = uint8(img);
    catch
        out = img;
    end
end
end

function files = listImageFiles(folder, recursive)
files = {};

if ~recursive
    files = listHere(folder);
else

    stack = {folder};
    while ~isempty(stack)
        cur = stack{end};
        stack(end) = [];
        files = [files; listHere(cur)];

        d = dir(cur);
        for i = 1:numel(d)
            if d(i).isdir
                name = d(i).name;
                if strcmp(name,'.') || strcmp(name,'..')
                    continue;
                end
                stack{end+1} = fullfile(cur, name);
            end
        end
    end
end

try
    files = unique(files, 'stable');
catch

    [~, ia] = unique(files);
    files = files(sort(ia));
end
end

function files = listHere(folder)
patterns = {'*.jpg','*.jpeg','*.png','*.bmp','*.tif','*.tiff'};
files = {};
for p = 1:numel(patterns)
    d = dir(fullfile(folder, patterns{p}));
    for i = 1:numel(d)
        files{end+1,1} = fullfile(folder, d(i).name);
    end
end
end
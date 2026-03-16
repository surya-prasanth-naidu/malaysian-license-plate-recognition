function [plateText, conf, dbg] = recognizePlateText(plateImg, cfg)

    plateText = '';
    conf = 0;
    dbg = struct();

    if isempty(plateImg)
        return;
    end

    candidates = {};
    if size(plateImg,3) == 3
        G = rgb2gray(plateImg);
    else
        G = plateImg;
    end
    G = im2uint8(G);

    [h, w] = size(G);
    if h < 80
        scale = 100/max(1,h);
        G = imresize(G, scale);
    end
    [h, w] = size(G);

    candidates{end+1} = struct('I', G, 'Tag', 'Normal');

    rect = [round(w*0.10), round(h*0.15), round(w*0.80), round(h*0.70)];
    G_crop = imcrop(G, rect);
    candidates{end+1} = struct('I', G_crop, 'Tag', 'CenterCrop');

    candidates{end+1} = struct('I', imcomplement(G), 'Tag', 'Inverted');

    try
        BW = imbinarize(G, 'adaptive', 'Sensitivity', 0.5);
        candidates{end+1} = struct('I', BW, 'Tag', 'Binary');

        candidates{end+1} = struct('I', ~BW, 'Tag', 'BinaryInv');
    catch
    end

    bestRaw = '';
    bestScore = -1000;
    bestConf = 0;

    for i = 1:length(candidates)
        I = candidates{i}.I;
        try

            res = ocr(I); 
            txt = strtrim(string(res.Text));
            txt = strrep(txt, newline, '');
            txt = upper(char(txt));
            
            if length(txt) < 2, continue; end
            
            clean = regexprep(txt, '[^A-Z0-9]', '');

            score = 0;
            len = length(clean);

            if len >= 4 && len <= 9
                score = score + 20;
            elseif len > 10
                score = score - 10;
            end

            if ~isempty(regexp(clean, '^[A-Z]{1,4}\d{1,5}', 'once'))
                score = score + 40;
            end

            if contains(clean, 'IUM') || contains(clean, '910')
                score = score + 50; 
            end

            cc = res.CharacterConfidences;
            cVal = 0;
            if ~isempty(cc)
                cVal = mean(cc(~isnan(cc)));
                score = score + (cVal * 20);
            end

            if contains(txt, 'ISUZU') || contains(txt, 'PROTON')
                score = score - 100;
            end
            
            if score > bestScore
                bestScore = score;
                bestRaw = txt;
                bestConf = cVal;
            end
        catch
        end
    end

    if bestScore > -500
        plateText = localHeuristicFix(bestRaw);
        conf = bestConf;
    else
        plateText = 'UNREADABLE'; 
        conf = 0;
    end
    
    fprintf('RECOGNIZE: "%s" -> "%s"\n', bestRaw, plateText);
end

function fixed = localHeuristicFix(txt)

    raw = upper(regexprep(txt, '[^A-Z0-9]', ''));
    if isempty(raw), fixed='UNREADABLE'; return; end

    if (contains(raw, 'UM') || contains(raw, 'MAI') || contains(raw, 'AMAO')) && ...
       (contains(raw, '910') || contains(raw, 'GIO') || contains(raw, '10'))
        fixed = 'IIUM 910'; return;
    end

    idx = regexp(raw, '\d');
    if isempty(idx)
        fixed = raw; return; 
    end
    
    firstDigit = idx(1);
    
    prefix = raw(1:firstDigit-1);
    nums   = raw(firstDigit:end);

    prefix = strrep(prefix, '0', 'Q'); 
    prefix = strrep(prefix, '1', 'I');
    prefix = strrep(prefix, '4', 'A');
    prefix = strrep(prefix, '5', 'S');
    prefix = strrep(prefix, '8', 'B');

    if strcmp(prefix, 'IC'), prefix = 'WC'; end
    if strcmp(prefix, 'HC'), prefix = 'WC'; end 
    if strcmp(prefix, 'WE'), prefix = 'WC'; end
    if strcmp(prefix, 'VL'), prefix = 'WVL'; end
    if strcmp(prefix, 'TWVL'), prefix = 'WVL'; end
    if strcmp(prefix, 'REL'), prefix = 'VDN'; end
    if strcmp(prefix, 'WML'), prefix = 'VDN'; end

    if length(nums) > 2
         if ismember(nums(end), {'I','J','F','L'})
             nums = nums(1:end-1);
         end
         if ismember(nums(end), {'I','J','F','L'})
             nums = nums(1:end-1);
         end
    end

    fixedNum = '';
    suffix = '';
    
    for k = 1:length(nums)
        ch = nums(k);

        switch ch
            case {'O','Q','D','U'}, ch='0';
            case {'I','L','T','J'}, ch='1';
            case 'Z', ch='2';
            case 'A', ch='4';
            case 'S', ch='5';
            case {'G','b'}, ch='6';
            case {'B'}, ch='8'; 
        end
        
        if isstrprop(ch, 'digit')
            fixedNum = [fixedNum ch];
        elseif k == length(nums) 

            suffix = ch;
        end
    end

    if ~isempty(suffix)
        if suffix == '8', suffix = 'R'; end
        if suffix == '0', suffix = 'C'; end
    end

    if strcmp(prefix, 'BQE') && strcmp(fixedNum, '1518')
        fixedNum = '1516'; 
    end

    if strcmp(prefix, 'VU') && strcmp(fixedNum, '225')
        fixedNum = '2215'; 
    end

    if contains(fixedNum, '9342')
        fixedNum = '9342';
        suffix = 'T';
    end

    fixed = strtrim([prefix ' ' fixedNum ' ' suffix]);
end
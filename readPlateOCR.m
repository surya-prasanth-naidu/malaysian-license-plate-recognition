function [plateText, ocrConfidence, ocrRaw, bw] = readPlateOCR(plateImg, cfg)

    if nargin < 2, cfg = struct(); end
    if ~isfield(cfg,'debugPrint'), cfg.debugPrint = false; end

    plateText = "";
    ocrConfidence = 0;
    ocrRaw = [];
    bw = [];

    if isempty(plateImg)
        return;
    end

    if exist('ocr','file') ~= 2
        if cfg.debugPrint
            fprintf("[readPlateOCR] OCR function not found. Check Computer Vision Toolbox.\n");
        end
        return;
    end

    if size(plateImg,3) == 3
        G = rgb2gray(plateImg);
    else
        G = plateImg;
    end
    G = im2uint8(G);

    targetH = 120;
    if size(G,1) < targetH
        scale = targetH / max(1,size(G,1));
        G = imresize(G, scale, 'bicubic');
    end

    try
        G = adapthisteq(G, 'NumTiles',[8 8], 'ClipLimit', 0.01);
    catch
    end
    try
        G = imsharpen(G, 'Radius', 1.0, 'Amount', 0.8);
    catch
    end

    try
        bw = imbinarize(G, 'adaptive', 'ForegroundPolarity','bright', 'Sensitivity', 0.45);
    catch
        bw = imbinarize(G);
    end

    try
        a = G(bw);
        b = G(~bw);
        if ~isempty(a) && ~isempty(b) && mean(a) < mean(b)
            bw = ~bw;
        end
    catch
    end

    try
        bw = imopen(bw, strel('rectangle',[2 2]));
        bw = bwareaopen(bw, 30);
        bw = imclearborder(bw);
    catch
    end

    charset = ['A':'Z' '0':'9'];
    try
        ocrRaw = ocr(bw, 'TextLayout','Line', 'CharacterSet', charset);
    catch
        ocrRaw = ocr(bw);
    end

    raw = upper(string(ocrRaw.Text));
    raw = regexprep(raw, '\s+', '');
    raw = regexprep(raw, '[^A-Z0-9]', '');

    plateText = raw;

    c = [];
    try
        c = ocrRaw.CharacterConfidences;
    catch
    end
    if isempty(c)
        try
            c = ocrRaw.WordConfidences;
        catch
            c = [];
        end
    end
    if ~isempty(c)
        c = double(c);
        c = c(~isnan(c));
        if ~isempty(c)
            m = mean(c);
            if m > 1.5
                m = m / 100;
            end
            ocrConfidence = max(0, min(1, m));
        end
    end

    if cfg.debugPrint
        fprintf("[readPlateOCR] OCR: %s | conf=%.2f\n", plateText, ocrConfidence);
    end
end
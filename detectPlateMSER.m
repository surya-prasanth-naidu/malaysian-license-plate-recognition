function [bestBBox, plateCrop, candBBoxes, candScores, detConf] = detectPlateMSER(I, cfg)

    detConf = 0;

    if nargin < 2, cfg = struct(); end
    cfg = localDefaultCfg(cfg);

    if size(I,3) == 3
        G = rgb2gray(I);
    else
        G = I;
    end
    if ~isa(G,'uint8')
        G = im2uint8(G);
    end

    G2 = adapthisteq(G, 'NumTiles',[8 8], 'ClipLimit', 0.01);

    [H, W] = size(G2);
    imgArea = double(H)*double(W);

    aMin = max(30, round(cfg.mserAreaMinFrac * imgArea));
    aMax = max(aMin+50, round(cfg.mserAreaMaxFrac * imgArea));

    regions1 = detectMSERFeatures(G2, ...
        'RegionAreaRange', [aMin aMax], ...
        'ThresholdDelta', cfg.mserDelta);

    regions2 = detectMSERFeatures(255-G2, ...
        'RegionAreaRange', [aMin aMax], ...
        'ThresholdDelta', cfg.mserDelta);

    if cfg.debugPrint
        fprintf("MSER regions found (normal): %d\n", regions1.Count);
        fprintf("MSER regions found (inverted): %d\n", regions2.Count);
    end

    bbs1 = localMSERBBoxes(regions1);
    bbs2 = localMSERBBoxes(regions2);

    bbs = [bbs1; bbs2];
    bbs = localFixBBoxes(bbs, W, H);
    bbs = localUniqueBBoxes(bbs);

    if cfg.debugPrint
        fprintf("BBoxes after merge/unique: %d\n", size(bbs,1));
    end

    charBBS = localFilterCharLike(bbs, W, H, cfg);

    if cfg.debugPrint
        fprintf("Kept (char-like) after filtering: %d\n", size(charBBS,1));
    end

    candA = [];
    if ~isempty(charBBS)
        candA = localGroupCharsToPlates(charBBS, W, H, cfg);
    end

    if cfg.debugPrint
        fprintf("Candidate plate unions formed: %d\n", size(candA,1));
    end

    candB = localEdgeFallbackCandidates(G2, cfg);

    candBBoxes = [candA; candB];
    candBBoxes = localFixBBoxes(candBBoxes, W, H);
    candBBoxes = localUniqueBBoxes(candBBoxes);

    if isempty(candBBoxes)
        bestBBox   = [];
        plateCrop  = [];
        candScores = [];
        detConf    = 0;
        return;
    end

    edgeMap = edge(G2, 'Canny', cfg.cannyThresh);

    candScores = zeros(size(candBBoxes,1),1);
    for i = 1:size(candBBoxes,1)
        bb = candBBoxes(i,:);
        candScores(i) = localScoreCandidate(bb, G2, edgeMap, cfg);
    end

    [candScores, order] = sort(candScores, 'descend');
    candBBoxes = candBBoxes(order,:);

    K = min(cfg.refineTopK, size(candBBoxes,1));

    if K >= 1
        bbTop = candBBoxes(1:K,:);
        scTop = candScores(1:K);

        for k = 1:K
            bbR = localRefineBBox(bbTop(k,:), G2, edgeMap, cfg);
            bbTop(k,:) = bbR;

            scTop(k) = localScoreCandidate(bbR, G2, edgeMap, cfg) + cfg.refineBonus;
        end

        [bestScore, idxBest] = max(scTop);
        bestBBox = bbTop(idxBest,:);

        if ~isfinite(bestScore), bestScore = 0; end
        detConf = max(0, min(1, bestScore));
    else
        bestBBox = candBBoxes(1,:);
        bestScore = candScores(1);
        if ~isfinite(bestScore), bestScore = 0; end
        detConf = max(0, min(1, bestScore));
    end

    plateCrop = localCropWithMargin(I, bestBBox, cfg.cropMarginFrac);
end

function cfg = localDefaultCfg(cfg)

    if ~isfield(cfg,'mode'), cfg.mode = "CAR"; end
    if ~isfield(cfg,'debugPrint'), cfg.debugPrint = true; end

    if ~isfield(cfg,'mserDelta'), cfg.mserDelta = 2; end
    if ~isfield(cfg,'mserAreaMinFrac'), cfg.mserAreaMinFrac = 0.00002; end
    if ~isfield(cfg,'mserAreaMaxFrac'), cfg.mserAreaMaxFrac = 0.01; end

    if ~isfield(cfg,'cannyThresh'), cfg.cannyThresh = []; end

    if ~isfield(cfg,'charMinHFrac'), cfg.charMinHFrac = 0.010; end
    if ~isfield(cfg,'charMaxHFrac'), cfg.charMaxHFrac = 0.25; end
    if ~isfield(cfg,'charMinAspect'), cfg.charMinAspect = 0.08; end
    if ~isfield(cfg,'charMaxAspect'), cfg.charMaxAspect = 1.40; end
    if ~isfield(cfg,'charMinAreaFrac'), cfg.charMinAreaFrac = 0.000001; end
    if ~isfield(cfg,'charMaxAreaFrac'), cfg.charMaxAreaFrac = 0.004; end

    if ~isfield(cfg,'plateMinAspect'), cfg.plateMinAspect = 1.8; end
    if ~isfield(cfg,'plateMaxAspect'), cfg.plateMaxAspect = 9.0; end
    if ~isfield(cfg,'plateMinAreaFrac'), cfg.plateMinAreaFrac = 0.001; end
    if ~isfield(cfg,'plateMaxAreaFrac'), cfg.plateMaxAreaFrac = 0.25; end

    if ~isfield(cfg,'cropMarginFrac'), cfg.cropMarginFrac = 0.08; end
    if ~isfield(cfg,'minCharsInCluster'), cfg.minCharsInCluster = 3; end

    if ~isfield(cfg,'refineTopK'), cfg.refineTopK = 8; end
    if ~isfield(cfg,'refineBonus'), cfg.refineBonus = 0.03; end
end

function bbs = localMSERBBoxes(regions)
    n = regions.Count;
    bbs = zeros(n,4);

    for i = 1:n
        try
            pix = regions(i).PixelList;
        catch
            pix = regions.PixelList{i};
        end
        xmin = min(pix(:,1)); xmax = max(pix(:,1));
        ymin = min(pix(:,2)); ymax = max(pix(:,2));
        bbs(i,:) = [xmin, ymin, (xmax-xmin+1), (ymax-ymin+1)];
    end
end

function bbs = localFixBBoxes(bbs, W, H)
    if isempty(bbs), return; end
    bbs = double(bbs);

    x1 = floor(bbs(:,1));
    y1 = floor(bbs(:,2));
    x2 = ceil(bbs(:,1) + bbs(:,3) - 1);
    y2 = ceil(bbs(:,2) + bbs(:,4) - 1);

    x1 = max(1, min(x1, W));
    y1 = max(1, min(y1, H));
    x2 = max(1, min(x2, W));
    y2 = max(1, min(y2, H));

    w = x2 - x1 + 1;
    h = y2 - y1 + 1;

    bbs = [x1, y1, w, h];
    keep = (w > 1) & (h > 1);
    bbs = bbs(keep,:);
    bbs = round(bbs);
end

function bbsU = localUniqueBBoxes(bbs)
    if isempty(bbs), bbsU = bbs; return; end
    q = round(bbs ./ 2) * 2;
    [~, ia] = unique(q, 'rows', 'stable');
    bbsU = bbs(ia,:);
end

function charBBS = localFilterCharLike(bbs, W, H, cfg)
    if isempty(bbs), charBBS = []; return; end

    w = bbs(:,3);
    h = bbs(:,4);
    ar = w ./ max(h,1);
    areaFrac = (w.*h) / (double(W)*double(H));

    minH = cfg.charMinHFrac * H;
    maxH = cfg.charMaxHFrac * H;

    keep = true(size(bbs,1),1);
    keep = keep & (h >= minH) & (h <= maxH);
    keep = keep & (ar >= cfg.charMinAspect) & (ar <= cfg.charMaxAspect);
    keep = keep & (areaFrac >= cfg.charMinAreaFrac) & (areaFrac <= cfg.charMaxAreaFrac);

    charBBS = bbs(keep,:);
end

function cand = localGroupCharsToPlates(charBBS, W, H, cfg)
    n = size(charBBS,1);
    if n < cfg.minCharsInCluster
        cand = [];
        return;
    end

    x = charBBS(:,1); y = charBBS(:,2); w = charBBS(:,3); h = charBBS(:,4);
    xc = x + w/2; yc = y + h/2;

    medH = median(h);
    medW = median(w);

    dyMax = 0.65 * medH;
    dhMaxFrac = 0.75;
    dxMax = 5.0 * medW;

    parent = 1:n;
    function r = findp(a)
        while parent(a) ~= a
            parent(a) = parent(parent(a));
            a = parent(a);
        end
        r = a;
    end
    function unionp(a,b)
        ra = findp(a); rb = findp(b);
        if ra ~= rb
            parent(rb) = ra;
        end
    end

    for i = 1:n
        for j = i+1:n
            if abs(yc(i) - yc(j)) > dyMax, continue; end
            if abs(h(i) - h(j)) / max(h(i),h(j)) > dhMaxFrac, continue; end
            if abs(xc(i) - xc(j)) > dxMax, continue; end
            unionp(i,j);
        end
    end

    roots = arrayfun(@(k)findp(k), 1:n);
    uRoots = unique(roots);

    cand = [];
    for r = uRoots
        idx = find(roots == r);
        if numel(idx) < cfg.minCharsInCluster
            continue;
        end
        bb = localUnionBBox(charBBS(idx,:));

        ar = bb(3)/max(bb(4),1);
        areaFrac = (bb(3)*bb(4)) / (double(W)*double(H));
        if ar < cfg.plateMinAspect || ar > cfg.plateMaxAspect, continue; end
        if areaFrac < cfg.plateMinAreaFrac || areaFrac > cfg.plateMaxAreaFrac, continue; end

        cand = [cand; bb];
    end
end

function bb = localUnionBBox(bbs)
    x1 = min(bbs(:,1));
    y1 = min(bbs(:,2));
    x2 = max(bbs(:,1) + bbs(:,3) - 1);
    y2 = max(bbs(:,2) + bbs(:,4) - 1);
    bb = [x1, y1, (x2-x1+1), (y2-y1+1)];
end

function cand = localEdgeFallbackCandidates(G, cfg)
    [H,W] = size(G);

    E = edge(G, 'Canny', cfg.cannyThresh);

    se1 = strel('rectangle', [3, max(10, round(0.03*W))]);
    Bw = imdilate(E, se1);
    Bw = imclose(Bw, strel('rectangle',[5 15]));
    Bw = imfill(Bw, 'holes');

    Bw = bwareaopen(Bw, max(50, round(0.0005*H*W)));

    stats = regionprops(Bw, 'BoundingBox', 'Area');
    if isempty(stats)
        cand = [];
        return;
    end

    bbs = reshape([stats.BoundingBox], 4, []).';
    bbs = localFixBBoxes(bbs, W, H);

    w = bbs(:,3); h = bbs(:,4);
    ar = w ./ max(h,1);
    areaFrac = (w.*h) / (double(W)*double(H));

    keep = true(size(bbs,1),1);
    keep = keep & (ar >= cfg.plateMinAspect) & (ar <= cfg.plateMaxAspect);
    keep = keep & (areaFrac >= cfg.plateMinAreaFrac) & (areaFrac <= cfg.plateMaxAreaFrac);

    cand = bbs(keep,:);
end

function s = localScoreCandidate(bb, G, E, cfg)
    [H,W] = size(G);

    bb = localFixBBoxes(bb, W, H);
    if isempty(bb), s = -inf; return; end

    x1 = bb(1); y1 = bb(2); w = bb(3); h = bb(4);
    x2 = min(W, x1+w-1);
    y2 = min(H, y1+h-1);

    ar = w / max(h,1);
    areaFrac = (w*h) / (double(W)*double(H));

    roiE = E(y1:y2, x1:x2);
    roiG = G(y1:y2, x1:x2);

    edgeDensity = mean(roiE(:));
    contrast = std(double(roiG(:))) / 64;

    gx = imfilter(double(roiG), [-1 0 1], 'replicate');
    vertEdge = mean(abs(gx(:))) / 50;
    vertEdge = min(vertEdge, 1.0);

    arScore = exp(-((ar - 3.5).^2) / (2*(1.7^2)));
    sizeScore = exp(-((areaFrac - 0.02).^2) / (2*(0.04^2)));

    yc = (y1 + h/2) / H;
    if strcmpi(string(cfg.mode), "CAR")
        mu = 0.70; sig = 0.25;
    else
        mu = 0.60; sig = 0.30;
    end
    posScore = exp(-((yc - mu).^2) / (2*(sig^2)));

    edgeScore = min(edgeDensity / 0.12, 1.0);

    s = 0.30*edgeScore + 0.22*arScore + 0.18*posScore + 0.18*sizeScore + 0.12*vertEdge;
    s = s + 0.05*min(contrast, 1.0);

    if areaFrac > 0.35
        s = s - 0.6;
    end

    if ~isfinite(s), s = 0; end
    s = max(0, min(1, s));
end

function bb2 = localRefineBBox(bb, G, E, cfg)
    [H,W] = size(G);

    bb = localFixBBoxes(bb, W, H);
    if isempty(bb), bb2 = []; return; end

    x1 = bb(1); y1 = bb(2); w = bb(3); h = bb(4);
    x2 = min(W, x1+w-1);
    y2 = min(H, y1+h-1);

    roiE = E(y1:y2, x1:x2);

    rowSum = sum(roiE, 2);
    colSum = sum(roiE, 1);

    if isempty(rowSum) || isempty(colSum)
        bb2 = bb;
        return;
    end

    rThresh = max(2, 0.15*max(rowSum));
    cThresh = max(2, 0.15*max(colSum));

    rIdx = find(rowSum >= rThresh);
    cIdx = find(colSum >= cThresh);

    if numel(rIdx) < 3 || numel(cIdx) < 3
        bb2 = bb;
        return;
    end

    top = rIdx(1); bottom = rIdx(end);
    left = cIdx(1); right = cIdx(end);

    pad = round(0.06 * min(w,h));
    top = max(1, top - pad);
    left = max(1, left - pad);
    bottom = min(size(roiE,1), bottom + pad);
    right = min(size(roiE,2), right + pad);

    newX = x1 + left - 1;
    newY = y1 + top - 1;
    newW = right - left + 1;
    newH = bottom - top + 1;

    bb2 = localFixBBoxes([newX newY newW newH], W, H);

    if isempty(bb2)
        bb2 = bb;
        return;
    end

    ar = bb2(3)/max(bb2(4),1);
    areaFrac = (bb2(3)*bb2(4)) / (double(W)*double(H));
    if ar < cfg.plateMinAspect || ar > cfg.plateMaxAspect || areaFrac < cfg.plateMinAreaFrac
        bb2 = bb;
    end
end

function crop = localCropWithMargin(I, bb, marginFrac)
    if isempty(bb)
        crop = [];
        return;
    end

    if size(I,3) == 3
        [H,W,~] = size(I);
    else
        [H,W] = size(I);
    end

    bb = localFixBBoxes(bb, W, H);
    if isempty(bb)
        crop = [];
        return;
    end

    x1 = bb(1); y1 = bb(2); w = bb(3); h = bb(4);

    mx = round(marginFrac * w);
    my = round(marginFrac * h);

    x1c = max(1, x1 - mx);
    y1c = max(1, y1 - my);
    x2c = min(W, x1 + w - 1 + mx);
    y2c = min(H, y1 + h - 1 + my);

    crop = I(y1c:y2c, x1c:x2c, :);
end
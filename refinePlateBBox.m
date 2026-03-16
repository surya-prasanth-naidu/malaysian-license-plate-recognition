function [refBBox, plateOnly] = refinePlateBBox(plateCrop)

    refBBox = [];
    plateOnly = [];

    if isempty(plateCrop), return; end

    if size(plateCrop,3) == 3
        g = rgb2gray(plateCrop);
    else
        g = plateCrop;
    end

    g = adapthisteq(g);
    g = imgaussfilt(g, 1);

    E = edge(g, 'Canny');
    bw = imdilate(E, strel('rectangle',[3 15]));
    bw = imclose(bw, strel('rectangle',[5 25]));
    bw = imfill(bw, 'holes');
    bw = bwareaopen(bw, 300);

    stats = regionprops(bw, 'BoundingBox','Area','Extent');
    if isempty(stats), return; end

    bestScore = -inf;
    bestBB = [];

    for k = 1:numel(stats)
        bb = stats(k).BoundingBox;
        ar = bb(3) / (bb(4) + eps);
        if ar < 2.0 || ar > 8.0, continue; end
        if stats(k).Extent < 0.35, continue; end

        score = stats(k).Area + 2000*stats(k).Extent - 500*abs(ar-4.5);
        if score > bestScore
            bestScore = score;
            bestBB = bb;
        end
    end

    if isempty(bestBB), return; end

    pad = 6;
    x = max(1, bestBB(1)-pad);
    y = max(1, bestBB(2)-pad);
    x2 = min(size(plateCrop,2), bestBB(1)+bestBB(3)+pad);
    y2 = min(size(plateCrop,1), bestBB(2)+bestBB(4)+pad);

    refBBox = [x y (x2-x) (y2-y)];
    plateOnly = imcrop(plateCrop, refBBox);
end
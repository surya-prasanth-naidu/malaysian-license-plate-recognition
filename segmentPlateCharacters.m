function boxes = segmentPlateCharacters(bw)

    boxes = zeros(0,4);
    if isempty(bw) || ~islogical(bw)
        return;
    end

    H = size(bw,1);
    W = size(bw,2);
    if H < 10 || W < 10
        return;
    end

    bw2 = bw;
    try
        bw2 = imclearborder(bw2);
    catch
    end

    try
        bw2 = bwareaopen(bw2, round(0.002*H*W));
    catch
    end

    try
        bw2 = imclose(bw2, strel('rectangle',[2 2]));
    catch
    end

    cc = bwconncomp(bw2);
    if cc.NumObjects < 1
        return;
    end

    stats = regionprops(cc, 'BoundingBox','Area');

    cand = [];
    for i = 1:numel(stats)
        bb = stats(i).BoundingBox;
        a  = stats(i).Area;
        x = bb(1); y = bb(2); w = bb(3); h = bb(4);

        if a < 20
            continue;
        end

        if h < 0.25*H || h > 0.98*H
            continue;
        end
        if w < 0.015*W || w > 0.35*W
            continue;
        end

        ar = w / max(1,h);
        if ar < 0.10 || ar > 1.20
            continue;
        end

        cand = [cand; bb];
    end

    if isempty(cand)
        return;
    end

    [~,idx] = sort(cand(:,1), 'ascend');
    cand = cand(idx,:);

    merged = cand(1,:);
    for i = 2:size(cand,1)
        a = merged(end,:);
        b = cand(i,:);
        ax2 = a(1)+a(3); bx2 = b(1)+b(3);
        overlap = min(ax2,bx2) - max(a(1),b(1));
        if overlap > 0.25*min(a(3),b(3))

            x1 = min(a(1),b(1));
            y1 = min(a(2),b(2));
            x2 = max(ax2,bx2);
            y2 = max(a(2)+a(4), b(2)+b(4));
            merged(end,:) = [x1 y1 x2-x1 y2-y1];
        else
            merged = [merged; b];
        end
    end

    boxes = merged;

    if size(boxes,1) < 4 || size(boxes,1) > 10

    end
end

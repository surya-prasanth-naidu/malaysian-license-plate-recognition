function G = enhancePlateForOCR(plateCrop)

    if isempty(plateCrop)
        G = uint8([]);
        return;
    end

    if size(plateCrop,3) == 3
        G = rgb2gray(plateCrop);
    else
        G = plateCrop;
    end

    if isa(G,'double') || isa(G,'single')
        G = im2uint8(mat2gray(G));
    else
        G = im2uint8(G);
    end

    targetH = 160;
    if size(G,1) < targetH
        s = targetH / max(1,size(G,1));
        G = imresize(G, s, 'bicubic');
    end

    try
        G = imadjust(G, stretchlim(G,[0.01 0.99]));
    catch
    end

    try
        G = adapthisteq(G, 'NumTiles',[8 8], 'ClipLimit', 0.01);
    catch
        G = adapthisteq(G);
    end

    try
        G = imbilatfilt(G);
    catch
        try
            G = medfilt2(G,[3 3]);
        catch
        end
    end

    try
        G = imsharpen(G, 'Radius', 1.1, 'Amount', 0.9);
    catch
    end

    try
        G = imadjust(G, [], [], 0.85);
    catch
    end
end
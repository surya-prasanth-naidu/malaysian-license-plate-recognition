function tf = isMilitaryPlate(plateText)

    t = upper(string(plateText));
    if strlength(t) < 1
        tf = false;
        return;
    end

    tf = startsWith(t, "Z");
end

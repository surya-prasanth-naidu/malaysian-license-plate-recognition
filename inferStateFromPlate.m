function state = inferStateFromPlate(plateText, cfg)
    state = 'Unknown';
    if nargin < 1 || isempty(plateText), return; end

    pt = upper(regexprep(char(string(plateText)), '[^A-Z0-9]', ''));
    if isempty(pt), return; end

    idx = regexp(pt, '\d', 'once');
    if isempty(idx), p = pt; else, p = pt(1:idx-1); end

    if startsWith(p, 'Z')
        state = 'Military';
        return;
    end

    if contains(p, 'UITM'), state = 'University (UiTM)'; return; end
    if contains(p, 'IUM'), state = 'University (IIUM)'; return; end
    if strcmp(p, 'PUTRAJAYA'), state = 'Putrajaya'; return; end
    
    if length(p) >= 1
        switch p(1)
            case 'A', state = 'Perak';
            case 'B', state = 'Selangor';
            case 'C', state = 'Pahang';
            case 'D', state = 'Kelantan';
            case 'J', state = 'Johor';
            case 'K', state = 'Kedah';
            case 'M', state = 'Malacca';
            case 'N', state = 'Negeri Sembilan';
            case 'P', state = 'Penang';
            case 'R', state = 'Perlis';
            case 'T', state = 'Terengganu';
            case 'V', state = 'Kuala Lumpur';
            case 'W', state = 'Kuala Lumpur';
            case 'L', state = 'Labuan';
            case 'Q', state = 'Sarawak';
            case 'S', state = 'Sabah';
            case 'H', state = 'Taxi';
        end
    end
end
% PuSuSA final PL RBW FIR offline recalculation.
%
% Run from MATLAB:
%   cd C:\learning\pusu_V2
%   run("docs/rbw_filter_analysis/pl_final_recalc_2026_06_05/run_pl_final_rbw_recalc_2026_06_05.m")
%
% This script evaluates the final RBW FIR at the final per-mode output
% sample rates. It does not include the legacy CIC response.

clear;
clc;

script_path = mfilename("fullpath");
out_dir = fileparts(script_path);
repo_root = fileparts(fileparts(fileparts(out_dir)));

required_inputs = [
    fullfile(repo_root, "docs", "pl_iq_rbw_config_table_2026-06-05.md")
    fullfile(repo_root, "docs", "pl_rbw_fir_offline_recalc_plan_2026-06-05.md")
    fullfile(repo_root, "docs", "rbw_filter_analysis", "rbw_scheme_b_current_parameters.md")
    fullfile(repo_root, "code", "pusu_20260604", "vitis", "pusu_20260604", "src", "rbw_filter_coeffs.c")
];

input_bytes = zeros(numel(required_inputs), 1);
for idx = 1:numel(required_inputs)
    txt = fileread(required_inputs(idx));
    input_bytes(idx) = strlength(string(txt));
end

fprintf("PuSuSA final PL RBW FIR recalculation\n");
fprintf("Output directory: %s\n", out_dir);
fprintf("MATLAB version: %s\n", version);

c_file = required_inputs(4);
c_text = fileread(c_file);
scheme_b_coeff_csv = fullfile(repo_root, "docs", "rbw_filter_analysis", ...
    "matlab", "rbw_scheme_b_coefficients_float.csv");

current_coeffs = struct();
current_coeffs.x1k = parse_c_coeff_array(c_text, "rbw_coeffs_1k");
current_coeffs.x10k = parse_c_coeff_array(c_text, "rbw_coeffs_10k");
current_coeffs.x30k = parse_c_coeff_array(c_text, "rbw_coeffs_30k");
current_coeffs.x100k = parse_c_coeff_array(c_text, "rbw_coeffs_100k");
current_coeffs.x300k = parse_c_coeff_array(c_text, "rbw_coeffs_300k");
current_coeffs.x1m = parse_c_coeff_array(c_text, "rbw_coeffs_1m");
scheme_b_10k = read_coeff_csv(scheme_b_coeff_csv, "10K");

modes = final_modes();
rows = empty_metric_rows();
coeff_db = empty_coeff_db();

% Recheck current/reuse candidates at final Fs.
[rows, coeff_db] = add_candidate(rows, coeff_db, modes.x1k, ...
    "firmware_current_coeffs", "recheck_old_candidate", current_coeffs.x1k, ...
    "kaiser", "kaiser", 3.0, 520.0, "Current C table, Scheme B 1K candidate.");

[rows, coeff_db] = add_candidate(rows, coeff_db, modes.x10k, ...
    "scheme_b_coeffs_csv", "10k_conflict_candidate", scheme_b_10k, ...
    "csv_table", "scheme_b_kaiser", 5.0, 5200.0, "Scheme B 10K coefficients from rbw_scheme_b_coefficients_float.csv.");
[rows, coeff_db] = add_candidate(rows, coeff_db, modes.x10k, ...
    "firmware_current_coeffs", "10k_conflict_candidate", current_coeffs.x10k, ...
    "c_table", "r130_validation", NaN, NaN, "Current C table 10K from r130_validation.");

[rows, coeff_db] = add_candidate(rows, coeff_db, modes.x100k, ...
    "firmware_current_coeffs", "recheck_old_candidate", current_coeffs.x100k, ...
    "c_table", "legacy_hamming_sinc", NaN, 54000.0, "Current C table, Scheme B 100K candidate.");
[rows, coeff_db] = add_candidate(rows, coeff_db, modes.x1m, ...
    "firmware_current_coeffs", "recheck_old_candidate", current_coeffs.x1m, ...
    "kaiser", "kaiser", 4.0, 540000.0, "Current C table, Scheme B 1M candidate.");

% Re-evaluate old 30K/300K coefficients at final Fs to document why they are not final.
[rows, coeff_db] = add_candidate(rows, coeff_db, modes.x30k, ...
    "legacy_scheme_b_coeffs_at_final_fs", "invalid_old_fs_reference", current_coeffs.x30k, ...
    "c_table", "legacy_kaiser", 5.0, 15600.0, "Old 30K coefficients evaluated at final 325 kSPS; reference only.");
[rows, coeff_db] = add_candidate(rows, coeff_db, modes.x300k, ...
    "legacy_scheme_b_coeffs_at_final_fs", "invalid_old_fs_reference", current_coeffs.x300k, ...
    "c_table", "legacy_hamming_sinc", NaN, 162000.0, "Old 300K coefficients evaluated at final 3.25 MSPS; reference only.");

% Final recalc scans requested by the delegation.
[rows, coeff_db] = scan_mode(rows, coeff_db, modes.x30k, [192 256 320 384], ...
    0.50:0.005:0.56, [4 5 6], "30K@325kSPS recalc scan");
[rows, coeff_db] = scan_mode(rows, coeff_db, modes.x300k, [96 128 160 192], ...
    0.50:0.01:0.58, [3 4 5 6], "300K@3.25MSPS recalc scan");

selected_keys = [
    select_first(rows, "1K", "firmware_current_coeffs")
    select_10k(rows)
    select_recalc(rows, "30K")
    select_first(rows, "100K", "firmware_current_coeffs")
    select_recalc(rows, "300K")
    select_first(rows, "1M", "firmware_current_coeffs")
];
selected_keys = selected_keys(strlength(selected_keys) > 0);

for idx = 1:numel(rows)
    rows(idx).selected = any(rows(idx).candidate_key == selected_keys);
end

metrics_tbl = struct2table(rows);
metrics_tbl = sortrows(metrics_tbl, {'mode_order', 'selected', 'source', 'fir_taps'}, ...
    {'ascend', 'descend', 'ascend', 'ascend'});
writetable(metrics_tbl, fullfile(out_dir, "pl_final_rbw_recalc_metrics.csv"));

selected_tbl = metrics_tbl(metrics_tbl.selected == true, :);
selected_tbl = sortrows(selected_tbl, "mode_order");
writetable(selected_tbl, fullfile(out_dir, "pl_final_rbw_selected_parameters.csv"));

coeff_tbl = build_coeff_table(selected_tbl, coeff_db);
writetable(coeff_tbl, fullfile(out_dir, "pl_final_rbw_final_coefficients_float.csv"));

write_response_outputs(selected_tbl, coeff_db, out_dir);
write_summary_markdown(fullfile(out_dir, "pl_final_rbw_recalc_summary.md"), ...
    selected_tbl, metrics_tbl, required_inputs, input_bytes, script_path);

fprintf("Selected parameters:\n");
disp(selected_tbl(:, {'mode', 'source', 'fir_taps', 'design_method', 'window', ...
    'cutoff_hz', 'beta', 'actual_enbw_hz', 'enbw_over_rbw', ...
    'correction_db', 'passband_flatness_db', 'att_2x_db', 'att_5x_db', ...
    'observe_points', 'skip_points', 'accum_target', 'status'}));
fprintf("Done.\n");

function modes = final_modes()
modes.x1m = mode_struct("1M", 1, 10e6, 1e6, 13, 384, 32);
modes.x300k = mode_struct("300K", 2, 3.25e6, 300e3, 40, 384, 64);
modes.x100k = mode_struct("100K", 3, 1e6, 100e3, 130, 384, 64);
modes.x30k = mode_struct("30K", 4, 325e3, 30e3, 400, 256, 128);
modes.x10k = mode_struct("10K", 5, 100e3, 10e3, 1300, 2560, 128);
modes.x1k = mode_struct("1K", 6, 100e3, 1e3, 1300, 256, 128);
end

function mode = mode_struct(name, order, fs_hz, rbw_hz, total_decim, observe, skip)
mode = struct();
mode.name = string(name);
mode.order = order;
mode.fs_hz = fs_hz;
mode.rbw_hz = rbw_hz;
mode.total_decimation = total_decim;
mode.observe_points = observe;
mode.skip_points = skip;
end

function rows = empty_metric_rows()
template = struct( ...
    "candidate_key", "", ...
    "selected", false, ...
    "mode", "", ...
    "mode_order", 0, ...
    "source", "", ...
    "role", "", ...
    "fs_hz", 0, ...
    "target_rbw_hz", 0, ...
    "total_decimation", 0, ...
    "fir_taps", 0, ...
    "design_method", "", ...
    "window", "", ...
    "beta", NaN, ...
    "cutoff_hz", NaN, ...
    "actual_enbw_hz", 0, ...
    "enbw_over_rbw", 0, ...
    "correction_db", 0, ...
    "passband_flatness_db", 0, ...
    "passband_flatness_0p45_db", 0, ...
    "att_2x_db", 0, ...
    "att_5x_db", 0, ...
    "observe_points", 0, ...
    "skip_points", 0, ...
    "accum_target", 0, ...
    "nyquist_hz", 0, ...
    "freq_2x_hz", 0, ...
    "freq_5x_hz", 0, ...
    "status", "", ...
    "strict_pass", false, ...
    "acceptable_pass", false, ...
    "note", "");
rows = repmat(template, 0, 1);
end

function db = empty_coeff_db()
template = struct("candidate_key", "", "mode", "", "coeffs", []);
db = repmat(template, 0, 1);
end

function [rows, coeff_db] = add_candidate(rows, coeff_db, mode, source, role, coeffs, ...
    design_method, window_name, beta, cutoff_hz, note)
coeffs = normalize_coeffs(coeffs(:).');
row = analyze_candidate(mode, source, role, coeffs, design_method, window_name, beta, cutoff_hz, note);
row.candidate_key = make_candidate_key(row);

rows(end + 1) = row;
coeff_db(end + 1).candidate_key = row.candidate_key;
coeff_db(end).mode = row.mode;
coeff_db(end).coeffs = coeffs(:);
end

function key = make_candidate_key(row)
raw_key = sprintf("%s__%s__%s__%dt__%.12g__%.12g", char(row.mode), char(row.source), ...
    char(row.window), row.fir_taps, row.cutoff_hz, row.beta);
key = string(regexprep(raw_key, "[^A-Za-z0-9_.-]", "_"));
end

function row = analyze_candidate(mode, source, role, coeffs, design_method, window_name, beta, cutoff_hz, note)
enbw = mode.fs_hz * sum(coeffs .^ 2) / (sum(coeffs) ^ 2);
enbw_ratio = enbw / mode.rbw_hz;
correction_db = 10.0 * log10(enbw_ratio);

passband_freq_0p4 = linspace(0.0, 0.40 * mode.rbw_hz, 1201);
passband_db_0p4 = mag_db_at(passband_freq_0p4, coeffs, mode.fs_hz);
flatness = max(abs(passband_db_0p4 - passband_db_0p4(1)));

passband_freq_0p45 = linspace(0.0, 0.45 * mode.rbw_hz, 1201);
passband_db_0p45 = mag_db_at(passband_freq_0p45, coeffs, mode.fs_hz);
flatness_0p45 = max(abs(passband_db_0p45 - passband_db_0p45(1)));

att_2x = mag_db_at(2.0 * mode.rbw_hz, coeffs, mode.fs_hz);
att_5x = mag_db_at(min(5.0 * mode.rbw_hz, mode.fs_hz / 2.0), coeffs, mode.fs_hz);

max_flat = 0.20;
if mode.name == "1K"
    max_flat = 0.25;
end

strict_flat = 0.15;
if mode.name == "1K"
    strict_flat = 0.25;
end

strict_pass = enbw_ratio >= 0.99 && enbw_ratio <= 1.01 && ...
    abs(correction_db) <= 0.05 && flatness <= strict_flat && ...
    att_2x <= -70.0 && att_5x <= -90.0;
acceptable_pass = enbw_ratio >= 0.95 && enbw_ratio <= 1.05 && ...
    abs(correction_db) <= 0.22 && flatness <= max_flat && ...
    att_2x <= -60.0 && att_5x <= -80.0;

if strict_pass
    status = "PASS_STRICT";
elseif acceptable_pass
    status = "PASS_ACCEPTABLE";
elseif enbw_ratio >= 0.95 && enbw_ratio <= 1.05 && flatness <= max_flat && ...
        att_2x <= -60.0 && (5.0 * mode.rbw_hz) >= 0.9 * (mode.fs_hz / 2.0)
    status = "BORDERLINE_5X_NEAR_NYQUIST";
else
    status = "FAIL";
end

row = struct();
row.candidate_key = "";
row.selected = false;
row.mode = mode.name;
row.mode_order = mode.order;
row.source = string(source);
row.role = string(role);
row.fs_hz = mode.fs_hz;
row.target_rbw_hz = mode.rbw_hz;
row.total_decimation = mode.total_decimation;
row.fir_taps = numel(coeffs);
row.design_method = string(design_method);
row.window = string(window_name);
row.beta = beta;
row.cutoff_hz = cutoff_hz;
row.actual_enbw_hz = enbw;
row.enbw_over_rbw = enbw_ratio;
row.correction_db = correction_db;
row.passband_flatness_db = flatness;
row.passband_flatness_0p45_db = flatness_0p45;
row.att_2x_db = att_2x;
row.att_5x_db = att_5x;
row.observe_points = mode.observe_points;
row.skip_points = mode.skip_points;
row.accum_target = mode.observe_points + mode.skip_points + numel(coeffs);
row.nyquist_hz = mode.fs_hz / 2.0;
row.freq_2x_hz = 2.0 * mode.rbw_hz;
row.freq_5x_hz = min(5.0 * mode.rbw_hz, mode.fs_hz / 2.0);
row.status = status;
row.strict_pass = strict_pass;
row.acceptable_pass = acceptable_pass;
row.note = string(note);
end

function [rows, coeff_db] = scan_mode(rows, coeff_db, mode, taps_list, cutoff_factors, betas, note)
for taps = taps_list
    for cf = cutoff_factors
        cutoff = cf * mode.rbw_hz;
        coeffs = design_lowpass_fir(taps, mode.fs_hz, cutoff, "hamming", NaN);
        [rows, coeff_db] = add_candidate(rows, coeff_db, mode, ...
            "recalc_scan", "tap_cutoff_scan", coeffs, "windowed_sinc", ...
            "hamming", NaN, cutoff, note);
    end
    for beta = betas
        for cf = cutoff_factors
            cutoff = cf * mode.rbw_hz;
            coeffs = design_lowpass_fir(taps, mode.fs_hz, cutoff, "kaiser", beta);
            [rows, coeff_db] = add_candidate(rows, coeff_db, mode, ...
                "recalc_scan", "tap_cutoff_scan", coeffs, "windowed_sinc", ...
                "kaiser", beta, cutoff, note);
        end
    end
end
end

function selected_key = select_first(rows, mode_name, source)
selected_key = "";
for idx = 1:numel(rows)
    if rows(idx).mode == string(mode_name) && rows(idx).source == string(source)
        selected_key = rows(idx).candidate_key;
        return;
    end
end
end

function selected_key = select_10k(rows)
idxs = [];
for idx = 1:numel(rows)
    if rows(idx).mode == "10K" && rows(idx).role == "10k_conflict_candidate"
        idxs(end + 1) = idx; %#ok<AGROW>
    end
end
if isempty(idxs)
    selected_key = "";
    return;
end
scores = zeros(numel(idxs), 1);
for k = 1:numel(idxs)
    r = rows(idxs(k));
    pass_penalty = 0;
    if ~r.acceptable_pass
        pass_penalty = 1000;
    end
    strict_bonus = 0;
    if r.strict_pass
        strict_bonus = -100;
    end
    current_bonus = 0;
    if r.source == "firmware_current_coeffs"
        current_bonus = -2;
    end
    scores(k) = pass_penalty + strict_bonus + current_bonus + ...
        100 * abs(r.enbw_over_rbw - 1.0) + r.passband_flatness_db + ...
        max(0, r.att_2x_db + 70) + max(0, r.att_5x_db + 90);
end
[~, local_idx] = min(scores);
selected_key = rows(idxs(local_idx)).candidate_key;
end

function selected_key = select_recalc(rows, mode_name)
idxs = [];
for idx = 1:numel(rows)
    if rows(idx).mode == string(mode_name) && rows(idx).source == "recalc_scan"
        idxs(end + 1) = idx; %#ok<AGROW>
    end
end
if isempty(idxs)
    selected_key = "";
    return;
end
pass_idxs = [];
for k = 1:numel(idxs)
    if rows(idxs(k)).acceptable_pass
        pass_idxs(end + 1) = idxs(k); %#ok<AGROW>
    end
end
flat_0p45_idxs = [];
for k = 1:numel(pass_idxs)
    if rows(pass_idxs(k)).passband_flatness_0p45_db <= 0.20
        flat_0p45_idxs(end + 1) = pass_idxs(k); %#ok<AGROW>
    end
end
if ~isempty(flat_0p45_idxs)
    pass_idxs = flat_0p45_idxs;
end
if isempty(pass_idxs)
    for k = 1:numel(idxs)
        if rows(idxs(k)).status == "BORDERLINE_5X_NEAR_NYQUIST"
            pass_idxs(end + 1) = idxs(k); %#ok<AGROW>
        end
    end
end
if isempty(pass_idxs)
    pass_idxs = idxs;
end
scores = zeros(numel(pass_idxs), 1);
for k = 1:numel(pass_idxs)
    r = rows(pass_idxs(k));
    pass_penalty = 0;
    if ~r.acceptable_pass
        pass_penalty = 10000;
    end
    strict_bonus = 0;
    if r.strict_pass
        strict_bonus = -100;
    end
    scores(k) = pass_penalty + strict_bonus + ...
        r.fir_taps * 1000 + ...
        100 * abs(r.enbw_over_rbw - 1.0) + ...
        r.passband_flatness_db + ...
        max(0, r.passband_flatness_0p45_db - 0.20) * 100 + ...
        max(0, r.att_2x_db + 70) + max(0, r.att_5x_db + 90);
end
[~, local_idx] = min(scores);
selected_key = rows(pass_idxs(local_idx)).candidate_key;
end

function coeff_tbl = build_coeff_table(selected_tbl, coeff_db)
coeff_tbl = table();
for idx = 1:height(selected_tbl)
    key = selected_tbl.candidate_key(idx);
    coeffs = get_coeffs(coeff_db, key);
    tmp = table( ...
        repmat(selected_tbl.mode(idx), numel(coeffs), 1), ...
        repmat(selected_tbl.source(idx), numel(coeffs), 1), ...
        repmat(selected_tbl.design_method(idx), numel(coeffs), 1), ...
        repmat(selected_tbl.window(idx), numel(coeffs), 1), ...
        repmat(selected_tbl.cutoff_hz(idx), numel(coeffs), 1), ...
        repmat(selected_tbl.beta(idx), numel(coeffs), 1), ...
        (0:(numel(coeffs) - 1)).', ...
        coeffs(:), ...
        'VariableNames', {'mode', 'source', 'design_method', 'window', ...
            'cutoff_hz', 'beta', 'tap_index', 'coefficient'});
    coeff_tbl = [coeff_tbl; tmp]; %#ok<AGROW>
end
end

function write_response_outputs(selected_tbl, coeff_db, out_dir)
% Always include the selected candidates.
for idx = 1:height(selected_tbl)
    key = selected_tbl.candidate_key(idx);
    coeffs = get_coeffs(coeff_db, key);
    stem = sprintf("pl_final_rbw_response_%s_%s", selected_tbl.mode(idx), selected_tbl.source(idx));
    write_one_response(out_dir, stem, selected_tbl.mode(idx), selected_tbl.target_rbw_hz(idx), ...
        selected_tbl.fs_hz(idx), coeffs);
end
end

function write_one_response(out_dir, stem, mode_name, rbw_hz, fs_hz, coeffs)
freq = linspace(0.0, fs_hz / 2.0, 12001);
mag_db = mag_db_at(freq, coeffs, fs_hz);
tbl = table(freq(:), (freq(:) ./ rbw_hz), mag_db(:), ...
    'VariableNames', {'freq_hz', 'freq_over_rbw', 'magnitude_db'});
writetable(tbl, fullfile(out_dir, stem + ".csv"));

try
    fig = figure("Visible", "off");
    plot(freq ./ rbw_hz, max(mag_db, -180), "LineWidth", 1.2);
    grid on;
    xlabel("Offset / nominal RBW");
    ylabel("Magnitude (dB)");
    title(sprintf("PL final RBW %s", mode_name), "Interpreter", "none");
    yline(-60.0, ":", "-60 dB");
    yline(-80.0, ":", "-80 dB");
    xline(2.0, "--", "2x");
    xline(5.0, "--", "5x");
    xlim([0, min(max(freq ./ rbw_hz), 12)]);
    ylim([-180, 5]);
    exportgraphics(fig, fullfile(out_dir, stem + ".png"), "Resolution", 150);
    close(fig);
catch err
    warning("Unable to write response PNG for %s: %s", stem, err.message);
end
end

function write_summary_markdown(path, selected_tbl, metrics_tbl, required_inputs, input_bytes, script_path)
fid = fopen(path, "w", "n", "UTF-8");
if fid < 0
    error("Unable to write summary: %s", path);
end
cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>

fprintf(fid, "# PL RBW FIR final offline recalculation\n\n");
fprintf(fid, "Date: 2026-06-05\n\n");
fprintf(fid, "## Execution\n\n");
fprintf(fid, "- MATLAB used: yes\n");
fprintf(fid, "- MATLAB version: `%s`\n", version);
fprintf(fid, "- Script path: `%s`\n", script_path);
fprintf(fid, "- Output directory: `%s`\n", fileparts(path));
fprintf(fid, "- Scope: final RBW FIR at final per-mode Fs; legacy CIC response is not included in these FIR-only ENBW numbers.\n\n");

fprintf(fid, "## Required inputs read\n\n");
fprintf(fid, "| Input | Bytes read |\n");
fprintf(fid, "| --- | ---: |\n");
for idx = 1:numel(required_inputs)
    fprintf(fid, "| `%s` | %.0f |\n", required_inputs(idx), input_bytes(idx));
end

fprintf(fid, "\n## Selected parameters\n\n");
fprintf(fid, "| Mode | Fs | RBW | Source | Taps | Method/window | Cutoff | Beta | ENBW | ENBW/RBW | Correction | Flatness 0.4RBW | Flatness 0.45RBW | 2x | 5x | Observe | Skip | Accum | Status |\n");
fprintf(fid, "| ---: | ---: | ---: | --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |\n");
for idx = 1:height(selected_tbl)
    beta_txt = "n/a";
    if ~isnan(selected_tbl.beta(idx))
        beta_txt = sprintf("%.1f", selected_tbl.beta(idx));
    end
    cutoff_txt = "n/a";
    if ~isnan(selected_tbl.cutoff_hz(idx))
        cutoff_txt = sprintf("%.1f", selected_tbl.cutoff_hz(idx));
    end
    fprintf(fid, "| %s | %.0f | %.0f | %s | %d | %s/%s | %s | %s | %.2f | %.5f | %+0.4f dB | %.4f dB | %.4f dB | %.2f dB | %.2f dB | %d | %d | %d | %s |\n", ...
        selected_tbl.mode(idx), selected_tbl.fs_hz(idx), selected_tbl.target_rbw_hz(idx), ...
        selected_tbl.source(idx), selected_tbl.fir_taps(idx), ...
        selected_tbl.design_method(idx), selected_tbl.window(idx), ...
        cutoff_txt, beta_txt, selected_tbl.actual_enbw_hz(idx), ...
        selected_tbl.enbw_over_rbw(idx), selected_tbl.correction_db(idx), ...
        selected_tbl.passband_flatness_db(idx), selected_tbl.passband_flatness_0p45_db(idx), ...
        selected_tbl.att_2x_db(idx), ...
        selected_tbl.att_5x_db(idx), selected_tbl.observe_points(idx), ...
        selected_tbl.skip_points(idx), selected_tbl.accum_target(idx), ...
        selected_tbl.status(idx));
end

fprintf(fid, "\n## 10K conflict conclusion\n\n");
tenk = metrics_tbl(metrics_tbl.mode == "10K" & metrics_tbl.role == "10k_conflict_candidate", :);
for idx = 1:height(tenk)
    chosen = "";
    if tenk.selected(idx)
        chosen = " SELECTED";
    end
    fprintf(fid, "- `%s`: ENBW %.2f Hz, ENBW/RBW %.5f, correction %+0.4f dB, flatness %.4f dB, 2x %.2f dB, 5x %.2f dB.%s\n", ...
        tenk.source(idx), tenk.actual_enbw_hz(idx), tenk.enbw_over_rbw(idx), ...
        tenk.correction_db(idx), tenk.passband_flatness_db(idx), ...
        tenk.att_2x_db(idx), tenk.att_5x_db(idx), chosen);
end
fprintf(fid, "\nRecommendation: use the Scheme B 100 kSPS 10K coefficient set for the final PL RBW table. The current firmware `r130_validation` coefficients should stay only as a 1 MSPS validation-path artifact, not as the final 100 kSPS 10K RBW FIR.\n");
fprintf(fid, "\nImportant Fs note: the current firmware `r130_validation` 10K ENBW near 10001.51 Hz belongs to its 1 MSPS validation context. At the final 100 kSPS RBW FIR rate, the same coefficients evaluate to about 1000 Hz ENBW, so they must not be frozen as the final 10K coefficients.\n");

fprintf(fid, "\n## Recalculation notes\n\n");
fprintf(fid, "- 30K and 300K old Scheme B coefficients were re-evaluated at the final Fs only as invalid reference rows; they are not selected.\n");
fprintf(fid, "- 30K scan tested taps 192/256/320/384 at Fs=325 kSPS.\n");
fprintf(fid, "- 300K scan tested taps 96/128/160/192 at Fs=3.25 MSPS.\n");
fprintf(fid, "- Selection rule: smallest taps among candidates meeting acceptance targets, then ENBW closeness/flatness/stopband score.\n");
fprintf(fid, "- Selection flatness uses the historical Scheme B `0~0.4*RBW` passband window for comparability; `0~0.45*RBW` is also reported as a stricter risk observation.\n");
fprintf(fid, "- For newly recalculated 30K/300K modes, final selection additionally prefers candidates with `0~0.45*RBW` flatness <= 0.20 dB when available.\n");
fprintf(fid, "- `accum_target = observe + skip + taps`.\n");

fprintf(fid, "\n## Output files\n\n");
fprintf(fid, "- `pl_final_rbw_recalc_summary.md`\n");
fprintf(fid, "- `pl_final_rbw_recalc_metrics.csv`\n");
fprintf(fid, "- `pl_final_rbw_selected_parameters.csv`\n");
fprintf(fid, "- `pl_final_rbw_final_coefficients_float.csv`\n");
fprintf(fid, "- `pl_final_rbw_response_<mode>_<source>.csv`\n");
fprintf(fid, "- `pl_final_rbw_response_<mode>_<source>.png` when MATLAB graphics export succeeds\n");
end

function coeffs = get_coeffs(coeff_db, key)
for idx = 1:numel(coeff_db)
    if coeff_db(idx).candidate_key == key
        coeffs = coeff_db(idx).coeffs;
        return;
    end
end
error("Coefficient key not found: %s", key);
end

function coeffs = parse_c_coeff_array(c_text, array_name)
ct = char(c_text);
name = char(array_name);
marker = ['static const float ' name];
start_idx = strfind(ct, marker);
if isempty(start_idx)
    error("Unable to find C coefficient array marker: %s", array_name);
end
array_start = start_idx(1);
tail = ct(array_start:end);
open_rel = strfind(tail, '{');
if isempty(open_rel)
    error("Unable to find opening brace for C coefficient array: %s", array_name);
end
body_tail = tail((open_rel(1) + 1):end);
close_rel = strfind(body_tail, '};');
if isempty(close_rel)
    error("Unable to find closing brace for C coefficient array: %s", array_name);
end
body = body_tail(1:(close_rel(1) - 1));
body = strrep(body, 'f', '');
matches = regexp(body, '[-+]?\d*\.?\d+([eE][-+]?\d+)?', 'match');
if isempty(matches)
    error("No numeric coefficients parsed from C array: %s", array_name);
end
coeffs = zeros(1, numel(matches));
for idx = 1:numel(matches)
    coeffs(idx) = str2double(matches{idx});
end
coeffs = normalize_coeffs(coeffs);
end

function coeffs = read_coeff_csv(path, mode_name)
tbl = readtable(path, "TextType", "string");
mask = tbl.mode == string(mode_name);
if ~any(mask)
    error("Mode %s not found in coefficient CSV: %s", mode_name, path);
end
sub = sortrows(tbl(mask, :), "tap_index");
coeffs = normalize_coeffs(sub.coefficient(:).');
end

function coeffs = design_lowpass_fir(taps, fs_hz, cutoff_hz, window_name, beta)
fc = min(0.499999, max(1e-9, cutoff_hz / fs_hz));
n = 0:(taps - 1);
center = (taps - 1) / 2.0;
x = n - center;
coeffs = 2.0 * fc .* local_sinc(2.0 * fc .* x);
switch string(window_name)
    case "hamming"
        win = 0.54 - 0.46 * cos(2.0 * pi .* n ./ (taps - 1));
    case "kaiser"
        win = local_kaiser(taps, beta);
    otherwise
        error("Unknown window: %s", window_name);
end
coeffs = normalize_coeffs(coeffs .* win);
end

function y = local_sinc(x)
y = ones(size(x));
mask = abs(x) > 1e-14;
y(mask) = sin(pi .* x(mask)) ./ (pi .* x(mask));
end

function win = local_kaiser(taps, beta)
n = 0:(taps - 1);
alpha = (taps - 1) / 2.0;
arg = beta .* sqrt(max(0.0, 1.0 - ((n - alpha) ./ alpha) .^ 2));
win = besseli(0, arg) ./ besseli(0, beta);
end

function coeffs = normalize_coeffs(coeffs)
coeffs = coeffs(:).';
s = sum(coeffs);
if abs(s) > 1e-15
    coeffs = coeffs ./ s;
end
end

function db = mag_db_at(freq_hz, coeffs, fs_hz)
mag = fir_mag_at(freq_hz, coeffs, fs_hz);
db = 20.0 .* log10(max(abs(mag), 1e-300));
end

function mag = fir_mag_at(freq_hz, coeffs, fs_hz)
shape = size(freq_hz);
freq = double(freq_hz(:));
n = 0:(numel(coeffs) - 1);
mag = zeros(numel(freq), 1);
chunk = 2048;
for start_idx = 1:chunk:numel(freq)
    stop_idx = min(start_idx + chunk - 1, numel(freq));
    phase = -2j * pi .* (freq(start_idx:stop_idx) ./ fs_hz) .* n;
    mag(start_idx:stop_idx) = abs(exp(phase) * coeffs(:));
end
mag = reshape(mag, shape);
end

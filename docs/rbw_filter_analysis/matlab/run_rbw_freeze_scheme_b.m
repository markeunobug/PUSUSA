% PuSuSA RBW ENBW Scheme B freeze export.
%
% Run from MATLAB:
%   cd C:\learning\pusu_V2
%   run("docs/rbw_filter_analysis/matlab/run_rbw_freeze_scheme_b.m")

clear;
clc;

repo_root = fileparts(fileparts(fileparts(fileparts(mfilename("fullpath")))));
addpath(fullfile(repo_root, "tools", "matlab"));

out_dir = fullfile(repo_root, "docs", "rbw_filter_analysis", "matlab");
if ~exist(out_dir, "dir")
    mkdir(out_dir);
end

fprintf("PuSuSA RBW ENBW Scheme B freeze export\n");

profile = "alias_rework_1k";
modes = rbw_enbw_lib.default_modes(profile);

specs = struct([]);
specs(1).mode = "1K";
specs(1).taps = 768;
specs(1).method = "kaiser";
specs(1).opts = struct("cutoff_hz", 520.0, "kaiser_beta", 3.0);
specs(1).scheme_status = "SCHEME_B_ACCEPTED";
specs(1).acceptance_note = "Flatness 0.206 dB accepted under first-pass 0.25 dB limit.";

specs(2).mode = "10K";
specs(2).taps = 256;
specs(2).method = "kaiser";
specs(2).opts = struct("cutoff_hz", 5200.0, "kaiser_beta", 5.0);
specs(2).scheme_status = "PASS";
specs(2).acceptance_note = "PASS candidate from MATLAB search.";

specs(3).mode = "30K";
specs(3).taps = 256;
specs(3).method = "kaiser";
specs(3).opts = struct("cutoff_hz", 15600.0, "kaiser_beta", 5.0);
specs(3).scheme_status = "PASS";
specs(3).acceptance_note = "PASS candidate from MATLAB search.";

specs(4).mode = "100K";
specs(4).taps = 128;
specs(4).method = "hamming_sinc";
specs(4).opts = struct("cutoff_hz", 54000.0);
specs(4).scheme_status = "PASS";
specs(4).acceptance_note = "PASS candidate from MATLAB search.";

specs(5).mode = "300K";
specs(5).taps = 128;
specs(5).method = "hamming_sinc";
specs(5).opts = struct("cutoff_hz", 162000.0);
specs(5).scheme_status = "PASS";
specs(5).acceptance_note = "PASS candidate from MATLAB search.";

specs(6).mode = "1M";
specs(6).taps = 96;
specs(6).method = "kaiser";
specs(6).opts = struct("cutoff_hz", 540000.0, "kaiser_beta", 4.0);
specs(6).scheme_status = "PASS";
specs(6).acceptance_note = "Accepted 96-tap 1M candidate.";

rows = struct([]);
coeff_rows = table();

for idx = 1:numel(specs)
    spec = specs(idx);
    mode = modes(strcmp({modes.name}, spec.mode));
    if isempty(mode)
        error("Mode %s not found in profile %s.", spec.mode, profile);
    end
    mode.fir_taps = spec.taps;

    coeffs = rbw_enbw_lib.design_fir(mode, spec.method, spec.opts);
    row = rbw_enbw_lib.analyze_coeffs(profile, mode, spec.method, ...
        sprintf("%s %s", spec.method, rbw_enbw_lib.opts_to_string(spec.opts)), ...
        coeffs, spec.opts, 60001, true);
    row = rbw_enbw_lib.add_engineering_constraints(row, ...
        rbw_enbw_lib.default_taps_for_mode(spec.mode), 1152);
    row.scheme_status = spec.scheme_status;
    row.acceptance_note = spec.acceptance_note;
    row.design_opts = [];

    if isempty(rows)
        rows = row;
    else
        rows(idx) = row; %#ok<SAGROW>
    end

    coeff_tbl = table( ...
        repmat(string(mode.name), numel(coeffs), 1), ...
        repmat(string(row.scheme_status), numel(coeffs), 1), ...
        repmat(string(row.design_method), numel(coeffs), 1), ...
        repmat(string(row.design_opts_json), numel(coeffs), 1), ...
        (0:(numel(coeffs) - 1)).', ...
        coeffs(:), ...
        'VariableNames', {'mode', 'scheme_status', 'design_method', ...
            'design_options', 'tap_index', 'coefficient'});
    coeff_rows = [coeff_rows; coeff_tbl]; %#ok<AGROW>

    response_max_hz = min(mode.fs_out_hz / 2.0, max(12.0 * mode.rbw_hz, 100e3));
    response_freq = linspace(0.0, response_max_hz, 8001);
    response_db = rbw_enbw_lib.db20(rbw_enbw_lib.total_mag(response_freq, mode, coeffs));
    response_tbl = table( ...
        response_freq(:), ...
        (response_freq(:) ./ mode.rbw_hz), ...
        response_db(:), ...
        'VariableNames', {'freq_hz', 'freq_over_rbw', 'magnitude_db'});
    response_stem = sprintf("rbw_scheme_b_response_%s", mode.name);
    writetable(response_tbl, fullfile(out_dir, response_stem + ".csv"));

    fig = figure("Visible", "off");
    plot(response_freq ./ mode.rbw_hz, max(response_db, -180), "LineWidth", 1.25);
    grid on;
    xlabel("Offset / nominal RBW");
    ylabel("Magnitude (dB)");
    title(sprintf("Scheme B %s: %s", mode.name, row.design_method), ...
        "Interpreter", "none");
    xlim([0, max(response_freq ./ mode.rbw_hz)]);
    ylim([-180, 5]);
    yline(-60.0, ":", "-60 dB");
    yline(-80.0, ":", "-80 dB");
    exportgraphics(fig, fullfile(out_dir, response_stem + ".png"), "Resolution", 150);
    close(fig);

    fprintf("%-4s %s taps=%d ENBW/RBW=%.4f flat=%.3f dB accum=%d\n", ...
        mode.name, row.scheme_status, row.fir_taps, row.enbw_main_over_rbw, ...
        row.passband_flatness_db, row.accum_target);
end

scheme_tbl = struct2table(rows);
writetable(scheme_tbl, fullfile(out_dir, "rbw_scheme_b_metrics.csv"));
writetable(coeff_rows, fullfile(out_dir, "rbw_scheme_b_coefficients_float.csv"));
write_scheme_b_markdown(fullfile(out_dir, "rbw_scheme_b_metrics.md"), rows);

fprintf("Wrote Scheme B outputs to:\n%s\n", out_dir);

function write_scheme_b_markdown(path, rows)
fid = fopen(path, "w");
if fid < 0
    error("Unable to open %s for writing", path);
end
cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>

fprintf(fid, "# RBW Scheme B Metrics\n\n");
fprintf(fid, "Generated by `docs/rbw_filter_analysis/matlab/run_rbw_freeze_scheme_b.m`.\n\n");
fprintf(fid, "| Mode | Status | Method/options | CIC R/N | Fs out | Taps | ENBW | ENBW/RBW | Correction | Flatness | 2x | 5x | Accum target | Required buffer |\n");
fprintf(fid, "| ---: | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n");
for idx = 1:numel(rows)
    r = rows(idx);
    method_txt = sprintf("%s `%s`", r.design_method, r.design_opts_json);
    fprintf(fid, "| %s | %s | %s | %d / %d | %.1f | %d | %.2f | %.4f | %+0.2f dB | %.3f dB | %.2f dB | %.2f dB | %d | %d |\n", ...
        r.mode, r.scheme_status, method_txt, r.cic_r, r.cic_n, r.fs_out_hz, ...
        r.fir_taps, r.enbw_main_hz, r.enbw_main_over_rbw, ...
        r.noise_correction_db, r.passband_flatness_db, r.att_2_x_rbw_db, ...
        r.att_5_x_rbw_db, r.accum_target, r.required_accum_buffer_size);
end

fprintf(fid, "\n## Notes\n\n");
fprintf(fid, "- Scheme B uses `alias_rework_1k`, so 1 kHz RBW uses `R=1300`.\n");
fprintf(fid, "- 1 kHz flatness is accepted under the first-pass relaxed `<=0.25 dB` limit.\n");
fprintf(fid, "- `ACCUM_BUFFER_SIZE` must be at least 1152 for this parameter set.\n");
fprintf(fid, "- These float coefficients are the source for the next firmware-table conversion step.\n");
end

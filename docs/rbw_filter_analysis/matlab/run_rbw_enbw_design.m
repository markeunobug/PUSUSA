% PuSuSA RBW ENBW offline design and candidate search.
%
% Run from MATLAB:
%   cd C:\learning\pusu_V2
%   run("docs/rbw_filter_analysis/matlab/run_rbw_enbw_design.m")

clear;
clc;

repo_root = fileparts(fileparts(fileparts(fileparts(mfilename("fullpath")))));
addpath(fullfile(repo_root, "tools", "matlab"));

out_dir = fullfile(repo_root, "docs", "rbw_filter_analysis", "matlab");
if ~exist(out_dir, "dir")
    mkdir(out_dir);
end

profiles = ["firmware_current", "alias_rework_1k"];
all_metric_rows = struct([]);
selection_rows = struct([]);
coeff_rows = table();
metric_idx = 0;
selection_idx = 0;

fprintf("PuSuSA RBW ENBW candidate search\n");
fprintf("Signal toolbox FIR support: %d\n", rbw_enbw_lib.has_signal_toolbox());
fprintf("Equiripple FIR support: %d\n\n", rbw_enbw_lib.has_equiripple());

for pidx = 1:numel(profiles)
    profile = profiles(pidx);
    modes = rbw_enbw_lib.default_modes(profile);
    fprintf("Profile: %s\n", profile);

    for midx = 1:numel(modes)
        mode = modes(midx);
        fprintf("  Searching %-4s R=%d Fs_out=%.1f Hz taps=%d ... ", ...
            mode.name, mode.cic_r, mode.fs_out_hz, mode.fir_taps);

        candidate_rows = rbw_enbw_lib.search_candidates(profile, mode);
        for ridx = 1:numel(candidate_rows)
            metric_idx = metric_idx + 1;
            candidate_rows(ridx).design_opts = [];
            if isempty(all_metric_rows)
                all_metric_rows = candidate_rows(ridx);
            else
                all_metric_rows(metric_idx) = candidate_rows(ridx); %#ok<SAGROW>
            end
        end

        [best_row, best_coeffs] = rbw_enbw_lib.select_best_candidate(profile, mode);
        selection_idx = selection_idx + 1;
        best_row.design_opts = [];
        if isempty(selection_rows)
            selection_rows = best_row;
        else
            selection_rows(selection_idx) = best_row; %#ok<SAGROW>
        end

        response_max_hz = min(mode.fs_out_hz / 2.0, max(12.0 * mode.rbw_hz, 100e3));
        response_freq = linspace(0.0, response_max_hz, 8001);
        response_mag = rbw_enbw_lib.total_mag(response_freq, mode, best_coeffs);
        response_db = rbw_enbw_lib.db20(response_mag);
        response_tbl = table( ...
            response_freq(:), ...
            (response_freq(:) ./ mode.rbw_hz), ...
            response_db(:), ...
            'VariableNames', {'freq_hz', 'freq_over_rbw', 'magnitude_db'});

        response_stem = sprintf("rbw_candidate_response_%s_%s", profile, mode.name);
        writetable(response_tbl, fullfile(out_dir, response_stem + ".csv"));

        fig = figure("Visible", "off");
        plot(response_freq ./ mode.rbw_hz, max(response_db, -180), "LineWidth", 1.25);
        grid on;
        xlabel("Offset / nominal RBW");
        ylabel("Magnitude (dB)");
        title(sprintf("%s %s candidate: %s", profile, mode.name, best_row.design_method), ...
            "Interpreter", "none");
        xlim([0, max(response_freq ./ mode.rbw_hz)]);
        ylim([-180, 5]);
        yline(-60.0, ":", "-60 dB");
        yline(-80.0, ":", "-80 dB");
        exportgraphics(fig, fullfile(out_dir, response_stem + ".png"), "Resolution", 150);
        close(fig);

        coeff_tbl = table( ...
            repmat(string(profile), numel(best_coeffs), 1), ...
            repmat(string(mode.name), numel(best_coeffs), 1), ...
            repmat(string(best_row.status), numel(best_coeffs), 1), ...
            repmat(string(best_row.design_method), numel(best_coeffs), 1), ...
            repmat(string(best_row.design_opts_json), numel(best_coeffs), 1), ...
            (0:(numel(best_coeffs) - 1)).', ...
            best_coeffs(:), ...
            'VariableNames', {'profile', 'mode', 'status', 'design_method', ...
                'design_options', 'tap_index', 'coefficient'});
        coeff_rows = [coeff_rows; coeff_tbl]; %#ok<AGROW>

        fprintf("%s ENBW/RBW=%.4f flat=%.3f dB 2x=%.1f dB 5x=%.1f dB\n", ...
            best_row.status, best_row.enbw_main_over_rbw, ...
            best_row.passband_flatness_db, best_row.att_2_x_rbw_db, ...
            best_row.att_5_x_rbw_db);
    end
    fprintf("\n");
end

metrics_tbl = struct2table(all_metric_rows);
selection_tbl = struct2table(selection_rows);
writetable(metrics_tbl, fullfile(out_dir, "rbw_candidate_metrics.csv"));
writetable(coeff_rows, fullfile(out_dir, "rbw_candidate_coefficients_float.csv"));

rbw_enbw_lib.write_candidate_metrics_markdown( ...
    fullfile(out_dir, "rbw_candidate_metrics.md"), selection_rows, metrics_tbl);
rbw_enbw_lib.write_candidate_selection_markdown( ...
    fullfile(out_dir, "rbw_candidate_selection.md"), selection_rows);

fprintf("Wrote candidate outputs to:\n%s\n", out_dir);

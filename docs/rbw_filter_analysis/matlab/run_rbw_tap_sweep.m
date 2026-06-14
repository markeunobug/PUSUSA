% PuSuSA RBW ENBW Step 1c tap sweep for unresolved candidate modes.
%
% Run from MATLAB:
%   cd C:\learning\pusu_V2
%   run("docs/rbw_filter_analysis/matlab/run_rbw_tap_sweep.m")

clear;
clc;

repo_root = fileparts(fileparts(fileparts(fileparts(mfilename("fullpath")))));
addpath(fullfile(repo_root, "tools", "matlab"));

out_dir = fullfile(repo_root, "docs", "rbw_filter_analysis", "matlab");
if ~exist(out_dir, "dir")
    mkdir(out_dir);
end

accum_buffer_size = 768;
rows = struct([]);
row_idx = 0;

fprintf("PuSuSA RBW ENBW tap sweep\n");
fprintf("Signal toolbox FIR support: %d\n", rbw_enbw_lib.has_signal_toolbox());
fprintf("Equiripple FIR support: %d\n\n", rbw_enbw_lib.has_equiripple());

jobs = struct([]);
jobs(1).profile = "alias_rework_1k";
jobs(1).mode_name = "1K";
jobs(1).taps = [256, 384, 512, 640, 768, 1024];
jobs(1).base_taps = 256;

jobs(2).profile = "firmware_current";
jobs(2).mode_name = "1M";
jobs(2).taps = [64, 96, 128, 160, 192, 256];
jobs(2).base_taps = 64;

jobs(3).profile = "alias_rework_1k";
jobs(3).mode_name = "1M";
jobs(3).taps = [64, 96, 128, 160, 192, 256];
jobs(3).base_taps = 64;

for jidx = 1:numel(jobs)
    job = jobs(jidx);
    modes = rbw_enbw_lib.default_modes(job.profile);
    mode = modes(strcmp({modes.name}, job.mode_name));
    if isempty(mode)
        error("Mode %s not found for profile %s.", job.mode_name, job.profile);
    end

    fprintf("Case: %s / %s\n", job.profile, job.mode_name);
    for tidx = 1:numel(job.taps)
        taps = job.taps(tidx);
        fprintf("  taps=%d ... ", taps);
        [best_row, best_coeffs] = rbw_enbw_lib.select_best_candidate_for_taps( ...
            job.profile, mode, taps);
        best_row = rbw_enbw_lib.add_engineering_constraints(best_row, ...
            job.base_taps, accum_buffer_size);
        best_row.design_opts = [];

        row_idx = row_idx + 1;
        if isempty(rows)
            rows = best_row;
        else
            rows(row_idx) = best_row; %#ok<SAGROW>
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

        response_stem = sprintf("rbw_tap_sweep_%s_%s_%dtaps", ...
            job.profile, job.mode_name, taps);
        writetable(response_tbl, fullfile(out_dir, response_stem + ".csv"));

        fig = figure("Visible", "off");
        plot(response_freq ./ mode.rbw_hz, max(response_db, -180), "LineWidth", 1.25);
        grid on;
        xlabel("Offset / nominal RBW");
        ylabel("Magnitude (dB)");
        title(sprintf("%s %s %d taps: %s", ...
            job.profile, job.mode_name, taps, best_row.design_method), ...
            "Interpreter", "none");
        xlim([0, max(response_freq ./ mode.rbw_hz)]);
        ylim([-180, 5]);
        yline(-60.0, ":", "-60 dB");
        yline(-80.0, ":", "-80 dB");
        exportgraphics(fig, fullfile(out_dir, response_stem + ".png"), "Resolution", 150);
        close(fig);

        fprintf("%s ENBW/RBW=%.4f flat=%.3f dB 2x=%.1f dB 5x=%.1f dB accum=%d fits=%d ops=%.2fx\n", ...
            best_row.status, best_row.enbw_main_over_rbw, best_row.passband_flatness_db, ...
            best_row.att_2_x_rbw_db, best_row.att_5_x_rbw_db, ...
            best_row.accum_target, best_row.fits_accum_buffer, best_row.fir_ops_relative);
    end
    fprintf("\n");
end

tap_sweep_tbl = struct2table(rows);
writetable(tap_sweep_tbl, fullfile(out_dir, "rbw_candidate_tap_sweep.csv"));
rbw_enbw_lib.write_tap_sweep_markdown( ...
    fullfile(out_dir, "rbw_candidate_tap_sweep.md"), rows);

fprintf("Wrote tap sweep outputs to:\n%s\n", out_dir);

classdef rbw_enbw_lib
    % Helper routines for PuSuSA RBW ENBW offline analysis.
    %
    % All methods are static so this file can be used from a plain MATLAB
    % script without creating objects. The model mirrors tools/rbw_filter_analysis.py:
    % DDC -> normalized CIC decimator -> post-decimation FIR.

    methods (Static)
        function modes = default_modes(profile)
            if nargin < 1 || strlength(string(profile)) == 0
                profile = "firmware_current";
            end

            adc_fs_hz = 130e6;
            names = ["1K", "10K", "30K", "100K", "300K", "1M"];
            rbw_hz = [1e3, 10e3, 30e3, 100e3, 300e3, 1e6];

            switch string(profile)
                case "firmware_current"
                    cic_r = [13000, 1300, 433, 130, 43, 13];
                case "alias_rework_1k"
                    cic_r = [1300, 1300, 433, 130, 43, 13];
                otherwise
                    error("Unknown RBW profile: %s", profile);
            end

            cic_n = [5, 5, 5, 5, 4, 4];
            fir_taps = [256, 256, 256, 128, 128, 64];
            observe_points = [256, 256, 256, 384, 384, 384];
            skip_points = [128, 128, 128, 64, 64, 32];

            modes = struct([]);
            for idx = 1:numel(names)
                modes(idx).name = char(names(idx));
                modes(idx).rbw_hz = rbw_hz(idx);
                modes(idx).cic_r = cic_r(idx);
                modes(idx).cic_n = cic_n(idx);
                modes(idx).fir_taps = fir_taps(idx);
                modes(idx).observe_points = observe_points(idx);
                modes(idx).skip_points = skip_points(idx);
                modes(idx).adc_fs_hz = adc_fs_hz;
                modes(idx).fs_out_hz = adc_fs_hz / cic_r(idx);
            end
        end

        function coeffs = design_fir(mode, method, opts)
            if nargin < 2 || strlength(string(method)) == 0
                method = "hamming_sinc";
            end
            if nargin < 3
                opts = struct();
            end

            switch string(method)
                case "hamming_sinc"
                    coeffs = rbw_enbw_lib.design_hamming_sinc(mode, opts);
                case "kaiser"
                    coeffs = rbw_enbw_lib.design_kaiser(mode, opts);
                case "equiripple"
                    coeffs = rbw_enbw_lib.design_equiripple(mode, opts);
                otherwise
                    error("Unknown FIR design method: %s", method);
            end
        end

        function coeffs = design_hamming_sinc(mode, opts)
            if nargin < 2
                opts = struct();
            end
            taps = mode.fir_taps;
            if isfield(opts, "cutoff_hz")
                cutoff_hz = opts.cutoff_hz;
            else
                cutoff_hz = mode.rbw_hz;
            end
            fc_norm = min(0.499, max(1e-6, cutoff_hz / mode.fs_out_hz));
            mid = floor(taps / 2);
            coeffs = zeros(1, taps);

            for n = 0:(taps - 1)
                k = n - mid;
                if k == 0
                    sinc_val = 2.0 * fc_norm;
                else
                    x = 2.0 * pi * fc_norm * k;
                    sinc_val = sin(x) / (pi * k);
                end
                window = 0.54 - 0.46 * cos(2.0 * pi * n / (taps - 1));
                coeffs(n + 1) = sinc_val * window;
            end

            coeff_sum = sum(coeffs);
            if abs(coeff_sum) > 1e-12
                coeffs = coeffs ./ coeff_sum;
            end
        end

        function coeffs = design_kaiser(mode, opts)
            if ~isfield(opts, "kaiser_beta")
                opts.kaiser_beta = 6.0;
            end
            if isfield(opts, "cutoff_hz")
                cutoff_hz = opts.cutoff_hz;
            else
                cutoff_hz = mode.rbw_hz;
            end
            if ~exist("fir1", "file") || ~exist("kaiser", "file")
                error("fir1/kaiser are unavailable.");
            end
            wn = min(0.999, max(1e-6, 2.0 * cutoff_hz / mode.fs_out_hz));
            coeffs = fir1(mode.fir_taps - 1, wn, kaiser(mode.fir_taps, opts.kaiser_beta));
            coeffs = rbw_enbw_lib.normalize_coeffs(coeffs);
        end

        function coeffs = design_equiripple(mode, opts)
            if ~isfield(opts, "passband_hz")
                opts.passband_hz = 0.4 * mode.rbw_hz;
            end
            if ~isfield(opts, "stopband_hz")
                opts.stopband_hz = 2.0 * mode.rbw_hz;
            end
            if ~isfield(opts, "stop_weight")
                opts.stop_weight = 100.0;
            end
            if ~exist("firpm", "file")
                error("firpm is unavailable.");
            end

            nyq = mode.fs_out_hz / 2.0;
            f_pass = min(0.98, max(1e-6, opts.passband_hz / nyq));
            f_stop = min(0.999, max(f_pass + 1e-5, opts.stopband_hz / nyq));
            if f_stop >= 0.999 && f_pass >= 0.98
                error("Invalid equiripple edges for mode %s.", mode.name);
            end
            coeffs = firpm(mode.fir_taps - 1, [0 f_pass f_stop 1], [1 1 0 0], [1 opts.stop_weight]);
            coeffs = rbw_enbw_lib.normalize_coeffs(coeffs);
        end

        function coeffs = normalize_coeffs(coeffs)
            coeffs = coeffs(:).';
            coeff_sum = sum(coeffs);
            if abs(coeff_sum) > 1e-12
                coeffs = coeffs ./ coeff_sum;
            end
        end

        function tf = has_signal_toolbox()
            tf = exist("fir1", "file") && exist("kaiser", "file");
        end

        function tf = has_equiripple()
            tf = false;
            if exist("firpm", "file") ~= 2
                return;
            end
            try
                test_coeffs = firpm(8, [0 0.2 0.4 1], [1 1 0 0]); %#ok<NASGU>
                tf = true;
            catch
                tf = false;
            end
        end

        function taps = default_taps_for_mode(mode_name)
            switch string(mode_name)
                case {"1K", "10K", "30K"}
                    taps = 256;
                case {"100K", "300K"}
                    taps = 128;
                case "1M"
                    taps = 64;
                otherwise
                    error("Unknown RBW mode for default taps: %s", mode_name);
            end
        end

        function candidates = candidate_option_grid(mode)
            candidates = struct([]);
            idx = 0;

            cutoff_factors = rbw_enbw_lib.cutoff_factors_for_mode(mode);
            for k = 1:numel(cutoff_factors)
                idx = idx + 1;
                candidates(idx).method = "hamming_sinc";
                candidates(idx).opts = struct("cutoff_hz", cutoff_factors(k) * mode.rbw_hz);
                candidates(idx).label = sprintf("hamming_sinc cutoff=%.4gxRBW", cutoff_factors(k));
            end

            if rbw_enbw_lib.has_signal_toolbox()
                kaiser_cutoffs = rbw_enbw_lib.kaiser_cutoff_factors_for_mode(mode);
                betas = rbw_enbw_lib.kaiser_betas_for_mode(mode);
                for b = 1:numel(betas)
                    for k = 1:numel(kaiser_cutoffs)
                        idx = idx + 1;
                        candidates(idx).method = "kaiser";
                        candidates(idx).opts = struct( ...
                            "cutoff_hz", kaiser_cutoffs(k) * mode.rbw_hz, ...
                            "kaiser_beta", betas(b));
                        candidates(idx).label = sprintf("kaiser cutoff=%.4gxRBW beta=%.1f", ...
                            kaiser_cutoffs(k), betas(b));
                    end
                end
            end

            if rbw_enbw_lib.has_equiripple()
                pass_edges = [0.38, 0.42, 0.50, 0.60, 0.70];
                stop_edges = [1.15, 1.50, 2.00, 2.60, 3.00];
                weights = [30, 100, 300];
                for p = 1:numel(pass_edges)
                    for s = 1:numel(stop_edges)
                        if stop_edges(s) <= pass_edges(p)
                            continue;
                        end
                        for w = 1:numel(weights)
                            idx = idx + 1;
                            candidates(idx).method = "equiripple";
                            candidates(idx).opts = struct( ...
                                "passband_hz", pass_edges(p) * mode.rbw_hz, ...
                                "stopband_hz", stop_edges(s) * mode.rbw_hz, ...
                                "stop_weight", weights(w));
                            candidates(idx).label = sprintf("equiripple pass=%.3gx stop=%.3gx w=%.0f", ...
                                pass_edges(p), stop_edges(s), weights(w));
                        end
                    end
                end
            end
        end

        function factors = cutoff_factors_for_mode(mode)
            if strcmp(mode.name, "1K") && mode.fs_out_hz >= 50.0 * mode.rbw_hz
                factors = unique([linspace(0.42, 0.78, 37), linspace(0.80, 1.25, 19), 1.0]);
            elseif strcmp(mode.name, "1M")
                factors = unique([linspace(0.42, 0.78, 37), linspace(0.80, 1.05, 11), 1.0]);
            else
                factors = unique([linspace(0.36, 0.78, 43), 1.0]);
            end
        end

        function factors = kaiser_cutoff_factors_for_mode(mode)
            if strcmp(mode.name, "1K") && mode.fs_out_hz >= 50.0 * mode.rbw_hz
                factors = unique([linspace(0.42, 0.84, 22), linspace(0.86, 1.30, 12), 1.0]);
            elseif strcmp(mode.name, "1M")
                factors = unique([linspace(0.46, 0.86, 21), linspace(0.88, 1.08, 6), 1.0]);
            else
                factors = linspace(0.36, 0.80, 23);
            end
        end

        function betas = kaiser_betas_for_mode(mode)
            if strcmp(mode.name, "1K") && mode.fs_out_hz >= 50.0 * mode.rbw_hz
                betas = [3.0, 4.0, 5.0, 6.5, 8.0, 9.5, 11.0];
            elseif strcmp(mode.name, "1M")
                betas = [3.0, 4.0, 5.0, 6.5, 8.0, 9.5, 11.0];
            else
                betas = [5.0, 7.0, 9.0, 11.0];
            end
        end

        function rows = search_candidates(profile, mode)
            options = rbw_enbw_lib.candidate_option_grid(mode);
            rows = struct([]);
            out_idx = 0;
            for idx = 1:numel(options)
                try
                    coeffs = rbw_enbw_lib.design_fir(mode, options(idx).method, options(idx).opts);
                    row = rbw_enbw_lib.analyze_coeffs(profile, mode, options(idx).method, ...
                        options(idx).label, coeffs, options(idx).opts, 6001, false);
                catch err
                    warning("Skipping %s %s: %s", mode.name, options(idx).label, err.message);
                    continue;
                end
                out_idx = out_idx + 1;
                if isempty(rows)
                    rows = row;
                else
                    rows(out_idx) = row; %#ok<AGROW>
                end
            end
        end

        function [best_row, best_coeffs] = select_best_candidate(profile, mode)
            rows = rbw_enbw_lib.search_candidates(profile, mode);
            if isempty(rows)
                error("No candidates generated for %s %s.", profile, mode.name);
            end

            scores = zeros(1, numel(rows));
            for idx = 1:numel(rows)
                r = rows(idx);
                enbw_penalty = abs(r.enbw_main_over_rbw - 1.0) * 1000.0;
                flat_penalty = max(0.0, r.passband_flatness_db - 0.2) * 40.0;
                stop2_penalty = max(0.0, r.att_2_x_rbw_db + 60.0) * 2.0;
                stop5_penalty = max(0.0, r.att_5_x_rbw_db + 80.0) * 1.0;
                pass_bonus = 0.0;
                if rbw_enbw_lib.meets_filter_targets(r)
                    pass_bonus = -1000.0;
                end
                scores(idx) = pass_bonus + enbw_penalty + flat_penalty + stop2_penalty + stop5_penalty;
            end

            [~, best_idx] = min(scores);
            coarse = rows(best_idx);
            best_coeffs = rbw_enbw_lib.design_fir(mode, coarse.design_method, coarse.design_opts);
            best_row = rbw_enbw_lib.analyze_coeffs(profile, mode, coarse.design_method, ...
                coarse.candidate_label, best_coeffs, coarse.design_opts, 60001, true);
        end

        function [best_row, best_coeffs, candidate_rows] = select_best_candidate_for_taps(profile, base_mode, taps)
            mode = base_mode;
            mode.fir_taps = taps;
            candidate_rows = rbw_enbw_lib.search_candidates(profile, mode);
            if isempty(candidate_rows)
                error("No tap-sweep candidates generated for %s %s %d taps.", ...
                    profile, mode.name, taps);
            end

            scores = zeros(1, numel(candidate_rows));
            for idx = 1:numel(candidate_rows)
                r = candidate_rows(idx);
                enbw_penalty = abs(r.enbw_main_over_rbw - 1.0) * 1000.0;
                flat_penalty = max(0.0, r.passband_flatness_db - 0.2) * 80.0;
                stop2_penalty = max(0.0, r.att_2_x_rbw_db + 60.0) * 4.0;
                stop5_penalty = max(0.0, r.att_5_x_rbw_db + 80.0) * 2.0;
                pass_bonus = 0.0;
                if rbw_enbw_lib.meets_filter_targets(r)
                    pass_bonus = -1000.0;
                end
                scores(idx) = pass_bonus + enbw_penalty + flat_penalty + stop2_penalty + stop5_penalty;
            end

            [~, best_idx] = min(scores);
            coarse = candidate_rows(best_idx);
            best_coeffs = rbw_enbw_lib.design_fir(mode, coarse.design_method, coarse.design_opts);
            best_row = rbw_enbw_lib.analyze_coeffs(profile, mode, coarse.design_method, ...
                coarse.candidate_label, best_coeffs, coarse.design_opts, 60001, true);
        end

        function row = add_engineering_constraints(row, base_taps, accum_buffer_size)
            accum_target = row.observe_points + row.skip_points + row.fir_taps;
            first_valid = row.fir_taps - 1 + row.skip_points;
            out_len = accum_target - first_valid;
            required_buffer = max(accum_buffer_size, accum_target);
            base_out_len = row.observe_points + 1;
            base_ops = base_taps * base_out_len;
            ops = row.fir_taps * out_len;

            row.accum_buffer_size = accum_buffer_size;
            row.accum_target = accum_target;
            row.first_valid = first_valid;
            row.out_len = out_len;
            row.fits_accum_buffer = accum_target <= accum_buffer_size;
            row.required_accum_buffer_size = required_buffer;
            row.fir_ops_per_window = ops;
            row.fir_ops_relative = ops / base_ops;
            row.accum_count_relative = accum_target / (row.observe_points + row.skip_points + base_taps);
            row.accum_time_ms = 1000.0 * accum_target / row.fs_out_hz;
            row.valid_window_ms = 1000.0 * out_len / row.fs_out_hz;
            row.output_sample_period_us = 1e6 / row.fs_out_hz;
        end

        function tf = meets_filter_targets(row)
            tf = row.enbw_main_over_rbw >= 0.95 && row.enbw_main_over_rbw <= 1.05 && ...
                row.passband_flatness_db <= 0.2 && ...
                row.att_2_x_rbw_db <= -60.0 && ...
                row.att_5_x_rbw_db <= -80.0;
        end

        function status = classify_candidate(row)
            if row.alias_geometry_risk
                status = "NEEDS_DECIMATION_REWORK";
                return;
            end
            if rbw_enbw_lib.meets_filter_targets(row)
                status = "PASS";
            elseif row.enbw_main_over_rbw >= 0.95 && row.enbw_main_over_rbw <= 1.05
                status = "NEEDS_TAPS";
            else
                status = "FAIL";
            end
        end

        function alias_hz = alias_to_output(freq_hz, fs_out_hz)
            alias_hz = mod(freq_hz + fs_out_hz / 2.0, fs_out_hz) - fs_out_hz / 2.0;
        end

        function mag = cic_mag(freq_hz, mode)
            f = double(freq_hz);
            numerator = sin(pi .* f .* mode.cic_r ./ mode.adc_fs_hz);
            denominator = mode.cic_r .* sin(pi .* f ./ mode.adc_fs_hz);
            mag = ones(size(f));
            mask = abs(denominator) > 1e-30;
            mag(mask) = abs(numerator(mask) ./ denominator(mask)) .^ mode.cic_n;
        end

        function mag = fir_mag_at(freq_hz, coeffs, fs_out_hz)
            input_size = size(freq_hz);
            freq = double(freq_hz(:));

            if exist("freqz", "file") && numel(freq) > 1
                omega = 2.0 * pi .* freq ./ fs_out_hz;
                mag = abs(freqz(coeffs, 1, omega));
                mag = reshape(mag, input_size);
                return;
            end

            n = 0:(numel(coeffs) - 1);
            mag = zeros(size(freq));
            chunk = 2048;
            for start_idx = 1:chunk:numel(freq)
                stop_idx = min(start_idx + chunk - 1, numel(freq));
                phase = -2j * pi .* freq(start_idx:stop_idx) ./ fs_out_hz .* n;
                mag(start_idx:stop_idx) = abs(exp(phase) * coeffs(:));
            end
            mag = reshape(mag, input_size);
        end

        function mag = total_mag(freq_hz, mode, coeffs)
            alias = rbw_enbw_lib.alias_to_output(freq_hz, mode.fs_out_hz);
            mag = rbw_enbw_lib.cic_mag(freq_hz, mode) .* ...
                rbw_enbw_lib.fir_mag_at(alias, coeffs, mode.fs_out_hz);
        end

        function val_db = db20(mag)
            val_db = 20.0 .* log10(max(abs(mag), 1e-300));
        end

        function bw_hz = find_bandwidth(freq_hz, mag, db_down)
            target = 10.0 ^ (-db_down / 20.0);
            idx = find(mag <= target, 1, "first");
            if isempty(idx)
                bw_hz = NaN;
                return;
            end
            if idx == 1
                bw_hz = freq_hz(1);
                return;
            end

            x0 = freq_hz(idx - 1);
            x1 = freq_hz(idx);
            y0 = mag(idx - 1);
            y1 = mag(idx);
            if y1 == y0
                bw_hz = x1;
            else
                bw_hz = x0 + (target - y0) * (x1 - x0) / (y1 - y0);
            end
        end

        function enbw_hz = enbw_main(mode, coeffs, n_points)
            if nargin < 3
                n_points = 60001;
            end
            f = linspace(-mode.fs_out_hz / 2.0, mode.fs_out_hz / 2.0, n_points);
            mag = rbw_enbw_lib.total_mag(f, mode, coeffs);
            enbw_hz = trapz(f, mag .^ 2);
        end

        function enbw_hz = enbw_full_adc(mode, coeffs, n_points)
            if nargin < 3
                n_points = 120001;
            end
            f = linspace(-mode.adc_fs_hz / 2.0, mode.adc_fs_hz / 2.0, n_points);
            alias = rbw_enbw_lib.alias_to_output(f, mode.fs_out_hz);
            grid = linspace(0.0, mode.fs_out_hz / 2.0, 20001);
            fir_grid = rbw_enbw_lib.fir_mag_at(grid, coeffs, mode.fs_out_hz);
            fir_response = interp1(grid, fir_grid, abs(alias), "linear", "extrap");
            mag = rbw_enbw_lib.cic_mag(f, mode) .* fir_response;
            enbw_hz = trapz(f, mag .^ 2);
        end

        function row = analyze_mode(mode, method)
            coeffs = rbw_enbw_lib.design_fir(mode, method, struct());
            row = rbw_enbw_lib.analyze_coeffs("", mode, method, string(method), coeffs, struct(), 60001, true);
        end

        function row = analyze_coeffs(profile, mode, method, label, coeffs, opts, enbw_points, include_full_adc)
            if nargin < 7
                enbw_points = 60001;
            end
            if nargin < 8
                include_full_adc = true;
            end
            f = linspace(0.0, 12.0 * mode.rbw_hz, 6001);
            mag = rbw_enbw_lib.total_mag(f, mode, coeffs);

            row = struct();
            row.profile = string(profile);
            row.mode = string(mode.name);
            row.design_method = string(method);
            row.candidate_label = string(label);
            row.rbw_hz = mode.rbw_hz;
            row.cic_r = mode.cic_r;
            row.cic_n = mode.cic_n;
            row.fs_out_hz = mode.fs_out_hz;
            row.fir_taps = mode.fir_taps;
            row.observe_points = mode.observe_points;
            row.skip_points = mode.skip_points;
            row.fir_cutoff_norm = rbw_enbw_lib.option_value(opts, "cutoff_hz", mode.rbw_hz) / mode.fs_out_hz;
            row.design_opts_json = rbw_enbw_lib.opts_to_string(opts);
            row.design_opts = opts;
            row.bw_3db_hz = rbw_enbw_lib.find_bandwidth(f, mag, 3.01029995664);
            row.bw_6db_hz = rbw_enbw_lib.find_bandwidth(f, mag, 6.0);
            row.enbw_main_hz = rbw_enbw_lib.enbw_main(mode, coeffs, enbw_points);
            if include_full_adc
                row.enbw_full_adc_hz = rbw_enbw_lib.enbw_full_adc(mode, coeffs);
            else
                row.enbw_full_adc_hz = NaN;
            end
            row.enbw_main_over_rbw = row.enbw_main_hz / mode.rbw_hz;
            row.enbw_full_over_rbw = row.enbw_full_adc_hz / mode.rbw_hz;
            row.enbw_error_pct = 100.0 * (row.enbw_main_over_rbw - 1.0);
            row.noise_correction_db = 10.0 * log10(row.enbw_main_over_rbw);

            passband_f = linspace(0.0, 0.4 * mode.rbw_hz, 801);
            passband_db = rbw_enbw_lib.db20(rbw_enbw_lib.total_mag(passband_f, mode, coeffs));
            row.passband_flatness_db = max(abs(passband_db - passband_db(1)));

            factors = [0.5, 1, 2, 5, 10];
            for k = 1:numel(factors)
                field_name = sprintf("att_%s_x_rbw_db", strrep(num2str(factors(k)), ".", "p"));
                row.(field_name) = rbw_enbw_lib.db20( ...
                    rbw_enbw_lib.total_mag(factors(k) * mode.rbw_hz, mode, coeffs));
            end

            alias_offsets = [1e3, 3e3, 10e3, 10.2e3, 14e3, 100e3];
            for k = 1:numel(alias_offsets)
                tag = rbw_enbw_lib.freq_tag(alias_offsets(k));
                alias_hz = abs(rbw_enbw_lib.alias_to_output(alias_offsets(k), mode.fs_out_hz));
                row.(sprintf("alias_%s_hz", tag)) = alias_hz;
                row.(sprintf("alias_%s_db", tag)) = rbw_enbw_lib.db20( ...
                    rbw_enbw_lib.total_mag(alias_offsets(k), mode, coeffs));
            end
            row.alias_geometry_risk = strcmp(mode.name, "1K") && ...
                (abs(rbw_enbw_lib.alias_to_output(10e3, mode.fs_out_hz)) <= 0.4 * mode.rbw_hz || ...
                 abs(rbw_enbw_lib.alias_to_output(10.2e3, mode.fs_out_hz)) <= 0.4 * mode.rbw_hz || ...
                 mode.fs_out_hz < 20.0 * mode.rbw_hz);
            row.status = rbw_enbw_lib.classify_candidate(row);
            row.recommendation = rbw_enbw_lib.recommendation(row);
        end

        function val = option_value(opts, field_name, default_value)
            if isfield(opts, field_name)
                val = opts.(field_name);
            else
                val = default_value;
            end
        end

        function txt = opts_to_string(opts)
            fields = fieldnames(opts);
            if isempty(fields)
                txt = "";
                return;
            end
            parts = strings(1, numel(fields));
            for idx = 1:numel(fields)
                val = opts.(fields{idx});
                if isnumeric(val)
                    val_txt = sprintf("%.12g", val);
                else
                    val_txt = string(val);
                end
                parts(idx) = sprintf("%s=%s", fields{idx}, val_txt);
            end
            txt = strjoin(parts, ";");
        end

        function tag = freq_tag(freq_hz)
            if abs(freq_hz - round(freq_hz)) < 1e-9
                tag = sprintf("%dhz", round(freq_hz));
            else
                tag = strrep(sprintf("%.1fhz", freq_hz), ".", "p");
            end
        end

        function txt = recommendation(row)
            if row.status == "PASS"
                txt = "Use this candidate for Step 2 freeze after coefficient quantization check.";
            elseif row.status == "NEEDS_DECIMATION_REWORK"
                txt = "Revise CIC decimation geometry before freezing coefficients; 1 kHz offset aliases into the passband-risk region.";
            elseif row.status == "NEEDS_TAPS"
                txt = "Increase FIR taps or broaden method sweep; current tap budget is close but misses rejection/flatness targets.";
            else
                txt = "No acceptable candidate found under this tap/decimation budget; revisit taps, decimation, or explicit ENBW correction.";
            end
        end

        function write_metrics_markdown(path, rows)
            fid = fopen(path, "w");
            if fid < 0
                error("Unable to open %s for writing", path);
            end
            cleaner = onCleanup(@() fclose(fid));

            fprintf(fid, "# RBW ENBW MATLAB Metrics\n\n");
            fprintf(fid, "Generated by `docs/rbw_filter_analysis/matlab/run_rbw_enbw_design.m`.\n\n");
            fprintf(fid, "| Mode | Fs out | Taps | -3 dB BW | -6 dB BW | ENBW | ENBW/RBW | Error | Correction | 0.5x | 1x | 2x | 5x | 10x |\n");
            fprintf(fid, "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n");
            for idx = 1:numel(rows)
                r = rows(idx);
                fprintf(fid, "| %s | %.1f | %d | %.1f | %.1f | %.1f | %.3f | %+0.1f%% | %+0.2f dB | %.2f dB | %.2f dB | %.2f dB | %.2f dB | %.2f dB |\n", ...
                    r.mode, r.fs_out_hz, r.fir_taps, r.bw_3db_hz, r.bw_6db_hz, ...
                    r.enbw_main_hz, r.enbw_main_over_rbw, r.enbw_error_pct, ...
                    r.noise_correction_db, r.att_0p5_x_rbw_db, r.att_1_x_rbw_db, ...
                    r.att_2_x_rbw_db, r.att_5_x_rbw_db, r.att_10_x_rbw_db);
            end
        end

        function write_candidate_metrics_markdown(path, selection_rows, metrics_tbl)
            fid = fopen(path, "w");
            if fid < 0
                error("Unable to open %s for writing", path);
            end
            cleaner = onCleanup(@() fclose(fid));

            fprintf(fid, "# RBW Candidate Metrics\n\n");
            fprintf(fid, "Generated by `docs/rbw_filter_analysis/matlab/run_rbw_enbw_design.m`.\n\n");
            fprintf(fid, "- Candidate rows evaluated: %d\n", height(metrics_tbl));
            fprintf(fid, "- Hamming-sinc cutoff sweep is always included.\n");
            fprintf(fid, "- Kaiser/equiripple candidates are included only when MATLAB toolbox functions are available.\n\n");
            if ~rbw_enbw_lib.has_equiripple()
                fprintf(fid, "> Note: Equiripple was not evaluated in this MATLAB install because `firpm` is not callable as a function.\n\n");
            end
            fprintf(fid, "## Selected Candidate Summary\n\n");
            fprintf(fid, "| Profile | Mode | Status | Method | ENBW/RBW | Flatness | 2x RBW | 5x RBW | 10 kHz alias | 10.2 kHz alias |\n");
            fprintf(fid, "| --- | ---: | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |\n");
            for idx = 1:numel(selection_rows)
                r = selection_rows(idx);
                fprintf(fid, "| %s | %s | %s | %s | %.4f | %.3f dB | %.2f dB | %.2f dB | %.1f Hz / %.2f dB | %.1f Hz / %.2f dB |\n", ...
                    r.profile, r.mode, r.status, r.design_method, r.enbw_main_over_rbw, ...
                    r.passband_flatness_db, r.att_2_x_rbw_db, r.att_5_x_rbw_db, ...
                    r.alias_10000hz_hz, r.alias_10000hz_db, ...
                    r.alias_10200hz_hz, r.alias_10200hz_db);
            end
        end

        function write_candidate_selection_markdown(path, rows)
            fid = fopen(path, "w");
            if fid < 0
                error("Unable to open %s for writing", path);
            end
            cleaner = onCleanup(@() fclose(fid));

            fprintf(fid, "# RBW Candidate Selection\n\n");
            fprintf(fid, "Step 1 selects one first-version candidate per profile and mode. ");
            fprintf(fid, "Status meanings: `PASS`, `NEEDS_TAPS`, `NEEDS_DECIMATION_REWORK`, or `FAIL`.\n\n");
            fprintf(fid, "| Profile | Mode | Status | Method/options | Fs out | Taps | ENBW | ENBW/RBW | Correction | Flatness | 2x | 5x | Alias check | Recommendation |\n");
            fprintf(fid, "| --- | ---: | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |\n");
            for idx = 1:numel(rows)
                r = rows(idx);
                alias_txt = sprintf("10k->%.1f Hz %.1f dB; 10.2k->%.1f Hz %.1f dB", ...
                    r.alias_10000hz_hz, r.alias_10000hz_db, ...
                    r.alias_10200hz_hz, r.alias_10200hz_db);
                method_txt = sprintf("%s `%s`", r.design_method, r.design_opts_json);
                fprintf(fid, "| %s | %s | %s | %s | %.1f | %d | %.2f | %.4f | %+0.2f dB | %.3f dB | %.2f dB | %.2f dB | %s | %s |\n", ...
                    r.profile, r.mode, r.status, method_txt, r.fs_out_hz, r.fir_taps, ...
                    r.enbw_main_hz, r.enbw_main_over_rbw, r.noise_correction_db, ...
                    r.passband_flatness_db, r.att_2_x_rbw_db, r.att_5_x_rbw_db, ...
                    alias_txt, r.recommendation);
            end

            fprintf(fid, "\n## Notes\n\n");
            fprintf(fid, "- `firmware_current` keeps the current CIC decimation ratios.\n");
            fprintf(fid, "- `alias_rework_1k` changes only 1 kHz RBW to `R=1300`, giving `Fs_out=100 kHz`.\n");
            if ~rbw_enbw_lib.has_equiripple()
                fprintf(fid, "- Equiripple was skipped because this MATLAB install exposes `firpm.m` as a non-callable script; Hamming-sinc and Kaiser sweeps were evaluated.\n");
            end
            fprintf(fid, "- `NEEDS_DECIMATION_REWORK` is assigned before filter quality when the 1 kHz 10 kHz/10.2 kHz alias geometry folds into the passband-risk region.\n");
        end

        function write_tap_sweep_markdown(path, rows)
            fid = fopen(path, "w");
            if fid < 0
                error("Unable to open %s for writing", path);
            end
            cleaner = onCleanup(@() fclose(fid));

            fprintf(fid, "# RBW Candidate Tap Sweep\n\n");
            fprintf(fid, "Generated by `docs/rbw_filter_analysis/matlab/run_rbw_tap_sweep.m`.\n\n");
            fprintf(fid, "This Step 1c sweep targets only the previously unresolved modes: ");
            fprintf(fid, "`alias_rework_1k / 1K` and `1M` under both profiles. ");
            fprintf(fid, "Engineering checks use `ACCUM_BUFFER_SIZE=768`.\n\n");
            if ~rbw_enbw_lib.has_equiripple()
                fprintf(fid, "> Note: Equiripple was not evaluated because this MATLAB install exposes `firpm.m` as a non-callable script. Hamming-sinc and Kaiser sweeps were evaluated.\n\n");
            end

            fprintf(fid, "## Recommendation\n\n");
            keys = rbw_enbw_lib.unique_mode_keys(rows);
            fprintf(fid, "| Case | Recommendation | Min PASS taps | Buffer impact | Compute impact | Notes |\n");
            fprintf(fid, "| --- | --- | ---: | --- | --- | --- |\n");
            for k = 1:numel(keys)
                key = keys(k);
                case_rows = rbw_enbw_lib.rows_for_key(rows, key);
                pass_rows = case_rows([case_rows.status] == "PASS" & [case_rows.fits_accum_buffer]);
                any_pass_rows = case_rows([case_rows.status] == "PASS");
                if ~isempty(pass_rows)
                    [~, pick_idx] = min([pass_rows.fir_taps]);
                    pick = pass_rows(pick_idx);
                    rec = "PASS";
                    min_taps_txt = sprintf("%d", pick.fir_taps);
                    buffer_txt = sprintf("fits 768, accum_target=%d", pick.accum_target);
                    compute_txt = sprintf("%.2fx current", pick.fir_ops_relative);
                    notes = sprintf("%s %s ENBW/RBW %.4f flat %.3f dB", ...
                        pick.profile, pick.mode, pick.enbw_main_over_rbw, pick.passband_flatness_db);
                elseif ~isempty(any_pass_rows)
                    [~, pick_idx] = min([any_pass_rows.fir_taps]);
                    pick = any_pass_rows(pick_idx);
                    rec = "NEEDS_BUFFER";
                    min_taps_txt = sprintf("%d", pick.fir_taps);
                    buffer_txt = sprintf("needs >=%d", pick.required_accum_buffer_size);
                    compute_txt = sprintf("%.2fx current", pick.fir_ops_relative);
                    notes = sprintf("Filter passes but accum_target=%d exceeds 768.", pick.accum_target);
                else
                    [~, pick_idx] = min(abs([case_rows.enbw_main_over_rbw] - 1.0) + ...
                        max(0, [case_rows.passband_flatness_db] - 0.2));
                    pick = case_rows(pick_idx);
                    rec = "NEEDS_ALGORITHM";
                    min_taps_txt = "n/a";
                    buffer_txt = sprintf("best tested accum_target=%d", pick.accum_target);
                    compute_txt = sprintf("best tested %.2fx current", pick.fir_ops_relative);
                    notes = sprintf("No tested taps met filter targets; best %d taps %s ENBW/RBW %.4f flat %.3f dB.", ...
                        pick.fir_taps, pick.design_method, pick.enbw_main_over_rbw, pick.passband_flatness_db);
                end
                fprintf(fid, "| %s | %s | %s | %s | %s | %s |\n", ...
                    key, rec, min_taps_txt, buffer_txt, compute_txt, notes);
            end

            fprintf(fid, "\n## Per-Tap Best Candidates\n\n");
            fprintf(fid, "| Profile | Mode | Taps | Status | Method/options | ENBW/RBW | Corr | -3 dB | -6 dB | Flat | 2x | 5x | 10x | 10 kHz alias | 10.2 kHz alias | Accum target | First valid | Out len | Fits 768 | Required buffer | FIR ops rel | Accum time |\n");
            fprintf(fid, "| --- | ---: | ---: | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: |\n");
            for idx = 1:numel(rows)
                r = rows(idx);
                method_txt = sprintf("%s `%s`", r.design_method, r.design_opts_json);
                fits_txt = rbw_enbw_lib.bool_text(r.fits_accum_buffer);
                fprintf(fid, "| %s | %s | %d | %s | %s | %.4f | %+0.2f dB | %.1f | %.1f | %.3f dB | %.2f dB | %.2f dB | %.2f dB | %.1f Hz / %.1f dB | %.1f Hz / %.1f dB | %d | %d | %d | %s | %d | %.2f | %.3f ms |\n", ...
                    r.profile, r.mode, r.fir_taps, r.status, method_txt, ...
                    r.enbw_main_over_rbw, r.noise_correction_db, r.bw_3db_hz, r.bw_6db_hz, ...
                    r.passband_flatness_db, r.att_2_x_rbw_db, r.att_5_x_rbw_db, r.att_10_x_rbw_db, ...
                    r.alias_10000hz_hz, r.alias_10000hz_db, ...
                    r.alias_10200hz_hz, r.alias_10200hz_db, ...
                    r.accum_target, r.first_valid, r.out_len, fits_txt, ...
                    r.required_accum_buffer_size, r.fir_ops_relative, r.accum_time_ms);
            end

            fprintf(fid, "\n## Engineering Notes\n\n");
            fprintf(fid, "- `accum_target = observe + skip + taps`.\n");
            fprintf(fid, "- `first_valid = taps - 1 + skip`.\n");
            fprintf(fid, "- `out_len = accum_target - first_valid`, which equals `observe + 1` with this windowing model.\n");
            fprintf(fid, "- 1 kHz `alias_rework_1k` uses `R=1300`, so `Fs_out=100 kHz`, sample period is 10 us, and the same sample count covers one tenth of the old `R=13000` time span. It avoids the 10 kHz/10.2 kHz passband-folding geometry, but increases post-CIC sample rate and FIR work per second by 10x before tap-count changes.\n");
        end

        function keys = unique_mode_keys(rows)
            keys = strings(1, numel(rows));
            for idx = 1:numel(rows)
                keys(idx) = sprintf("%s/%s", rows(idx).profile, rows(idx).mode);
            end
            keys = unique(keys, "stable");
        end

        function selected = rows_for_key(rows, key)
            mask = false(1, numel(rows));
            for idx = 1:numel(rows)
                mask(idx) = sprintf("%s/%s", rows(idx).profile, rows(idx).mode) == key;
            end
            selected = rows(mask);
        end

        function txt = bool_text(value)
            if value
                txt = "yes";
            else
                txt = "no";
            end
        end
    end
end

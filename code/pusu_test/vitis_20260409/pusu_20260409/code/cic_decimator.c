#include "../code/cic_decimator.h"

#include <math.h>
#include <string.h>

#define CIC_MAX_STAGES 5

static double cic_integ_i[CIC_MAX_STAGES];
static double cic_integ_q[CIC_MAX_STAGES];
static double cic_comb_prev_i[CIC_MAX_STAGES];
static double cic_comb_prev_q[CIC_MAX_STAGES];
static double cic_gain;
static int cic_stages;
static int cic_decim_ratio;
static int cic_decim_count;
static int cic_output_count;

void cic_decimator_init(int stages, int decim_ratio)
{
    int j;

    cic_stages      = stages;
    cic_decim_ratio = decim_ratio;
    cic_decim_count = 0;
    cic_output_count = 0;

    for (j = 0; j < CIC_MAX_STAGES; j++) {
        cic_integ_i[j]     = 0.0;
        cic_integ_q[j]     = 0.0;
        cic_comb_prev_i[j] = 0.0;
        cic_comb_prev_q[j] = 0.0;
    }

    cic_gain = pow((double)decim_ratio, (double)stages);
}

int cic_decimator_process(const float *i_in, const float *q_in,
                          int in_len, float *i_out, float *q_out,
                          int out_capacity)
{
    int i, j;
    int produced = 0;

    for (i = 0; i < in_len; i++) {
        double i_val = (double)i_in[i];
        double q_val = (double)q_in[i];

        for (j = 0; j < cic_stages; j++) {
            cic_integ_i[j] += i_val;
            i_val = cic_integ_i[j];
            cic_integ_q[j] += q_val;
            q_val = cic_integ_q[j];
        }

        cic_decim_count++;
        if (cic_decim_count >= cic_decim_ratio) {
            double comb_i = i_val;
            double comb_q = q_val;

            cic_decim_count = 0;

            for (j = 0; j < cic_stages; j++) {
                double diff_i = comb_i - cic_comb_prev_i[j];
                double diff_q = comb_q - cic_comb_prev_q[j];

                cic_comb_prev_i[j] = comb_i;
                cic_comb_prev_q[j] = comb_q;
                comb_i = diff_i;
                comb_q = diff_q;
            }

            if (produced < out_capacity) {
                i_out[produced] = (float)(comb_i / cic_gain);
                q_out[produced] = (float)(comb_q / cic_gain);
                produced++;
            }
        }
    }

    cic_output_count += produced;
    return produced;
}

void cic_decimator_reset(void)
{
    int j;

    cic_decim_count  = 0;
    cic_output_count = 0;

    for (j = 0; j < CIC_MAX_STAGES; j++) {
        cic_integ_i[j]     = 0.0;
        cic_integ_q[j]     = 0.0;
        cic_comb_prev_i[j] = 0.0;
        cic_comb_prev_q[j] = 0.0;
    }
}

int cic_decimator_output_available(void)
{
    return cic_output_count;
}

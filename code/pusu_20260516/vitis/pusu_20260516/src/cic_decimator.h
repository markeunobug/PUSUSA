#ifndef CIC_DECIMATOR_H
#define CIC_DECIMATOR_H

void cic_decimator_init(int stages, int decim_ratio);
int  cic_decimator_process(const float *i_in, const float *q_in,
                           int in_len, float *i_out, float *q_out,
                           int out_capacity);
void cic_decimator_reset(void);
int  cic_decimator_output_available(void);

#endif

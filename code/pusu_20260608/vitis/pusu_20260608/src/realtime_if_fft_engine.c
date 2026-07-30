#include "realtime_if_fft_engine.h"
#include <string.h>
#include "xstatus.h"
#include "dma_capture.h"
#include "lo_control.h"

#define RTFFT_FRAME_TIMEOUT_LOOPS 500000U

static void emit_status(realtime_if_fft_engine_t *e) { realtime_if_fft_engine_status_t s; realtime_if_fft_engine_get_status(e,&s); if(e->status_callback) (void)e->status_callback(&s,e->status_context); }
static void fail(realtime_if_fft_engine_t *e, realtime_if_fft_engine_error_t err)
{
    int reset_status = dma_capture_reset();
    e->last_error = (reset_status == XST_SUCCESS) ? err : RTFFT_ERR_DMA_RESET;
    if ((err == RTFFT_ERR_DMA) || (err == RTFFT_ERR_FRAME_TIMEOUT) ||
        (reset_status != XST_SUCCESS)) e->dma_error_count++;
    e->state = RTFFT_STATE_ERROR;
    emit_status(e);
}
int realtime_if_fft_engine_init(realtime_if_fft_engine_t *e) { if(!e)return -1; memset(e,0,sizeof(*e)); e->state=RTFFT_STATE_IDLE; e->next_trace_id=1U; return 0; }
int realtime_if_fft_engine_configure(realtime_if_fft_engine_t *e,const realtime_if_fft_engine_config_t *c) { if(!e||!c||c->version!=REALTIME_IF_FFT_ENGINE_VERSION||c->center_frequency_hz<REALTIME_IF_FFT_CENTER_MIN_HZ||c->center_frequency_hz>REALTIME_IF_FFT_CENTER_MAX_HZ||realtime_if_fft_engine_is_active(e)){ if(e)e->last_error=RTFFT_ERR_BAD_CONFIG; return -1;} e->config=*c;e->configured=1U;e->last_error=RTFFT_ERR_NONE;e->state=RTFFT_STATE_CONFIGURED;return 0; }
int realtime_if_fft_engine_start(realtime_if_fft_engine_t *e) { if(!e||realtime_if_fft_engine_is_active(e)){if(e)e->last_error=RTFFT_ERR_BUSY;return -1;} if(!e->configured){e->last_error=RTFFT_ERR_NOT_CONFIGURED;return -1;} e->stop_requested=0;e->wait_counter=0;e->last_error=RTFFT_ERR_NONE;e->state=RTFFT_STATE_SET_LO;return 0; }
void realtime_if_fft_engine_stop(realtime_if_fft_engine_t *e){if(e&&realtime_if_fft_engine_is_active(e))e->stop_requested=1U;}
int realtime_if_fft_engine_is_active(const realtime_if_fft_engine_t *e){return e&&(e->state==RTFFT_STATE_SET_LO||e->state==RTFFT_STATE_WAIT_LOCK||e->state==RTFFT_STATE_ARM_DMA||e->state==RTFFT_STATE_WAIT_FRAME);}
void realtime_if_fft_engine_get_status(const realtime_if_fft_engine_t *e,realtime_if_fft_engine_status_t *s){if(!e||!s)return;memset(s,0,sizeof(*s));s->version=REALTIME_IF_FFT_ENGINE_VERSION;s->state=(uint8_t)e->state;s->flags=(e->configured?1U:0U)|(realtime_if_fft_engine_is_active(e)?2U:0U);s->error_code=(uint8_t)e->last_error;s->next_trace_id=e->next_trace_id;s->frames_sent=e->frames_sent;s->dropped_frames=e->dropped_frames;s->dma_error_count=e->dma_error_count;s->center_frequency_hz=e->config.center_frequency_hz;}
void realtime_if_fft_engine_set_callbacks(realtime_if_fft_engine_t *e,realtime_if_fft_engine_trace_callback_t t,void *tc,realtime_if_fft_engine_status_callback_t s,void *sc){if(!e)return;e->trace_callback=t;e->trace_context=tc;e->status_callback=s;e->status_context=sc;}
int realtime_if_fft_engine_poll(realtime_if_fft_engine_t *e){ realtime_if_fft_config_t c; realtime_if_fft_trace_t trace; realtime_if_fft_engine_status_t status; if(!e)return -1; if(e->stop_requested){
        int reset_status=dma_capture_reset();
        e->stop_requested=0;
        e->last_error=(reset_status==XST_SUCCESS)?RTFFT_ERR_STOPPED:RTFFT_ERR_DMA_RESET;
        if(reset_status!=XST_SUCCESS) e->dma_error_count++;
        e->state=RTFFT_STATE_IDLE;
        emit_status(e);
        return (reset_status==XST_SUCCESS)?0:-1;
    } switch(e->state){case RTFFT_STATE_SET_LO: if(lo_control_set_lo1_for_rf_hz(e->config.center_frequency_hz)!=XST_SUCCESS){fail(e,RTFFT_ERR_LO_SET);return -1;}e->wait_counter=0;e->state=RTFFT_STATE_WAIT_LOCK;return 0;case RTFFT_STATE_WAIT_LOCK:if(lo_control_is_locked(LO_CONTROL_DEVICE_LO1)==XST_SUCCESS){e->state=RTFFT_STATE_ARM_DMA;return 0;}if(++e->wait_counter>=RTFFT_FRAME_TIMEOUT_LOOPS){fail(e,RTFFT_ERR_LO_LOCK);return -1;}return 0;case RTFFT_STATE_ARM_DMA:if(dma_capture_reset()!=XST_SUCCESS||dma_capture_start((u32)(REALTIME_IF_FFT_SIZE*sizeof(uint16_t)))!=XST_SUCCESS){fail(e,RTFFT_ERR_DMA);return -1;}e->wait_counter=0;e->state=RTFFT_STATE_WAIT_FRAME;return 0;case RTFFT_STATE_WAIT_FRAME:if(dma_capture_take_error()!=0){fail(e,RTFFT_ERR_DMA);return -1;}if(dma_capture_frame_ready()!=0){c.center_frequency_hz=e->config.center_frequency_hz;if(realtime_if_fft_process_raw_adc_frame(dma_capture_get_rx_buffer(),&c,e->next_trace_id,&trace)!=0){fail(e,RTFFT_ERR_PROCESS);return -1;}realtime_if_fft_engine_get_status(e,&status);if(e->trace_callback&&e->trace_callback(&trace,&status,e->trace_context)!=0){fail(e,RTFFT_ERR_STREAM);return -1;}e->next_trace_id++;if(!e->next_trace_id)e->next_trace_id=1U;e->frames_sent++;e->state=RTFFT_STATE_ARM_DMA;return 0;}if(++e->wait_counter>=RTFFT_FRAME_TIMEOUT_LOOPS){fail(e,RTFFT_ERR_FRAME_TIMEOUT);return -1;}return 0;default:return 0;} }

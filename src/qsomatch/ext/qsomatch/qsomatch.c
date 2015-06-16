/***************************************************************************
 * Name: qsomatch.c
 * Code to store a QSO and make a probabilistic match.
 */

#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <inttypes.h>
#include <time.h>
#include "ruby.h"
#include "distance.h"

#define MAX_CALLSIGN_CHARS   12
#define MAX_MULTIPLIER_CHARS 20

enum Band_t {
  b_TwoFortyOneG,
  b_OneFortyTwoG,
  b_OneNineteenG,
  b_SeventyFiveG,
  b_FortySevenG,
  b_TwentyFourG,
  b_TenG,
  b_FivePointSevenG,
  b_ThreePointFourG,
  b_TwoPointThreeG,
  b_OnePointTwoG,
  b_NineZeroTwoM,
  b_FourThirtyTwoM,
  b_TwoTwentyTwoM,
  b_TwoM,
  b_SixM,
  b_TenM,
  b_FifteenM,
  b_TwentyM,
  b_FortyM,
  b_EightyM,
  b_OneSixtyM,
  b_Unknown
};

/* order must match ordering of enum above */
static const char * const s_bandNames[] = {
  "241G",
  "142G",
  "119G",
  "75G",
  "47G",
  "24G",
  "10G",
  "5.7G",
  "3.4G",
  "2.3G",
  "1.2G",
  "902",
  "432",
  "222",
  "2m",
  "6m",
  "10m",
  "15m",
  "20m",
  "40m",
  "80m",
  "160m",
  "unknown"
};

struct StringMap_t {
  const char * const d_bandName;
  const int        d_bandNum;
};

static struct StringMap_t s_bandMap[] = {
  { "1.2G", b_OnePointTwoG},
  { "10G",  b_TenG},
  { "10m",  b_TenM},
  { "119G", b_OneNineteenG},
  { "142G", b_OneFortyTwoG},
  { "15m",  b_FifteenM},
  { "160m", b_OneSixtyM},
  { "2.3G", b_TwoPointThreeG},
  { "20m",  b_TwentyM},
  { "222",  b_TwoTwentyTwoM},
  { "241G", b_TwoFortyOneG},
  { "24G",  b_TwentyFourG},
  { "2m",   b_TwoM},
  { "3.4G", b_ThreePointFourG},
  { "40m",  b_FortyM},
  { "432",  b_FourThirtyTwoM},
  { "47G",  b_FortySevenG},
  { "5.7G", b_FivePointSevenG},
  { "6m",   b_SixM},
  { "75G",  b_SeventyFiveG},
  { "80m",  b_EightyM},
  { "902",  b_NineZeroTwoM},
  { "unknown", b_Unknown}
};

enum Mode_t {
  m_Phone,
  m_CW,
  m_FM,
  m_RTTY
};

static
const char * const s_modeNames[] = {
  "PH",
  "CW",
  "FM",
  "RY"
};

static struct StringMap_t s_modeMap[] = {
  { "CW", m_CW },
  { "FM", m_FM },
  { "PH", m_Phone },
  { "RY", m_RTTY }
};

struct Exchange_t {
  int16_t d_serial;			  /* serial number */
  char    d_callsign[MAX_CALLSIGN_CHARS]; /* callsign as logged */
  char    d_basecall[MAX_CALLSIGN_CHARS]; /* callsign with prefix/suffix removed */
  char    d_multiplier[MAX_MULTIPLIER_CHARS]; /* canonical multiplier name */
  char    d_location[MAX_MULTIPLIER_CHARS];   /* multiplier name as logged */
};

struct QSO_t {
  int32_t           d_qsoID;	/* unique number assigned to each QSO */
  int32_t           d_logID;	/* unique number assigned to each LOG */
  int32_t	    d_frequency;/* frequency number as logged */
  enum Band_t       d_band;
  enum Mode_t       d_mode;
  time_t            d_datetime;	/* date and time of QSO as seconds since epoch */
  struct Exchange_t d_sent;
  struct Exchange_t d_recvd;
};

const char * const s_CW_MAPPING[] = {
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  0,
  " ",				/* space */
  "-.-.--",			/* ! exclamation point */
  ".-..-.",			/* " quotation mark */
  0,				/* # hash */
  "...-..-",			/* $ dollar sign */
  0,				/* % percent */
  ".-...",			/* & ampersand */
  0,				/* ' single quote */
  "-.--.",			/* ( open paren */
  "-.--.-",			/* ) close paren */
  0,				/* * asterisk */
  ".-.-.",			/* + plus */
  "--..--",			/* , comma */
  "-....-",			/* - hyphen */
  ".-.-.-",			/* . period */
  "-..-.",			/* / slash */
  "-----",			/* 0 zero */
  ".----",			/* 1 one */
  "..---",			/* 2 two */
  "...--",			/* 3 three */
  "....-",			/* 4 four */
  ".....",			/* 5 five */
  "-....",			/* 6 six */
  "--...",			/* 7 seven */
  "---..",			/* 8 eight */
  "----.",			/* 9 nine */
  "---...",			/* : colon */
  "-.-.-.",			/* ; semicolon */
  0,				/* < less than */
  "-...-",			/* = double dash */
  0,				/* > greater than */
  "..--..",			/* ? question mark */
  ".--.-.",			/* @ at */
  ".-",  			/* A */
  "-...",			/* B */
  "-.-.",			/* C */
  "-..",			/* D */
  ".",				/* E */
  "..-.",			/* F */
  "--.",			/* G */
  "...",			/* H */
  "..",				/* I */
  ".---",			/* J */
  "-.-",			/* K */
  ".-..",			/* L */
  "--",				/* M */
  "-.",				/* N */
  "---",			/* O */
  ".--.",			/* P */
  "--.-",			/* Q */
  ".-.",			/* R */
  "...",			/* S */
  "-",				/* T */
  "..-",			/* U */
  "...-",			/* V */
  ".--",			/* W */
  "-..-",			/* X */
  "-.--",			/* Y */
  "--..",			/* Z */
  0,				/* [ */
  0,				/* \ */
  0,				/* ] */
  0,				/* ^ */
  "..--.-"			/* _ underscore */
};

static VALUE rb_cQSO, rb_eQSOError;

static void
free_qso(void *ptr);

static size_t
memsize_qso(const void *ptr);

static const rb_data_type_t qso_type = {
  "qso",
  { 0, free_qso, memsize_qso,},
  0, 0,
  RUBY_TYPED_FREE_IMMEDIATELY,
};

static void
freed_qso(void)
{
  rb_raise(rb_eQSOError, "deallocated QSO");
}

#define GetQSO(obj, qsop) do {\
  TypedData_Get_Struct((obj), struct QSO_t, &qso_type, (qsop));\
  if ((qsop) == 0) freed_qso();\
  } while(0)

static void
free_qso(void *ptr)
{
  struct QSO_t *qsop = (struct QSO_t *)ptr;
  if (qsop) {
    memset(qsop, 0, sizeof(struct QSO_t));
    xfree(qsop);
  }
}

static size_t
memsize_qso(const void *ptr)
{
  size_t size = 0;
  const struct QSO_t *qsop = (const struct QSO_t *)ptr;
  if (qsop) {
    size += sizeof(struct QSO_t);
  }
  return size;
}

/*
 * call-seq:
 *    qso.id
 *
 * Return the unique id of the QSO.
 */
static VALUE
qso_id(VALUE obj)
{
  struct QSO_t *qsop;
  GetQSO(obj, qsop);
  return INT2FIX(qsop->d_qsoID);
}

/*
 * call-seq:
 *    qso.logID
 *
 * Return the unique ID of the log this QSO appears in.
 */
static VALUE
qso_logID(VALUE obj)
{
  struct QSO_t *qsop;
  GetQSO(obj, qsop);
  return INT2FIX(qsop->d_logID);
}

/*
 * call-seq:
 *    qso.freq
 *
 * Return the frequency number for this QSO.
 */
static VALUE
qso_freq(VALUE obj)
{
  struct QSO_t *qsop;
  GetQSO(obj, qsop);
  return INT2FIX(qsop->d_frequency);
}

/*
 * call-seq:
 *    qso.band
 *
 * Return the band string for this QSO.
 */
static VALUE
qso_band(VALUE obj)
{
  struct QSO_t *qsop;
  GetQSO(obj, qsop);
  if (qsop->d_band < 0 ||
      qsop->d_band >= (sizeof(s_bandNames)/sizeof(char *)))
    rb_raise(rb_eQSOError, "QSO has an illegal band");
  return rb_str_new2(s_bandNames[qsop->d_band]);
}

/*
 * call-seq:
 *    qso.mode
 *
 * Return the mode string for this QSO.
 */
static VALUE
qso_mode(VALUE obj)
{
  struct QSO_t *qsop;
  GetQSO(obj, qsop);
  if (qsop->d_mode < 0 ||
      qsop->d_mode >= (sizeof(s_modeNames)/sizeof(char *)))
    rb_raise(rb_eQSOError, "QSO has an illegal mode");
  return rb_str_new2(s_modeNames[qsop->d_mode]);
}

/*
 * call-seq:
 *     qso.datetime
 *
 * Return the date and time of the QSO.
 */
static VALUE
qso_datetime(VALUE obj)
{
  struct QSO_t *qsop;
  GetQSO(obj, qsop);
  return rb_time_new(qsop->d_datetime, 0L);
}

static VALUE
qso_exchange_basecall(const struct Exchange_t *e)
{
  return rb_str_new2(e->d_basecall);
}

static VALUE
qso_exchange_callsign(const struct Exchange_t *e)
{
  return rb_str_new2(e->d_callsign);
}

static VALUE
qso_exchange_serial(const struct Exchange_t *e)
{
  return INT2FIX(e->d_serial);
}

static VALUE
qso_exchange_multiplier(const struct Exchange_t *e)
{
  return rb_str_new2(e->d_multiplier);
}

static VALUE
qso_exchange_location(const struct Exchange_t *e)
{
  return rb_str_new2(e->d_location);
}

/*
 * call-seq:
 *     qso.recvd_basecall
 *
 * Return the base callsign of the received exchange.
 */
static VALUE
qso_recvd_basecall(VALUE obj)
{
  struct QSO_t *qsop;
  GetQSO(obj, qsop);
  return qso_exchange_basecall(&(qsop->d_recvd));
}

/*
 * call-seq:
 *     qso.recvd_callsign
 *
 * Return the logged callsign of the received exchange.
 */
static VALUE
qso_recvd_callsign(VALUE obj)
{
  struct QSO_t *qsop;
  GetQSO(obj, qsop);
  return qso_exchange_callsign(&(qsop->d_recvd));
}

/*
 * call-seq:
 *     qso.recvd_serial
 *
 * Return the serial number of the received exchange.
 */
static VALUE
qso_recvd_serial(VALUE obj)
{
  struct QSO_t *qsop;
  GetQSO(obj, qsop);
  return qso_exchange_serial(&(qsop->d_recvd));
}

/*
 * call-seq:
 *     qso.recvd_multiplier
 *
 * Return the multiplier of the received exchange.
 */
static VALUE
qso_recvd_multiplier(VALUE obj)
{
  struct QSO_t *qsop;
  GetQSO(obj, qsop);
  return qso_exchange_multiplier(&(qsop->d_recvd));
}

/*
 * call-seq:
 *     qso.recvd_location
 *
 * Return the logged location of the received exchange.
 */
static VALUE
qso_recvd_location(VALUE obj)
{
  struct QSO_t *qsop;
  GetQSO(obj, qsop);
  return qso_exchange_location(&(qsop->d_recvd));
}

/*
 * call-seq:
 *     qso.sent_basecall
 *
 * Return the base callsign of the sent exchange.
 */
static VALUE
qso_sent_basecall(VALUE obj)
{
  struct QSO_t *qsop;
  GetQSO(obj, qsop);
  return qso_exchange_basecall(&(qsop->d_sent));
}

/*
 * call-seq:
 *     qso.sent_callsign
 *
 * Return the logged callsign of the sent exchange.
 */
static VALUE
qso_sent_callsign(VALUE obj)
{
  struct QSO_t *qsop;
  GetQSO(obj, qsop);
  return qso_exchange_callsign(&(qsop->d_sent));
}

/*
 * call-seq:
 *     qso.sent_serial
 *
 * Return the serial number of the sent exchange.
 */
static VALUE
qso_sent_serial(VALUE obj)
{
  struct QSO_t *qsop;
  GetQSO(obj, qsop);
  return qso_exchange_serial(&(qsop->d_sent));
}

/*
 * call-seq:
 *     qso.sent_multiplier
 *
 * Return the multiplier of the sent exchange.
 */
static VALUE
qso_sent_multiplier(VALUE obj)
{
  struct QSO_t *qsop;
  GetQSO(obj, qsop);
  return qso_exchange_multiplier(&(qsop->d_sent));
}

/*
 * call-seq:
 *     qso.sent_location
 *
 * Return the logged location of the sent exchange.
 */
static VALUE
qso_sent_location(VALUE obj)
{
  struct QSO_t *qsop;
  GetQSO(obj, qsop);
  return qso_exchange_location(&(qsop->d_sent));
}

/*
 * call-seq:
 *     qso.baseLine
 *
 * Return a string that holds the QSO in a Cabrillo line format.
 */
static VALUE
qso_basicLine(VALUE obj)
{
  char buffer[65+4*(MAX_CALLSIGN_CHARS)+4*(MAX_MULTIPLIER_CHARS)];
  struct QSO_t *qsop;
  struct tm result;
  GetQSO(obj, qsop);
  gmtime_r(&(qsop->d_datetime), &result);
  snprintf(buffer,sizeof(buffer),
	   "%5d %-4s %-2s %04d-%02d-%02d %-7s %-7s %4d %-4s %-4s %-7s %-7s %4d %-4s %-4s",
	   qsop->d_frequency,
	   s_bandNames[qsop->d_band],
	   s_modeNames[qsop->d_mode],
	   1900+result.tm_year,
	   1+result.tm_mon,
	   result.tm_mday,
	   qsop->d_sent.d_basecall,
	   qsop->d_sent.d_callsign,
	   qsop->d_sent.d_serial,
	   qsop->d_sent.d_multiplier,
	   qsop->d_sent.d_location,
	   qsop->d_recvd.d_basecall,
	   qsop->d_recvd.d_callsign,
	   qsop->d_recvd.d_serial,
	   qsop->d_recvd.d_multiplier,
	   qsop->d_recvd.d_location);
  return rb_str_new2(buffer);
}


static VALUE
q_to_s(const struct QSO_t *qsop,
     const struct Exchange_t *left,
     const struct Exchange_t *right)
{
  char buffer[82+4*(MAX_CALLSIGN_CHARS)+4*(MAX_MULTIPLIER_CHARS)];
  struct tm result;
  gmtime_r(&(qsop->d_datetime), &result);
  snprintf(buffer,sizeof(buffer),
	   "%7d %5d %5d %-4s %-2s %04d-%02d-%02d %-7s %-7s %4d %-4s %-4s %-7s %-7s %4d %-4s %-4s",
	   qsop->d_qsoID,
	   qsop->d_logID,
	   qsop->d_frequency,
	   s_bandNames[qsop->d_band],
	   s_modeNames[qsop->d_mode],
	   1900+result.tm_year,
	   1+result.tm_mon,
	   result.tm_mday,
	   left->d_basecall,
	   left->d_callsign,
	   left->d_serial,
	   left->d_multiplier,
	   left->d_location,
	   right->d_basecall,
	   right->d_callsign,
	   right->d_serial,
	   right->d_multiplier,
	   right->d_location);
  return rb_str_new2(buffer);
}
    
/*
 * call-seq:
 *     qso.to_s(reverse=false)
 *
 * Return a string representation of the QSO. If reverse is true
 * the sent and received exchanges are reversed.
 */
static VALUE
qso_to_s(int argc, VALUE* argv, VALUE obj)
{
  struct QSO_t *qsop;
  VALUE reversed;
  int isReversed = 0;
  GetQSO(obj, qsop);
  if (rb_scan_args(argc, argv, "01", &reversed) == 1) {
    isReversed = RTEST(reversed);
  }
  if (isReversed) {
    return q_to_s(qsop, &(qsop->d_sent), &(qsop->d_recvd));
  }
 else {
    return q_to_s(qsop, &(qsop->d_recvd), &(qsop->d_sent));
 }
}


/* 
 * call-seq:
 *      qso.fullMatch?(qsob, time)
 *
 * Return true iff qso correctly logged QSO qsob to a given
 * time tolerance in minutes.  This does not require qsob to
 * have correctly received qso's exchange.
 */
static VALUE
qso_fullmatch(VALUE obj, VALUE qso, VALUE time)
{
  if (((T_FIXNUM == TYPE(time)) || (T_BIGNUM == TYPE(time))) &&
      (T_OBJECT == TYPE(qso))) {
    const struct QSO_t *selfp, *qsop;
    const long tolerance = NUM2LONG(time);
    GetQSO(obj, selfp);
    GetQSO(qso, qsop);
    return ((selfp == qsop) ||
	    ((selfp->d_band == qsop->d_band) &&
	     (selfp->d_mode == qsop->d_mode) &&
	     (labs((long)(selfp->d_datetime - qsop->d_datetime)) <=
	      tolerance * 60L) &&
	     (abs(selfp->d_recvd.d_serial - qsop->d_sent.d_serial) <= 1) &&
	     (0 == strcmp(selfp->d_recvd.d_basecall,
			  qsop->d_sent.d_basecall)) &&
	     (0 == strcmp(selfp->d_recvd.d_multiplier,
			  qsop->d_sent.d_multiplier))))
      ? Qtrue : Qfalse;
  }

  rb_raise(rb_eTypeError, "Incorrect arguments to fullMatch?");
}

static int
toCW(const char *src, char *dest)
{
  int result = 0;
  while (*src) {
    if (*src >= 0 && *src < (sizeof(s_CW_MAPPING)/sizeof(char *)) &&
	s_CW_MAPPING[*src]) {
      const int newlen = (int)strlen(s_CW_MAPPING[*src]);
      strcpy(dest, src);
      dest += newlen;
    }
    else {
      *dest = ' ';
      ++dest;
    }
    ++src;
  }
  return result;
}

static double
max_match(const char * const left[],  const int left_len,
	  const char * const right[], const int right_len,
	  const int isCW)
{
  char buffer1[MAX_MULTIPLIER_CHARS*8 + 1];
  char buffer2[MAX_MULTIPLIER_CHARS*8 + 1];
  double result = 0;
  jw_Option opt = jw_option_new();
  int i;
  for(i = 0; i < left_len; ++i) {
    const int length_left = (int)strlen(left[i]);
    const int length_left_cw = (isCW ? toCW(left[i], buffer1) : 0);
    int j;
    for(j = 0; j < right_len; ++j) {
      const int length_right = (int)strlen(right[j]);
      const int length_right_cw = (isCW ? toCW(right[j], buffer2) : 0);
      double tmp = jw_distance(left[i], length_left,
			       right[j], length_right, opt);
      if (tmp > result) {
	result = tmp;
      }
      if (isCW) {
	tmp = jw_distance(buffer1, length_left_cw,
			  buffer2, length_right_cw, opt);
	if (tmp > result) {
	  result = tmp;
	}
      }
    }
  }
  return result;
}

static int
pack_list(const char *s1, const char *s2,
	   const char *list[])
{
  int count = 0;
  if (s1)
    list[count++] = s1;
  if (s1 && s2 && strcmp(s1, s2)) {
    list[count++] = s2;
  }
  return count;
}

#define SERIAL_FULL 1
#define SERIAL_NONE 10

static double
serialNumberCmp(const int sent, const int recvd, const int isCW)
{
  jw_Option opt = jw_option_new();
  char buffer1[12], buffer2[12];
  int len1, len2;
  const int diff = abs(sent-recvd);
  double tmp, result = (diff > SERIAL_FULL)
    ? ((diff >= SERIAL_NONE) ? 0 : (1.0 - ((1.0*diff - SERIAL_FULL)/
					   (1.0*SERIAL_NONE-SERIAL_FULL))))
    : 1.0;
  len1 = snprintf(buffer1, sizeof(buffer1), "%d", sent) - 1;
  len2 = spprintf(buffer2, sizeof(buffer2), "%d", recvd) - 1;
  tmp = jw_distance(buffer1, len1, buffer2, len2, opt);
  if (tmp > result) result = tmp;
  if (isCW) {
    char cw_buffer1[78], cw_buffer2[78];
    len1 = toCW(buffer1, cw_buffer1);
    len2 = toCW(buffer2, cw_buffer2);
    tmp = jw_distance(cw_buffer1, len1, cw_buffer2, len2, opt);
    if (tmp > result) result = tmp;
  }
  return result;
}

void
qso_exchange_probability(const struct Exchange_t * const sent,
			 const struct Exchange_t * const recvd,
			 const int                       isCW,
			 double                         *overallMetric,
			 double                         *callMetric)
{
  const char *sent_list[2];
  const char *recvd_list[2];
  int sent_len = pack_list(sent->d_basecall, sent->d_callsign, sent_list);
  int recvd_len = pack_list(recvd->d_basecall, recvd->d_callsign, recvd_list);
  *overallMetric = 0;
  *callMetric = max_match(sent_list, sent_len, recvd_list, recvd_len, isCW);
  if (*callMetric > 0) {
    *overallMetric = (*callMetric)*
      serialNumberCmp(sent->d_serial, recvd->d_serial, isCW);
    if (*overallMetric > 0) {
      sent_len = pack_list(sent->d_multiplier, sent->d_location, sent_list);
      recvd_len = pack_list(recvd->d_multiplier, recvd->d_location, recvd_list);
      *overallMetric = (*overallMetric) *
	max_match(sent_list, sent_len, recvd_list, recvd_len, isCW);
    }
  }
}



static void
qso_initialize()
{
  
}
	       

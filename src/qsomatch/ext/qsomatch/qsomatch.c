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

/* order must agree with s_bandName */
enum Band_t {
  b_OnePointTwoG,
  b_TenG,
  b_TenM,
  b_OneNineteenG,
  b_OneFortyTwoG,
  b_FifteenM,
  b_OneSixtyM,
  b_TwoPointThreeG,
  b_TwentyM,
  b_TwoTwentyTwoM,
  b_TwoFortyOneG,
  b_TwentyFourG,
  b_TwoM,
  b_ThreePointFourG,
  b_FortyM,
  b_FourThirtyTwoM,
  b_FortySevenG,
  b_FivePointSevenG,
  b_SixM,
  b_SeventyFiveG,
  b_EightyM,
  b_NineZeroTwoM,
  b_Unknown
};

#define MAX_BAND_NAME 8
/* order must match ordering of enum above */
static const char * const s_bandNames[] = {
  "1.2G",
  "10G",
  "10m",
  "119G",
  "142G",
  "15m",
  "160m",
  "2.3G",
  "20m",
  "222",
  "241G",
  "24G",
  "2m",
  "3.4G",
  "40m",
  "432",
  "47G",
  "5.7G",
  "6m",
  "75G",
  "80m",
  "902",
  "unknown"
};

struct StringMap_t {
  const char d_bandName[MAX_BAND_NAME];
  const int  d_bandNum;
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

static VALUE
qso_s_allocate(VALUE klass)
{
  struct QSO_t *qsop;
  VALUE result =  TypedData_Make_Struct(klass, struct QSO_t,
					&qso_type, qsop);
  memset(qsop, 0, sizeof(struct QSO_t));
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
  return e->d_basecall[0] ? rb_str_new2(e->d_basecall) : Qnil;
}

static VALUE
qso_exchange_callsign(const struct Exchange_t *e)
{
  return e->d_callsign[0] ? rb_str_new2(e->d_callsign) : Qnil;
}

static VALUE
qso_exchange_serial(const struct Exchange_t *e)
{
  return (e->d_serial >= 0) ? INT2FIX(e->d_serial) : Qnil;
}

static VALUE
qso_exchange_multiplier(const struct Exchange_t *e)
{
  return e->d_multiplier[0] ? rb_str_new2(e->d_multiplier) : Qnil;
}

static VALUE
qso_exchange_location(const struct Exchange_t *e)
{
  return e->d_location[0] ? rb_str_new2(e->d_location) : Qnil;
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
 *     qso.basicLine
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
  *dest = '\0';
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

static
enum Band_t
qso_lookupBand(VALUE band)
{
  if (T_STRING == TYPE(band)) {
    if ((RSTRING_LEN(band) >= 2) &&
	(RSTRING_LEN(band) < MAX_BAND_NAME)) {
      char bandbuf[MAX_BAND_NAME];
      int l=0, u=sizeof(s_bandMap)/sizeof(struct StringMap_t), m, cmp;
      memcpy(bandbuf, RSTRING_PTR(band), RSTRING_LEN(band));
      bandbuf[RSTRING_LEN(band)] = '\0';
      while (l < u) {		/* binary search */
	m = (l+u) >> 1;
	cmp = strcmp(bandbuf, s_bandMap[m].d_bandName);
	if (cmp > 0) l = m + 1;
	else if (cmp < 0) u = m;
	else
	  return s_bandMap[m].d_bandNum;
      }
    }
  }
  rb_raise(rb_eQSOError, "Illegal QSO band");
  return b_Unknown;
}

static
enum Mode_t
qso_lookupMode(VALUE mode)
{
  if (T_STRING == TYPE(mode)) {
    if (2 == RSTRING_LEN(mode)) {
      char modebuf[3];
      int l=0, u=sizeof(s_modeMap)/sizeof(struct StringMap_t), m, cmp;
      memcpy(modebuf, RSTRING_PTR(mode), 2);
      modebuf[2] = '\0';
      while (l < u) {		/* binary search */
	m = (l+u) >> 1;
	cmp = strcmp(modebuf, s_modeMap[m].d_bandName);
	if (cmp > 0) l = m + 1;
	else if (cmp < 0) u = m;
	else
	  return s_modeMap[m].d_bandNum;
      }
    }
  }
  rb_raise(rb_eQSOError, "Illegal mode error");
  return m_RTTY;
}

static ID s_cToI;

static
time_t
qso_convertTime(VALUE datetime)
{
  VALUE time = rb_funcall(datetime, s_cToI, 0);
  return (time_t)NUM2LONG(time);
}

static void
qso_copystr(char *dest, VALUE str, const int maxchars, const char *field)
{
  if (T_STRING == TYPE(str)) {
    if (maxchars > RSTRING_LEN(str)) {
      memcpy(dest, RSTRING_PTR(str), RSTRING_LEN(str));
      dest[RSTRING_LEN(str)] = '\0';
    }
    else {
      memcpy(dest, RSTRING_PTR(str), maxchars - 1);
      dest[maxchars-1] = '\0';
    }
  }
  else {
    rb_raise(rb_eQSOError, "Incorrect argument for %s\n", field);
  }
}

static
void
fillOutExchange(struct Exchange_t *exch,
		VALUE basecall, VALUE call,
		VALUE serial, VALUE multiplier, VALUE location)
{
  if (NIL_P(basecall)) {
    exch->d_basecall[0] = '\0';	/* zero length string indicates NIL */
  }
  else {
    qso_copystr(exch->d_basecall, basecall, MAX_CALLSIGN_CHARS,"basecall");
  }
  if (NIL_P(call)) {
    exch->d_callsign[0] = '\0';	/* zero length string indicates NIL */
  }
  else {
    qso_copystr(exch->d_callsign, call, MAX_CALLSIGN_CHARS,"callsign");
  }
  if (NIL_P(serial)) {
    exch->d_serial = -1;	/* negative number indicates NIL */
  }
  else {
    exch->d_serial = (int32_t)NUM2LONG(serial);
  }
  if (NIL_P(multiplier)) {
    exch->d_multiplier[0] = '\0'; /* zero length string indicates NIL */
  }
  else {
    qso_copystr(exch->d_multiplier, multiplier, MAX_MULTIPLIER_CHARS, "multiplier");
  }
  if (NIL_P(location)) {
    exch->d_location[0] = '\0';
  }
  else {
    qso_copystr(exch->d_location, location, MAX_MULTIPLIER_CHARS, "location");
  }
}

/*
 * call-seq:
 *      QSO.new(id, logID, frequency, band, mode, datetime,
 *              sent_basecall, sent_call, sent_serial, sent_multiplier, sent_location,
 *              recvd_basecall, recvd_call, recvd_serial, recvd_multiplier, recvd_location)
 *
 * Initialize a new QSO object.
 */
static VALUE
qso_initialize(VALUE obj,	/* self pointer */
	       VALUE id, VALUE logID, VALUE frequency, VALUE band, VALUE mode,
	       VALUE datetime,
	       VALUE sent_basecall, VALUE sent_call, VALUE sent_serial,
	       VALUE sent_multiplier, VALUE sent_location,
	       VALUE recvd_basecall, VALUE recvd_call, VALUE recvd_serial,
	       VALUE recvd_multiplier, VALUE recvd_location)
{
  struct QSO_t *qsop;
  GetQSO(obj, qsop);
  qsop->d_qsoID = (int32_t)NUM2LONG(id);
  qsop->d_logID = (int32_t)NUM2LONG(logID);
  qsop->d_frequency = (int32_t)NUM2LONG(frequency);
  qsop->d_band = qso_lookupBand(band);
  qsop->d_mode = qso_lookupMode(mode);
  qsop->d_datetime = qso_convertTime(datetime);
  fillOutExchange(&(qsop->d_sent),
		  sent_basecall, sent_call, sent_serial,
		  sent_multiplier, sent_location);
  fillOutExchange(&(qsop->d_recvd),
		  recvd_basecall, recvd_call, recvd_serial,
		  recvd_multiplier, recvd_location);
}
	       
void
Init_qsomatch(void)
{
  rb_cQSO = rb_define_class("QSO", rb_cObject);
  rb_eQSOError = rb_define_class("QSOError", rb_eException);
  s_cToI = rb_intern("to_i");
  rb_define_method(rb_cQSO, "initialize", qso_initialize, 16);
  rb_define_method(rb_cQSO, "id", qso_id, 0);
  rb_define_method(rb_cQSO, "logID", qso_logID, 0);
  rb_define_method(rb_cQSO, "freq", qso_freq, 0);
  rb_define_method(rb_cQSO, "band", qso_band, 0);
  rb_define_method(rb_cQSO, "mode", qso_mode, 0);
  rb_define_method(rb_cQSO, "datetime", qso_datetime, 0);
  rb_define_method(rb_cQSO, "recvd_basecall", qso_recvd_basecall, 0);
  rb_define_method(rb_cQSO, "recvd_callsign", qso_recvd_callsign, 0);
  rb_define_method(rb_cQSO, "recvd_serial", qso_recvd_serial, 0);
  rb_define_method(rb_cQSO, "recvd_multiplier", qso_recvd_multiplier, 0);
  rb_define_method(rb_cQSO, "recvd_location", qso_recvd_location, 0);
  rb_define_method(rb_cQSO, "sent_basecall", qso_sent_basecall, 0);
  rb_define_method(rb_cQSO, "sent_callsign", qso_sent_callsign, 0);
  rb_define_method(rb_cQSO, "sent_serial", qso_sent_serial, 0);
  rb_define_method(rb_cQSO, "sent_multiplier", qso_sent_multiplier, 0);
  rb_define_method(rb_cQSO, "sent_location", qso_sent_location, 0);
  rb_define_method(rb_cQSO, "basicLine", qso_basicLine, 0);
  rb_define_method(rb_cQSO, "to_s", qso_to_s, -1);
  rb_define_method(rb_cQSO, "fullmatch?", qso_fullmatch, 2);
}

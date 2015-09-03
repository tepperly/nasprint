/* Copyright (c) 2014 Jian Weihang */

/* MIT License */

/* Permission is hereby granted, free of charge, to any person obtaining */
/* a copy of this software and associated documentation files (the */
/* "Software"), to deal in the Software without restriction, including */
/* without limitation the rights to use, copy, modify, merge, publish, */
/* distribute, sublicense, and/or sell copies of the Software, and to */
/* permit persons to whom the Software is furnished to do so, subject to */
/* the following conditions: */

/* The above copyright notice and this permission notice shall be */
/* included in all copies or substantial portions of the Software. */

/* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, */
/* EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF */
/* MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND */
/* NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE */
/* LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION */
/* OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION */
/* WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE. */

#include <stdlib.h>
#include <ctype.h>
#include "distance.h"
#include "adj_matrix.h"

jw_Option jw_option_new(void)
{
  jw_Option opt;
  opt.adj_table = 0;
  opt.weight = 0.1;
  opt.threshold = 0.7;
  return opt;
}

static inline int
jw_imax(int i, int j)
{
  return (i >= j) ? i : j;
}

static inline int
jw_imin(int i, int j)
{
  return (i <= j) ? i : j;
}

double
jw_distance(const char *s1, int s1_byte_len, const char *s2, int s2_byte_len, jw_Option opt){
  // Guarantee the order (s1 should be longer)
  if (s1_byte_len > s2_byte_len){
    const char *tmp = s1; 
    int tmp2 = s1_byte_len; 
    s1 = s2; s2 = tmp;
    s1_byte_len = s2_byte_len; s2_byte_len = tmp2;
  }
  {
  // Compute jaro distance
    const int window_size = jw_imax(s2_byte_len / 2 - 1, 0);
    const int max_index = s2_byte_len - 1;
    double matches     = 0.0,
      sim_matches = 0.0;
    int transpositions = 0,
      previous_index = -1;
    int i, j;
    for(i = 0; i < s1_byte_len; i++){
      const int left  = jw_imax(i - window_size,0);
      const int right = jw_imin(i + window_size, max_index);
      char matched     = 0,
	   found       = 0,
           sim_matched = 0;
      for(j = left; j <= right; j++){
	if(s1[i] == s2[j]){
	  matched = 1;
	  if(!found && j > previous_index){
	    previous_index = j;
	    found = 1;
	  }
	}
	else {
	  if(opt.adj_table &&
	     jw_adj_matrix_find(opt.adj_table, s1[i], s2[j])) {
	    sim_matched = 1;
	  }
	}
      }
      if (matched) {
	matches++;
	if(!found) transpositions++;
      }
      else {
	if(sim_matched)
	  sim_matches += 3;
      }
    }
    {
      // Don't divide transpositions by 2 since it's been counted directly by above code.
      double similarity = matches;
      if(opt.adj_table) similarity += sim_matches / 10;
      { 
	const double jaro_distance = matches == 0 ? 0 : (similarity / s1_byte_len + similarity / s2_byte_len + (matches - transpositions) / matches) / 3.0;

	// calculate jaro-winkler distance
	const double threshold = opt.threshold, weight = opt.weight;
	int prefix = 0;
	const int max_length = jw_imin(4, s1_byte_len);
	for(i = 0; i < max_length; ++i){
	  if(s1[i] == s2[i]) prefix++;
	  else break;
	}
	return jaro_distance < threshold ? jaro_distance : jaro_distance + ((prefix * weight) * (1 - jaro_distance));
      }
    }
  }
}

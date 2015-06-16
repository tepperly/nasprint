/* Copyright (c) 2014 Jian Weihang */
/* Included modifications by Tom Epperly */

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
#include <string.h>
#include "adj_matrix.h"

const char *DEFAULT_ADJ_TABLE[] = {
  "A","E", "A","I", "A","O", "A","U", "B","V", "E","I", "E","O", "E","U", "I","O", "I","U", "O","U",
  "I","Y", "E","Y", "C","G", "E","F", "W","U", "W","V", "X","K", "S","Z", "X","S", "Q","C", "U","V",
  "M","N", "L","I", "Q","O", "P","R", "I","J", "2","Z", "5","S", "8","B", "1","I", "1","L", "0","O",
  "0","Q", "C","K", "G","J", "E"," ", "Y"," ", "S"," "
};


jw_AdjMatrix* jw_adj_matrix_new(unsigned int capacity){
  jw_AdjMatrix *matrix = malloc(sizeof(jw_AdjMatrix));
  if (matrix) {
    matrix->d_capacity = capacity;
    matrix->d_length = 0;
    matrix->d_maxchar = 0;
    matrix->d_rowstart = NULL;
    matrix->d_colindex = NULL;
  }
  return matrix;
}

static inline char
adj_matrix_min(const char x,
	       const char y)
{
  return (x < y) ? x : y;
}

static inline char
adj_matrix_max(const char x,
	       const char y)
{
  return (x > y) ? x : y;
}

static char
adj_matrix_maxrow(const char * const x,
		  const char * const y,
		  const unsigned int num)
{
  char maxrow = 0u;
  unsigned int i;
  for(i = 0; i < num; ++i) {
    maxrow = adj_matrix_max(maxrow, adj_matrix_min(x[i], y[i]));
  }
  return maxrow;
}

void jw_adj_matrix_add_multiple(jw_AdjMatrix *matrix,
				const char *x,
				const char *y,
				unsigned int num)
{
  if (matrix) {
    if (matrix->d_length) {
    }
    else {
      const unsigned int actualnum = ((num < matrix->d_capacity) ? num : matrix->d_capacity);
      unsigned int i;
      int count = 0;
      char row, column;
      const char maxrow = adj_matrix_maxrow(x, y, actualnum);
      const unsigned int maxrowind = maxrow + 2u;
      matrix->d_colindex = malloc(sizeof(char)*matrix->d_capacity);
      memset(matrix->d_colindex, 0, sizeof(char)*matrix->d_capacity);
      matrix->d_rowstart = malloc(sizeof(int)*maxrowind);
      memset(matrix->d_rowstart, 0, sizeof(int)*maxrowind);
      matrix->d_maxchar = maxrow + 1;
      for(i = 0; i < actualnum; ++i) {
	row = adj_matrix_min(x[i], y[i]);
	++(matrix->d_rowstart[row]);
      }
      for(i = 1; i <= maxrowind; ++i) {
	int tmp = matrix->d_rowstart[i-1];
	matrix->d_rowstart[i-1] = count;
	count += tmp;
      }
      for(i = 0; i < actualnum; ++i) {
	row = adj_matrix_min(x[i], y[i]);
	column = adj_matrix_max(x[i], y[i]);
	for(count = matrix->d_rowstart[row]; count < matrix->d_rowstart[row+1]; ++count) {
	  if (matrix->d_colindex[count] == 0) {
	    matrix->d_colindex[count] = column;
	    break;
	  }
	}
      }
      matrix->d_length += (int)actualnum;
    }
  }
}

char jw_adj_matrix_find(const jw_AdjMatrix *matrix, char x, char y){
  if (matrix && (matrix->d_length > 0)) {
    if (y < x) {			/* x should always be < y */
      char tmp = y;
      y = x;
      x = tmp;
    }
    if (x < matrix->d_maxchar) {
      const int last = matrix->d_rowstart[x+1];
      int j;
      /* assumes d_colindex is unordered */
      for(j = matrix->d_rowstart[x]; j < last; ++j) {
	if (matrix->d_colindex[j] == y) return 1;
      }
    }
  }
  return 0;
}

void jw_adj_matrix_free(jw_AdjMatrix *matrix){
  if (matrix){
    if (matrix->d_rowstart) free(matrix->d_rowstart);
    if (matrix->d_colindex) free(matrix->d_colindex);
    memset(matrix, 0, sizeof(jw_AdjMatrix));
    free(matrix);
  }
}

jw_AdjMatrix* jw_adj_matrix_default(){
  static char first_time = 1;
  static jw_AdjMatrix *ret_matrix;
  if(first_time){
    const unsigned int length = sizeof(DEFAULT_ADJ_TABLE)/sizeof(char*)/2;
    char 
      *x = malloc(sizeof(char)*length), 
      *y = malloc(sizeof(char)*length);
    unsigned i;
    ret_matrix = jw_adj_matrix_new(length);
    for(i = 0; i < length; ++i){
      x[i] = DEFAULT_ADJ_TABLE[i << 1][0];
      y[i] = DEFAULT_ADJ_TABLE[(i << 1) + 1][0];
    }
    jw_adj_matrix_add_multiple(ret_matrix, x, y, length);
    free(x);
    free(y);
    first_time = 0;
  }
  return ret_matrix;
}

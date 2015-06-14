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
#ifndef ADJ_MATRIX_H
#define ADJ_MATRIX_H 1

/**
 * A sparse matrix data structure to hold the adjacency matrix. Because values
 * are either zero or one, the actual value does not need to be stored only
 * the indices of the nonzero entries.
 *
 * http://en.wikipedia.org/wiki/Sparse_matrix#Compressed_row_Storage_.28CRS_or_CSR.29
 */
struct jw_AdjMatrix_t {
  unsigned int     d_capacity;	/* how many elements can this matrix hold */
  unsigned int     d_length;	/* how many elements does it currently have */
  char             d_maxchar;	/* one higher than the maximum Unicode character code */
  int             *d_rowstart;	/* there are d_maxchar + 2 of these */
  char            *d_colindex;	/* there are d_capacity of these */
};

typedef struct jw_AdjMatrix_t jw_AdjMatrix;

jw_AdjMatrix* jw_adj_matrix_new        (unsigned int capacity);
/**
 * adj_matrix_add is very inefficient. It's more efficient to add
 * all the elements in a single call to add_multiple.
 */
void         jw_adj_matrix_add_multiple(jw_AdjMatrix *matrix, 
				        const char *x,
				        const char *y,
				        unsigned int num);
char          jw_adj_matrix_find        (const jw_AdjMatrix *matrix, char x, char y);
void          jw_adj_matrix_free        (jw_AdjMatrix *matrix);
jw_AdjMatrix* jw_adj_matrix_default     (void);

#endif /* ADJ_MATRIX_H */
